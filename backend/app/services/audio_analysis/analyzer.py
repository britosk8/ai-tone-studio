"""Pipeline de análise de áudio para extração de características de timbre."""
import logging
import numpy as np
from scipy.signal import correlate
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

try:
    import librosa
    LIBROSA_AVAILABLE = True
except ImportError:
    LIBROSA_AVAILABLE = False
    logger.warning("librosa não disponível — análise espectral limitada")

from ...models.audio import (
    AudioAnalysisResult,
    SpectralProfile,
    DynamicsProfile,
    EffectPresenceEstimate,
    GainCharacter,
    ConfidenceLevel,
    GuitarRegion,
    MusicSection,
)


class AudioAnalyzer:
    """
    Pipeline de análise de áudio para estimativa de timbre de guitarra.

    LIMITAÇÕES IMPORTANTES:
    - Trabalha com mixagem final, não trilha isolada
    - Estimativas de distorção baseadas em análise espectral, não identificação do equipamento
    - Presença de efeitos (reverb, delay) é estatística, não determinística
    - Nunca identificará o equipamento original usado na gravação
    - Confiança é sempre relativa e deve ser comunicada ao usuário
    """

    # Faixas de frequência para análise EQ (Hz)
    FREQ_BANDS = {
        "bass": (20, 250),
        "low_mid": (250, 800),
        "mid": (800, 2500),
        "high_mid": (2500, 5000),
        "treble": (5000, 20000),
    }

    # Limiar de confiança para análise em mixagem
    MIXED_TRACK_CONFIDENCE_PENALTY = 0.3

    def __init__(self, source_separated_audio: Optional[np.ndarray] = None, source_kind: str = "mix"):
        """
        Args:
            source_separated_audio: Stem Demucs other (não comprova guitarra isolada).
                Se None, usa o arquivo e o tipo de referência declarado em source_kind.
        """
        if source_kind not in {"mix", "isolated", "separated_other"}:
            raise ValueError("Tipo de referência inválido")
        self.source_kind = "separated_other" if source_separated_audio is not None else source_kind
        self.using_isolated = self.source_kind == "isolated"
        self._quality_ok = False
        self.using_separated = source_separated_audio is not None
        self._separated_audio = source_separated_audio

    def analyze(self, audio_path: Path, sr: int = 22050) -> AudioAnalysisResult:
        """Analisa arquivo de áudio e retorna resultado estruturado."""
        if not LIBROSA_AVAILABLE:
            raise RuntimeError("librosa é necessário para análise de áudio")

        logger.info(f"Analisando: {audio_path}")

        # Carrega áudio
        y, sr = librosa.load(str(audio_path), sr=sr, mono=True)
        if len(y) < sr or not np.isfinite(y).all() or np.max(np.abs(y)) < 1e-8:
            raise ValueError("O áudio deve ter pelo menos um segundo e conter sinal audível.")
        duration = librosa.get_duration(y=y, sr=sr)

        # Usa áudio separado se disponível
        y_guitar = self._separated_audio if self.using_separated else y

        if not np.isfinite(y_guitar).all() or len(y_guitar) < sr:
            raise ValueError("Referência de guitarra inválida")
        self._quality_ok = (len(y_guitar) >= 10 * sr
                            and float(np.sqrt(np.mean(y_guitar ** 2))) >= 0.001
                            and float(np.mean(np.abs(y_guitar) >= 0.99)) < 0.005)

        # Análise espectral
        spectral = self._analyze_spectral(y_guitar, sr)
        dynamics = self._analyze_dynamics(y_guitar, sr)
        effects = self._estimate_effects(y_guitar, sr, spectral, dynamics)
        bpm, bpm_conf = self._estimate_bpm(y, sr)

        # Confiança geral depende de referência isolada declarada e qualidade mínima
        overall_conf = self._compute_overall_confidence(
            spectral, dynamics, effects, self.using_isolated and self._quality_ok
        )

        limitations = []
        if not self.using_isolated:
            limitations.append(
                "Análise realizada em referência com múltiplos instrumentos. "
                "Estimativas de timbre de guitarra têm precisão reduzida."
            )
        if self.source_kind == "separated_other":
            limitations.append("A separação Demucs retornou 'other', que também pode conter teclado e outros instrumentos; não comprova guitarra isolada.")
        if not self._quality_ok:
            limitations.append("Sinal curto, muito baixo ou com clipping: confiança reduzida. Prefira 10 segundos ou mais, audíveis e sem saturação de captura.")
        if self.using_isolated:
            limitations.append("Referência declarada como guitarra isolada pelo usuário; essa declaração não é verificada automaticamente.")
        limitations.append("Confiança é qualitativa sobre a estimativa, não um percentual de fidelidade ao original nem identificação do modelo de equipamento.")
        limitations.append(
            "O timbre gerado é uma aproximação baseada em características espectrais, "
            "não uma identificação do equipamento original da gravação."
        )

        return AudioAnalysisResult(
            duration_seconds=duration,
            sample_rate=sr,
            bpm_estimate=bpm,
            bpm_confidence=bpm_conf,
            source_separation_available=self.using_separated,
            source_separation_model="demucs" if self.using_separated else None,
            overall_spectral=spectral,
            overall_dynamics=dynamics,
            effect_estimates=effects,
            overall_confidence=overall_conf,
            limitations=limitations,
            reference_profile=self._reference_profile(y_guitar,sr),
        )

    def _reference_profile(self,y,sr):
        from .tone_comparison import fingerprint
        try:
            profile=fingerprint(y,sr)
            profile['source_kind']='isolated' if self.using_isolated else 'mix'
            return profile
        except ValueError:
            return {}

    def _analyze_spectral(self, y: np.ndarray, sr: int) -> SpectralProfile:
        """Calcula perfil espectral por bandas de frequência."""
        # STFT para análise de energia por banda
        S = np.abs(librosa.stft(y))
        freqs = librosa.fft_frequencies(sr=sr)

        band_energies = {}
        for band_name, (f_low, f_high) in self.FREQ_BANDS.items():
            mask = (freqs >= f_low) & (freqs <= f_high)
            if mask.any():
                band_power = S[mask, :].mean()
                band_energies[band_name] = float(band_power)
            else:
                band_energies[band_name] = 0.0

        # Normaliza energias para [0, 1]
        max_energy = max(band_energies.values()) or 1.0
        normalized = {k: v / max_energy for k, v in band_energies.items()}

        # Centroide espectral
        centroid = librosa.feature.spectral_centroid(y=y, sr=sr)
        centroid_mean = float(centroid.mean())

        brightness = min(1.0, centroid_mean / 5000.0)

        return SpectralProfile(
            bass_energy=normalized.get("bass", 0),
            low_mid_energy=normalized.get("low_mid", 0),
            mid_energy=normalized.get("mid", 0),
            high_mid_energy=normalized.get("high_mid", 0),
            treble_energy=normalized.get("treble", 0),
            spectral_centroid_hz=centroid_mean,
            brightness=brightness,
        )

    def _analyze_dynamics(self, y: np.ndarray, sr: int) -> DynamicsProfile:
        """Calcula perfil dinâmico."""
        rms = librosa.feature.rms(y=y)[0]
        rms_mean = float(rms.mean())
        rms_db = float(librosa.amplitude_to_db(np.array([rms_mean]))[0])
        peak_db = float(librosa.amplitude_to_db(np.array([np.abs(y).max()]))[0])
        dynamic_range = peak_db - rms_db

        # Transientes via onset strength
        onset_env = librosa.onset.onset_strength(y=y, sr=sr)
        transient_strength = float(np.percentile(onset_env, 90)) / (float(onset_env.max()) + 1e-6)

        # Estimativa de compressão: baixo DR indica compressão
        compression_estimate = max(0.0, min(1.0, 1.0 - (dynamic_range / 40.0)))

        # Estimativa de sustain: energia que se mantém após transientes
        sustain_estimate = float(np.std(rms) / (rms_mean + 1e-6))
        sustain_estimate = max(0.0, min(1.0, 1.0 - sustain_estimate))

        return DynamicsProfile(
            rms_db=rms_db,
            peak_db=peak_db,
            dynamic_range_db=dynamic_range,
            transient_strength=transient_strength,
            compression_estimate=compression_estimate,
            sustain_estimate=sustain_estimate,
        )

    def _estimate_effects(
        self, y: np.ndarray, sr: int, spectral: SpectralProfile, dynamics: DynamicsProfile
    ) -> EffectPresenceEstimate:
        """Estima presença de efeitos com base em características espectrais."""

        # Distorção estimada por harmônicos e centroide
        distortion_level, gain_char = self._estimate_distortion(y, sr, spectral)

        # Reverb: presença de cauda longa no espectro
        reverb_present, reverb_amount = self._estimate_reverb(y, sr)

        # Delay: correlação com delay temporal
        delay_present, delay_ms = self._estimate_delay(y, sr)

        # Chorus: modulação de pitch no espectro
        chorus_present = self._estimate_chorus(y, sr)

        # Compressão
        compression_present = dynamics.compression_estimate > 0.4

        # Confiança é baixa para mixagem completa
        conf = ConfidenceLevel.MEDIUM if self.using_isolated and self._quality_ok else ConfidenceLevel.LOW

        return EffectPresenceEstimate(
            distortion_level=distortion_level,
            gain_character=gain_char,
            gain_confidence=conf,
            reverb_present=reverb_present,
            reverb_amount=reverb_amount,
            reverb_confidence=ConfidenceLevel.LOW,
            delay_present=delay_present,
            delay_ms_estimate=delay_ms,
            delay_confidence=ConfidenceLevel.LOW,
            chorus_present=chorus_present,
            chorus_confidence=ConfidenceLevel.SPECULATIVE,
            wah_present=False,
            wah_confidence=ConfidenceLevel.SPECULATIVE,
            compression_present=compression_present,
            compression_confidence=ConfidenceLevel.LOW,
        )

    def _estimate_distortion(
        self, y: np.ndarray, sr: int, spectral: SpectralProfile
    ) -> tuple[float, GainCharacter]:
        """
        Estima nível de distorção via análise de harmônicos e espectro.
        Alta energia em harmônicos ímpares = mais distorção.
        """
        # Zero crossing rate como proxy de distorção
        zcr = librosa.feature.zero_crossing_rate(y)[0]
        zcr_mean = float(zcr.mean())

        # Espectral flatness: mais flat = mais ruído/distorção
        flatness = librosa.feature.spectral_flatness(y=y)[0]
        flatness_mean = float(flatness.mean())

        # Combinação de métricas para estimar distorção
        # ZCR alto + flatness alta = mais distorção (heurística)
        distortion_score = (zcr_mean * 2 + flatness_mean) / 3.0
        distortion_level = min(1.0, distortion_score * 5.0)

        if distortion_level < 0.15:
            char = GainCharacter.CLEAN
        elif distortion_level < 0.35:
            char = GainCharacter.CRUNCH
        elif distortion_level < 0.55:
            char = GainCharacter.OVERDRIVE
        elif distortion_level < 0.75:
            char = GainCharacter.HIGH_GAIN
        else:
            char = GainCharacter.LEAD

        return distortion_level, char

    def _estimate_reverb(self, y: np.ndarray, sr: int) -> tuple[bool, float]:
        """Estima presença de reverb pela cauda de decaimento."""
        # Autocorrelação para detectar decaimento longo
        hop_length = 512
        rms = librosa.feature.rms(y=y, hop_length=hop_length)[0]

        # Analisa taxa de decaimento do RMS
        if len(rms) < 10:
            return False, 0.0

        # RT60 aproximado: tempo para RMS cair 60dB
        rms_db = librosa.amplitude_to_db(rms + 1e-6)
        peak_idx = np.argmax(rms_db)
        tail = rms_db[peak_idx:]

        if len(tail) < 3:
            return False, 0.0

        decay_rate = (tail[0] - tail[-1]) / (len(tail) * hop_length / sr + 1e-6)
        reverb_amount = max(0.0, min(1.0, 1.0 - (decay_rate / 60.0)))
        reverb_present = reverb_amount > 0.2

        return reverb_present, reverb_amount

    def _estimate_delay(self, y: np.ndarray, sr: int) -> tuple[bool, Optional[float]]:
        """Estimativa muito básica de delay por autocorrelação."""
        # Autocorrelação do sinal
        y_short = y[:sr * 3]  # Primeiros 3 segundos
        correlation = correlate(y_short, y_short, mode="full", method="fft")
        correlation = correlation[len(correlation) // 2:]
        correlation /= correlation[0] + 1e-6

        # Procura picos secundários (excluindo zero-lag)
        min_lag_samples = int(0.05 * sr)  # Min 50ms
        max_lag_samples = int(1.0 * sr)   # Max 1000ms

        search_region = correlation[min_lag_samples:max_lag_samples]
        if len(search_region) == 0:
            return False, None

        peak = float(search_region.max())
        if peak > 0.3:
            peak_idx = int(np.argmax(search_region)) + min_lag_samples
            delay_ms = (peak_idx / sr) * 1000.0
            return True, delay_ms

        return False, None

    def _estimate_chorus(self, y: np.ndarray, sr: int) -> bool:
        """Variação de notas não comprova chorus; não o habilita automaticamente."""
        return False

    def _estimate_bpm(self, y: np.ndarray, sr: int) -> tuple[Optional[float], ConfidenceLevel]:
        """Estima BPM via detecção de onset."""
        try:
            tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
            if isinstance(tempo, np.ndarray):
                tempo = float(tempo[0]) if len(tempo) > 0 else None
            else:
                tempo = float(tempo)

            if tempo and 40 <= tempo <= 250:
                return tempo, ConfidenceLevel.MEDIUM
            return tempo, ConfidenceLevel.LOW
        except Exception as e:
            logger.warning(f"Falha na estimativa de BPM: {e}")
            return None, ConfidenceLevel.SPECULATIVE

    def _compute_overall_confidence(
        self,
        spectral: SpectralProfile,
        dynamics: DynamicsProfile,
        effects: EffectPresenceEstimate,
        isolated_quality_ok: bool,
    ) -> ConfidenceLevel:
        """Confiança geral conservadora."""
        if isolated_quality_ok:
            return ConfidenceLevel.MEDIUM
        return ConfidenceLevel.LOW
