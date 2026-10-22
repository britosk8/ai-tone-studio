from pathlib import Path
import subprocess
import soundfile as sf
import numpy as np


class AudioPreprocessor:
    """Decodifica sem normalizar; preserva estéreo e dinâmica em FLOAT32."""

    def prepare(self, source: Path, target: Path, start=0, duration=None):
        command = [
            "ffmpeg",
            "-v",
            "error",
            "-nostdin",
            "-i",
            str(source),
            "-ss",
            str(start),
        ]
        if duration is not None:
            command += ["-t", str(duration)]
        command += ["-ar", "44100", "-ac", "2", "-c:a", "pcm_f32le", "-y", str(target)]
        try:
            subprocess.run(command, check=True, capture_output=True, timeout=180)
        except (subprocess.SubprocessError, OSError) as exc:
            raise ValueError(
                "Não foi possível decodificar o áudio selecionado."
            ) from exc
        y, sr = sf.read(target, dtype="float32", always_2d=True)
        if len(y) < 3 * sr or not np.isfinite(y).all() or np.max(np.abs(y)) < 1e-8:
            raise ValueError(
                "O trecho precisa conter ao menos 3 segundos de sinal audível."
            )
        return target
