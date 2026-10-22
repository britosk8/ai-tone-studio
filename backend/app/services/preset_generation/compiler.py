"""
PresetCompiler: transforma análise de áudio em preset validado para o dispositivo.

Responsabilidades:
- Traduzir características espectrais/dinâmicas em parâmetros de efeito
- Validar todos os parâmetros contra o catálogo do dispositivo
- Garantir que nenhum efeito ou parâmetro inexistente seja gerado
- Gerar tanto preset de guitarra base quanto solo
"""
import logging
from typing import Optional
from uuid import uuid4

from ...models.audio import AudioAnalysisResult, GainCharacter, ConfidenceLevel
from ...models.devices import DeviceModel, EffectType, PresetRole
from ...models.preset import (
    Preset, PresetEffectChain, EffectBlock, ParameterValue, PresetPair
)
from ..device_catalog.loader import CatalogLoader

logger = logging.getLogger(__name__)


class PresetCompiler:
    """
    Compilador de presets: análise de áudio → preset validado para hardware.

    Princípios:
    1. Nunca gerar parâmetros fora dos limites do catálogo
    2. Nunca usar modelos de amp/efeito não existentes no dispositivo
    3. Ser conservador nas estimativas — é melhor um preset funcional
       do que um "perfeito no papel" mas incorreto
    4. Comunicar claramente o nível de confiança de cada decisão
    """

    def __init__(self, catalog_loader: CatalogLoader):
        self.catalog = catalog_loader

    def compile_pair(
        self,
        analysis: AudioAnalysisResult,
        rhythm_device: DeviceModel,
        lead_device: DeviceModel,
        artist: Optional[str] = None,
        song_title: Optional[str] = None,
    ) -> PresetPair:
        """Compila par de presets (base + solo) a partir da análise."""

        if not self.catalog.is_supported(rhythm_device):
            raise ValueError(
                f"Dispositivo {rhythm_device.value} ainda não tem catálogo validado. "
                f"Transfira manualmente usando o guia exportado."
            )
        if not self.catalog.is_supported(lead_device):
            raise ValueError(
                f"Dispositivo {lead_device.value} ainda não tem catálogo validado."
            )

        rhythm_preset = self._compile_rhythm_preset(
            analysis, rhythm_device, artist, song_title
        )
        lead_preset = self._compile_lead_preset(
            analysis, lead_device, artist, song_title
        )

        return PresetPair(
            track_id=analysis.track_id,
            rhythm_preset=rhythm_preset,
            lead_preset=lead_preset,
            analysis_summary=self._build_analysis_summary(analysis),
        )

    def _compile_rhythm_preset(
        self,
        analysis: AudioAnalysisResult,
        device: DeviceModel,
        artist: Optional[str],
        song_title: Optional[str],
    ) -> Preset:
        """
        Preset de guitarra base: foco em definição, riff, palm muting.
        Prioriza clareza de acordes, controle de graves, noise gate adequado.
        """
        effects = analysis.effect_estimates
        spectral = analysis.overall_spectral
        dynamics = analysis.overall_dynamics

        blocks: list[EffectBlock] = []
        slot = 0
        limitations: list[str] = []

        # 1. Noise Gate — quase sempre útil para guitarra base
        ng_params = self._map_noise_gate_rhythm(dynamics)
        ng_model = self.catalog.get_effect_model(device, EffectType.NOISE_GATE, 0)
        if ng_model:
            if ng_model["name"] == "AI Gate":
                ng_params = {"Gate": ng_params["threshold"], "Bias": 50}
            blocks.append(EffectBlock(
                slot=slot,
                effect_type=EffectType.NOISE_GATE,
                model_id=str(ng_model["id"]),
                model_name=ng_model["name"],
                enabled=True,
                parameters=self._build_parameters(ng_model, ng_params),
                generated_confidence=ConfidenceLevel.SPECULATIVE,
                generation_rationale="Gate sugerido para controle de ruído; não identificado no áudio. Ajuste ao ruído real da sua guitarra",
            ))
            slot += 1

        # 2. Compressor — se compressão detectada
        if effects.compression_present:
            comp_params = self._map_compressor(dynamics)
            comp_model = self.catalog.get_effect_model(device, EffectType.COMPRESSOR, 0)
            if comp_model:
                blocks.append(EffectBlock(
                    slot=slot,
                    effect_type=EffectType.COMPRESSOR,
                    model_id=str(comp_model["id"]),
                    model_name=comp_model["name"],
                    enabled=True,
                    parameters=self._build_parameters(comp_model, comp_params),
                    generated_confidence=effects.compression_confidence,
                    generation_rationale="Dinâmica sugere compressão; a masterização e outros instrumentos também podem explicar a medição",
                ))
                slot += 1

        # 3. Drive/Distorção
        drive_params = self._map_drive_rhythm(effects, spectral)
        drive_model = self.catalog.get_drive_model(device, effects.gain_character)
        if drive_model:
            blocks.append(EffectBlock(
                slot=slot,
                effect_type=EffectType.DRIVE,
                model_id=str(drive_model["id"]),
                model_name=drive_model["name"],
                enabled=effects.distortion_level > 0.2,
                parameters=self._build_parameters(drive_model, drive_params),
                generated_confidence=effects.gain_confidence,
                generation_rationale=f"Timbre estimado: {effects.gain_character.value}",
            ))
            slot += 1

        # 4. Amplificador
        amp_params = self._map_amp_rhythm(effects, spectral, dynamics)
        amp_model = self.catalog.get_amp_model(device, effects.gain_character)
        if amp_model:
            blocks.append(EffectBlock(
                slot=slot,
                effect_type=EffectType.AMP,
                model_id=str(amp_model["id"]),
                model_name=amp_model["name"],
                enabled=True,
                parameters=self._build_parameters(amp_model, amp_params),
                generated_confidence=effects.gain_confidence,
                generation_rationale=f"Amp compatível com timbre {effects.gain_character.value}",
            ))
            slot += 1

        # 5. Cabinet
        cab_model = self.catalog.get_cabinet_model(device, effects.gain_character)
        if cab_model:
            blocks.append(EffectBlock(
                slot=slot,
                effect_type=EffectType.CABINET,
                model_id=str(cab_model["id"]),
                model_name=cab_model["name"],
                enabled=True,
                parameters=[],
                generated_confidence=ConfidenceLevel.LOW,
                generation_rationale="Cabinet padrão para o tipo de amp selecionado",
            ))
            slot += 1
            limitations.append("Seleção de cabinet é uma estimativa — ajuste de acordo com o som da sua guitarra")

        # 6. Delay/Reverb — mínimos para guitarra base
        if effects.reverb_present and effects.reverb_amount > 0.3:
            reverb_params = self._map_reverb_minimal()
            reverb_model = self.catalog.get_effect_model(device, EffectType.REVERB, 0)
            if reverb_model:
                blocks.append(EffectBlock(
                    slot=slot,
                    effect_type=EffectType.REVERB,
                    model_id=str(reverb_model["id"]),
                    model_name=reverb_model["name"],
                    enabled=True,
                    parameters=self._build_parameters(reverb_model, reverb_params),
                    generated_confidence=effects.reverb_confidence,
                    generation_rationale="Leve reverb detectado — reduzido para não sujar o riff",
                ))
                slot += 1

        song_label = " — ".join(value for value in (artist, song_title) if value) or "Música importada"

        return Preset(
            name=f"Base - {song_label}",
            role=PresetRole.RHYTHM,
            device_model=device,
            catalog_version=self.catalog.get_catalog_version(device),
            artist=artist,
            song_title=song_title,
            bpm=analysis.bpm_estimate,
            effect_chain=PresetEffectChain(blocks=blocks),
            overall_confidence=analysis.overall_confidence,
            generation_summary=self._build_rhythm_summary(effects, spectral),
            limitations_noted=limitations + analysis.limitations,
            analysis_warnings=analysis.warnings,
        )

    def _compile_lead_preset(
        self,
        analysis: AudioAnalysisResult,
        device: DeviceModel,
        artist: Optional[str],
        song_title: Optional[str],
    ) -> Preset:
        """
        Preset de guitarra solo: foco em lead, sustain, destaque no mix.
        Prioriza gain, sustain, EQ com presença, delay e reverb para expressão.
        """
        effects = analysis.effect_estimates
        spectral = analysis.overall_spectral
        dynamics = analysis.overall_dynamics

        blocks: list[EffectBlock] = []
        slot = 0
        limitations: list[str] = []

        # 1. Noise Gate — mais sutil para solo
        ng_params = self._map_noise_gate_lead(dynamics)
        ng_model = self.catalog.get_effect_model(device, EffectType.NOISE_GATE, 0)
        if ng_model:
            if ng_model["name"] == "AI Gate":
                ng_params = {"Gate": ng_params["threshold"], "Bias": 50}
            blocks.append(EffectBlock(
                slot=slot,
                effect_type=EffectType.NOISE_GATE,
                model_id=str(ng_model["id"]),
                model_name=ng_model["name"],
                enabled=True,
                parameters=self._build_parameters(ng_model, ng_params),
                generated_confidence=ConfidenceLevel.SPECULATIVE,
                generation_rationale="Gate sugerido para controle de ruído; não identificado no áudio. Preserve as notas longas ao ajustar",
            ))
            slot += 1

        # 2. Drive — com mais ganho para sustain no solo
        drive_params = self._map_drive_lead(effects, spectral)
        drive_model = self.catalog.get_drive_model(device, effects.gain_character)
        if drive_model:
            blocks.append(EffectBlock(
                slot=slot,
                effect_type=EffectType.DRIVE,
                model_id=str(drive_model["id"]),
                model_name=drive_model["name"],
                enabled=effects.distortion_level > 0.2,
                parameters=self._build_parameters(drive_model, drive_params),
                generated_confidence=effects.gain_confidence,
                generation_rationale=f"Drive condicionado à distorção estimada ({effects.gain_character.value}); o papel solo não implica distorção",
            ))
            slot += 1

        # 3. Amplificador — boost de presença para lead
        amp_params = self._map_amp_lead(effects, spectral, dynamics)
        amp_model = self.catalog.get_amp_model(device, effects.gain_character)
        if amp_model:
            blocks.append(EffectBlock(
                slot=slot,
                effect_type=EffectType.AMP,
                model_id=str(amp_model["id"]),
                model_name=amp_model["name"],
                enabled=True,
                parameters=self._build_parameters(amp_model, amp_params),
                generated_confidence=effects.gain_confidence,
                generation_rationale=f"Amp compatível com o caráter estimado {effects.gain_character.value}; modelo original não identificado",
            ))
            slot += 1

        # 4. Cabinet
        cab_model = self.catalog.get_cabinet_model(device, effects.gain_character)
        if cab_model:
            blocks.append(EffectBlock(
                slot=slot,
                effect_type=EffectType.CABINET,
                model_id=str(cab_model["id"]),
                model_name=cab_model["name"],
                enabled=True,
                parameters=[],
                generated_confidence=ConfidenceLevel.LOW,
                generation_rationale="Cabinet escolhido para o caráter estimado; modelo original não identificado",
            ))
            slot += 1

        # 5. Modulação (chorus/flanger) — se detectada
        if effects.chorus_present:
            mod_params = {"rate": 40, "depth": 30, "mix": 25}
            mod_model = self.catalog.get_effect_model(device, EffectType.MODULATION, 0)
            if mod_model:
                blocks.append(EffectBlock(
                    slot=slot,
                    effect_type=EffectType.MODULATION,
                    model_id=str(mod_model["id"]),
                    model_name=mod_model["name"],
                    enabled=effects.chorus_confidence in (ConfidenceLevel.MEDIUM, ConfidenceLevel.HIGH),
                    parameters=self._build_parameters(mod_model, mod_params),
                    generated_confidence=effects.chorus_confidence,
                    generation_rationale="Modulação apenas sugerida; baixa confiança mantém o bloco desligado para não alterar o timbre sem evidência",
                ))
                slot += 1

        # 6. Delay — fundamental para solo
        delay_params = self._map_delay_lead(effects, analysis.bpm_estimate)
        delay_model = self.catalog.get_effect_model(device, EffectType.DELAY, 0)
        if delay_model:
            blocks.append(EffectBlock(
                slot=slot,
                effect_type=EffectType.DELAY,
                model_id=str(delay_model["id"]),
                model_name=delay_model["name"],
                enabled=effects.delay_present,
                parameters=self._build_parameters(delay_model, delay_params),
                generated_confidence=effects.delay_confidence,
                generation_rationale="Delay para expressão no solo",
            ))
            slot += 1

        # 7. Reverb
        reverb_params = self._map_reverb_lead(effects)
        reverb_model = self.catalog.get_effect_model(device, EffectType.REVERB, 0)
        if reverb_model:
            blocks.append(EffectBlock(
                slot=slot,
                effect_type=EffectType.REVERB,
                model_id=str(reverb_model["id"]),
                model_name=reverb_model["name"],
                enabled=effects.reverb_present,
                parameters=self._build_parameters(reverb_model, reverb_params),
                generated_confidence=effects.reverb_confidence,
                generation_rationale="Reverb para ambiência do solo",
            ))
            slot += 1

        song_label = " — ".join(value for value in (artist, song_title) if value) or "Música importada"

        return Preset(
            name=f"Solo - {song_label}",
            role=PresetRole.LEAD,
            device_model=device,
            catalog_version=self.catalog.get_catalog_version(device),
            artist=artist,
            song_title=song_title,
            bpm=analysis.bpm_estimate,
            effect_chain=PresetEffectChain(blocks=blocks),
            overall_confidence=analysis.overall_confidence,
            generation_summary=self._build_lead_summary(effects, spectral),
            limitations_noted=limitations + analysis.limitations,
            analysis_warnings=analysis.warnings,
        )

    # ── Mapeamentos de parâmetros ──────────────────────────────────────────────

    def _map_noise_gate_rhythm(self, dynamics) -> dict:
        """Noise gate mais agressivo para base."""
        # Mais compressão = sinal mais consistente = gate mais agressivo
        threshold = int(20 + dynamics.compression_estimate * 30)
        return {"threshold": min(threshold, 60), "decay": 50}

    def _map_noise_gate_lead(self, dynamics) -> dict:
        """Noise gate sutil para solo — não cortar notas longas."""
        return {"threshold": 15, "decay": 70}

    def _map_compressor(self, dynamics) -> dict:
        """Parâmetros de compressor baseados na dinâmica detectada."""
        ratio = int(40 + dynamics.compression_estimate * 40)
        return {
            "threshold": 50,
            "ratio": min(ratio, 80),
            "attack": 40,
            "release": 60,
            "sustain": int(30 + dynamics.sustain_estimate * 40),
            "blend": 100,
            "level": 55,
        }

    def _map_drive_rhythm(self, effects, spectral) -> dict:
        """Drive para guitarra base: moderado, focado em definição."""
        drive_raw = effects.distortion_level
        # Base: levemente menos drive que o detectado para clareza de acorde
        drive = int(drive_raw * 65)
        tone = int(40 + spectral.brightness * 30)
        return {"drive": max(10, drive), "tone": tone, "level": 70}

    def _map_drive_lead(self, effects, spectral) -> dict:
        """Drive para solo: mais gain para sustain."""
        drive_raw = effects.distortion_level
        drive = int(drive_raw * 80)
        tone = int(45 + spectral.brightness * 35)
        return {"drive": max(20, drive), "tone": tone, "level": 72}

    def _map_amp_rhythm(self, effects, spectral, dynamics) -> dict:
        """Parâmetros de amp para guitarra base."""
        gain = int(effects.distortion_level * 70)
        bass = int(35 + spectral.bass_energy * 40)
        middle = int(50 + spectral.mid_energy * 20)
        treble = int(40 + spectral.treble_energy * 30)
        presence = int(40 + spectral.brightness * 25)
        return {
            "gain": max(10, gain),
            "bass": min(bass, 75),
            "middle": middle,
            "treble": treble,
            "presence": presence,
            "volume": 65,
        }

    def _map_amp_lead(self, effects, spectral, dynamics) -> dict:
        """Parâmetros de amp para guitarra solo — mais presença."""
        gain = int(effects.distortion_level * 70)
        bass = int(30 + spectral.bass_energy * 30)
        middle = int(55 + spectral.mid_energy * 25)
        treble = int(50 + spectral.treble_energy * 30)
        presence = int(55 + spectral.brightness * 30)
        return {
            "gain": max(10, gain),
            "bass": min(bass, 65),
            "middle": middle,
            "treble": treble,
            "presence": min(presence, 85),
            "volume": 70,
        }

    def _map_delay_lead(self, effects, bpm: Optional[float]) -> dict:
        """Parâmetros de delay para solo, com tap tempo se BPM disponível."""
        if bpm and effects.delay_ms_estimate is None:
            # Dotted-eighth note delay: (60000/bpm) * 0.75
            delay_ms = int((60000 / bpm) * 0.75)
        elif effects.delay_ms_estimate:
            delay_ms = int(effects.delay_ms_estimate)
        else:
            delay_ms = 350

        delay_ms = max(50, min(delay_ms, 1000))
        return {
            "time": delay_ms,
            "feedback": 25,
            "mix": 20,
        }

    def _map_reverb_minimal(self) -> dict:
        return {"decay": 25, "mix": 15, "pre_delay": 10}

    def _map_reverb_lead(self, effects) -> dict:
        reverb_mix = int(effects.reverb_amount * 35)
        return {
            "decay": 40,
            "mix": max(10, min(reverb_mix, 35)),
            "pre_delay": 15,
        }

    # ── Utilitários ─────────────────────────────────────────────────────────

    def _build_parameters(self, model: dict, values: dict) -> list[ParameterValue]:
        """Constrói lista de ParameterValue validada contra o catálogo.
        Comparação de chaves case-insensitive para compatibilidade com catálogos
        que usam Title Case (ex: 'Threshold') ou lower case (ex: 'threshold').
        """
        params = []
        catalog_params = model.get("parameters", {})
        # Índice de catálogo com chaves em lower para busca case-insensitive
        normalize = lambda key: key.lower().replace("-", "_").replace(" ", "_")
        catalog_lower = {normalize(k): (k, v) for k, v in catalog_params.items()}
        aliases = {"drive": "gain", "volume": "level", "presence": "pres", "feedback": "fb", "rate": "speed"}

        for param_name, raw_value in values.items():
            lookup = param_name.lower().replace("-", "_").replace(" ", "_")
            if lookup not in catalog_lower:
                lookup = aliases.get(lookup, lookup)
            # Tenta match exato primeiro, depois case-insensitive
            if param_name in catalog_params:
                catalog_key = param_name
                spec = catalog_params[param_name]
            elif lookup in catalog_lower:
                catalog_key, spec = catalog_lower[lookup]
            else:
                logger.debug(f"Parâmetro '{param_name}' não no catálogo de {model.get('name', '?')}, ignorando")
                continue

            p_min = spec.get("min", 0)
            p_max = spec.get("max", 100)
            clamped = max(p_min, min(float(raw_value), p_max))
            unit = spec.get("unit", "")

            params.append(ParameterValue(
                name=catalog_key,
                raw_value=clamped,
                display_value=f"{clamped:.0f}{(' ' + unit) if unit else ''}",
                unit=unit if unit else None,
                min_value=p_min, max_value=p_max, step=spec.get("step", 1),
            ))

        return params

    def _build_analysis_summary(self, analysis: AudioAnalysisResult) -> str:
        e = analysis.effect_estimates
        s = analysis.overall_spectral
        parts = [
            f"BPM estimado: {analysis.bpm_estimate:.0f}" if analysis.bpm_estimate else "BPM: não detectado",
            f"Timbre: {e.gain_character.value}",
            f"Distorção: {e.distortion_level:.0%}",
            f"Brilho: {'alto' if s.brightness > 0.6 else 'médio' if s.brightness > 0.3 else 'escuro'}",
            f"Confiança geral: {analysis.overall_confidence.value}",
        ]
        return " | ".join(parts)

    def _build_rhythm_summary(self, effects, spectral) -> str:
        return (
            f"Preset de guitarra base gerado para timbre {effects.gain_character.value}. "
            f"Distorção estimada em {effects.distortion_level:.0%}. "
            f"Parâmetros ajustados para definição de acorde e clareza de riff. "
            f"Confiança: {effects.gain_confidence.value}."
        )

    def _build_lead_summary(self, effects, spectral) -> str:
        return (
            f"Preset de guitarra solo gerado para timbre {effects.gain_character.value}. "
            f"Gain e presença aumentados para destaque do solo no mix. "
            f"Delay calculado {'a partir do BPM estimado' if effects.delay_ms_estimate is None else 'a partir de padrão detectado'}. "
            f"Confiança: {effects.gain_confidence.value}."
        )
