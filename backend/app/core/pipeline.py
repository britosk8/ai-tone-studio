"""Pipeline principal de análise e geração de presets."""
import asyncio
import logging
import shutil
import tempfile
from pathlib import Path
from typing import Optional

from ..models.audio import AudioAnalysisResult, MusicTrack
from ..models.devices import DeviceModel
from ..models.preset import PresetPair
from ..services.audio_analysis.analyzer import AudioAnalyzer
from ..services.audio_analysis.source_separator import SourceSeparator
from ..services.device_catalog.loader import CatalogLoader
from ..services.preset_generation.compiler import PresetCompiler

logger = logging.getLogger(__name__)


class ToneAnalysisPipeline:
    """
    Orquestra o pipeline completo:
    upload de áudio → separação → análise → geração de preset → validação.
    """

    def __init__(self, catalogs_dir: Optional[Path] = None):
        self.separator = SourceSeparator()
        self.catalog = CatalogLoader(catalogs_dir)
        self.compiler = PresetCompiler(self.catalog)

    async def process(
        self,
        audio_path: Path,
        rhythm_device: DeviceModel,
        lead_device: DeviceModel,
        artist: Optional[str] = None,
        song_title: Optional[str] = None,
        source_kind: str = "mix",
        excerpt_start: float = 0,
        excerpt_duration: Optional[float] = None,
        engine_mode: str = "legacy",
        lead_start: Optional[float] = None,
        lead_duration: Optional[float] = None,
        progress=None,
    ) -> tuple[AudioAnalysisResult, PresetPair]:
        """
        Processa um arquivo de áudio e gera par de presets.

        Raises:
            ValueError: se dispositivo não tem catálogo suportado
            RuntimeError: se análise falhar completamente
        """
        work_dir = Path(tempfile.mkdtemp(prefix="toneai_"))
        try:
            return await asyncio.to_thread(
                self._run, audio_path, rhythm_device, lead_device, artist, song_title, work_dir, source_kind, excerpt_start, excerpt_duration, engine_mode, lead_start, lead_duration, progress
            )
        finally:
            shutil.rmtree(work_dir, ignore_errors=True)

    def _run(
        self,
        audio_path: Path,
        rhythm_device: DeviceModel,
        lead_device: DeviceModel,
        artist: Optional[str],
        song_title: Optional[str],
        work_dir: Path,
        source_kind: str = "mix",
        excerpt_start: float = 0,
        excerpt_duration: Optional[float] = None,
        engine_mode: str = "legacy",
        lead_start: Optional[float] = None,
        lead_duration: Optional[float] = None,
        progress=None,
    ) -> tuple[AudioAnalysisResult, PresetPair]:

        if engine_mode == "guitar_v2":
            from ..services.tone_engine.engine import GuitarToneEngine
            engine = GuitarToneEngine(self.compiler)
            report = progress or (lambda percent, message: None)
            analysis = engine.analyze(audio_path,work_dir,source_kind,excerpt_start,excerpt_duration,report)
            lead_analysis = analysis
            if lead_start is not None:
                lead_dir = work_dir / 'lead'
                lead_dir.mkdir()
                lead_analysis = engine.analyze(audio_path,lead_dir,source_kind,lead_start,lead_duration,report)
            report(85, 'Gerando e validando presets no catálogo da pedaleira...')
            pair = self.compiler.compile_pair(analysis,rhythm_device,lead_device,artist,song_title)
            if lead_analysis is not analysis:
                pair.lead_preset = self.compiler._compile_lead_preset(lead_analysis,lead_device,artist,song_title)
            engine.refine(pair.rhythm_preset,analysis)
            engine.refine(pair.lead_preset,lead_analysis)
            analysis.engine_diagnostics['lead'] = lead_analysis.engine_diagnostics.copy() if lead_analysis is not analysis else {'same_region':True}
            from ..services.tone_engine.candidates import PresetCandidateGenerator
            generator = PresetCandidateGenerator(self.compiler)
            rhythm_candidates = generator.generate(pair.rhythm_preset,analysis)
            lead_candidates = generator.generate(pair.lead_preset,lead_analysis)
            analysis.engine_diagnostics['candidates'] = {
                'rhythm': [p.model_dump(mode='json') for p in rhythm_candidates],
                'lead': [p.model_dump(mode='json') for p in lead_candidates],
                'ranking': 'catalog_family_order_not_acoustic_similarity'}
            analysis.engine_diagnostics['reference_profiles'] = {'rhythm':analysis.reference_profile,'lead':lead_analysis.reference_profile}
            pair.analysis_summary = 'Guitarra analisada com motor v2 heurístico. ' + ' '.join(analysis.limitations)
            return analysis, pair

        if source_kind not in {"mix", "isolated"}:
            raise ValueError("Tipo de referência inválido")
        if excerpt_duration is not None:
            import librosa
            import soundfile as sf
            y, sr = librosa.load(str(audio_path), sr=22050, mono=True,
                                 offset=excerpt_start, duration=excerpt_duration)
            if len(y) < 3 * sr:
                raise ValueError("O trecho selecionado precisa conter pelo menos 3 segundos de áudio")
            audio_path = work_dir / "selected_excerpt.wav"
            sf.write(audio_path, y, sr, subtype="FLOAT")

        # Etapa 1: Separação de fontes (opcional, melhor qualidade)
        guitar_audio = None
        if source_kind != "isolated" and self.separator.is_available():
            logger.info("Tentando separação de fontes com Demucs…")
            stem_path = self.separator.separate(audio_path, work_dir / "stems")
            if stem_path:
                guitar_audio = self.separator.load_stem_audio(stem_path)
                if guitar_audio is not None:
                    logger.info("Separação de fontes bem-sucedida")
                else:
                    logger.warning("Falha ao carregar stem — prosseguindo com mix completo")
            else:
                logger.warning("Separação falhou — prosseguindo com mix completo")
        else:
            logger.info("Demucs não disponível — analisando mix completo")

        # Etapa 2: Análise de áudio
        logger.info("Iniciando análise espectral…")
        analyzer = AudioAnalyzer(source_separated_audio=guitar_audio, source_kind=source_kind)
        analysis = analyzer.analyze(audio_path)
        if excerpt_duration is not None:
            analysis.limitations.append(f"Referência analisada: trecho de {excerpt_start:g}s a {excerpt_start + analysis.duration_seconds:g}s. Base e solo partem deste mesmo trecho.")
        logger.info(f"Análise concluída: confiança={analysis.overall_confidence.value}")

        # Etapa 3: Geração de presets
        logger.info("Gerando presets…")
        preset_pair = self.compiler.compile_pair(
            analysis,
            rhythm_device=rhythm_device,
            lead_device=lead_device,
            artist=artist,
            song_title=song_title,
        )
        logger.info("Presets gerados com sucesso")

        return analysis, preset_pair
