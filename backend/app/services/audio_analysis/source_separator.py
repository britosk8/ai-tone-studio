"""Separação de fontes de áudio usando Demucs."""
import logging
import subprocess
import sys
from pathlib import Path
from typing import Optional
import numpy as np

logger = logging.getLogger(__name__)

try:
    import demucs.api
    DEMUCS_AVAILABLE = True
except ImportError:
    DEMUCS_AVAILABLE = False
    logger.info("demucs não disponível — separação de fontes desativada")


class SourceSeparator:
    """
    Separa instrumentos de uma mixagem usando Demucs.

    LIMITAÇÕES IMPORTANTES:
    - htdemucs separa vocals, drums, bass e other; guitarra dedicada requer modelo de seis fontes
    - 'other' contém guitarra mas também pode ter piano, sinth etc.
    - Qualidade de separação varia muito por gênero musical
    - Requer GPU para velocidade adequada (CPU é muito lento para produção)
    - Gravações ao vivo ou baixa qualidade degradam muito o resultado
    """

    # htdemucs possui vocals, drums, bass e other; other não isola guitarra.
    DEFAULT_MODEL = "htdemucs"

    def __init__(self, model: str = DEFAULT_MODEL):
        self.model = model
        self._separator = None

    def is_available(self) -> bool:
        return DEMUCS_AVAILABLE

    def separate(
        self, audio_path: Path, output_dir: Path, stem: str = "other"
    ) -> Optional[Path]:
        """
        Separa o áudio e retorna o caminho do stem solicitado.

        Args:
            audio_path: Arquivo de entrada (MP3/WAV/FLAC)
            output_dir: Diretório para stems separados
            stem: Stem a retornar ('other' no modelo htdemucs)

        Returns:
            Path do stem separado, ou None se falhar
        """
        if not DEMUCS_AVAILABLE:
            logger.warning("Demucs indisponível. Prosseguindo sem separação de fontes.")
            return None

        output_dir.mkdir(parents=True, exist_ok=True)
        logger.info(f"Separando fontes com {self.model}: {audio_path}")

        try:
            # Usa CLI do demucs para maior compatibilidade
            cmd = [
                sys.executable, "-m", "demucs",
                "--name", self.model,
                "--out", str(output_dir),
                "--two-stems", stem,
                str(audio_path),
            ]
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=600
            )

            if result.returncode != 0:
                logger.error(f"Demucs falhou: {result.stderr}")
                return None

            # Localiza stem gerado
            model_dir = output_dir / self.model / audio_path.stem
            stem_path = model_dir / f"{stem}.wav"

            if stem_path.exists():
                logger.info(f"Stem separado: {stem_path}")
                return stem_path
            else:
                logger.error(f"Stem não encontrado em {stem_path}")
                return None

        except subprocess.TimeoutExpired:
            logger.error("Timeout na separação de fontes (>10min)")
            return None
        except Exception as e:
            logger.error(f"Erro na separação de fontes: {e}")
            return None

    def load_stem_audio(self, stem_path: Path, sr: int = 22050) -> Optional[np.ndarray]:
        """Carrega stem separado como array numpy."""
        try:
            import librosa
            y, _ = librosa.load(str(stem_path), sr=sr, mono=True)
            return y
        except Exception as e:
            logger.error(f"Erro ao carregar stem: {e}")
            return None
