"""Provider desacoplado, cache persistente e nenhuma substituição silenciosa por mix."""

from dataclasses import dataclass
from typing import Protocol
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import threading
from ...core.storage import data_directory

_LOCK = threading.Lock()
ROOT = Path(__file__).resolve().parents[4]


@dataclass
class SeparationResult:
    guitar_stem: Path
    directory: Path
    metadata: dict


class IGuitarSeparationProvider(Protocol):
    def separate_guitar(self, audio_path: Path) -> SeparationResult: ...


class DemucsGuitarProvider:
    def separate_guitar(self, audio_path: Path) -> SeparationResult:
        identity = {
            "provider": "demucs-4.0.1",
            "model": "htdemucs_6s",
            "configuration": "float32-stereo-44100-shifts0-segment4-v1",
            "input_sha256": hashlib.sha256(audio_path.read_bytes()).hexdigest(),
        }
        key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
        parent = data_directory() / "separations"
        target = parent / key
        with _LOCK:  # Limita uso CPU/RAM e evita publicar cache incompleto.
            manifest = target / "manifest.json"
            if manifest.exists():
                metadata = json.loads(manifest.read_text())
                if all(
                    (target / f"{name}.wav").is_file()
                    and hashlib.sha256(
                        (target / f"{name}.wav").read_bytes()
                    ).hexdigest()
                    == digest
                    for name, digest in metadata["stem_sha256"].items()
                ):
                    return SeparationResult(target / "guitar.wav", target, metadata)
                raise ValueError(
                    "Cache de separação corrompido. Preserve os arquivos e confira o backend."
                )
            python = Path(
                os.environ.get(
                    "TONE_DEMUCS_PYTHON",
                    str(ROOT / "repertorio/laboratorio/.venv/bin/python"),
                )
            )
            if not python.is_file():
                raise ValueError(
                    "Separação indisponível: configure TONE_DEMUCS_PYTHON com Demucs 4.0.1. Nenhum preset foi gerado da mixagem."
                )
            parent.mkdir(parents=True, exist_ok=True)
            temporary = Path(tempfile.mkdtemp(prefix="processing_", dir=parent))
            try:
                env = os.environ.copy()
                env.setdefault(
                    "TORCH_HOME", str(ROOT / "repertorio/laboratorio/cache/torch")
                )
                worker = Path(__file__).with_name("separation_worker.py")
                subprocess.run(
                    [str(python), str(worker), str(audio_path), str(temporary)],
                    check=True,
                    capture_output=True,
                    timeout=3600,
                    env=env,
                )
                names = ["drums", "bass", "other", "vocals", "piano", "guitar"]
                if not all((temporary / f"{name}.wav").is_file() for name in names):
                    raise ValueError("Separação incompleta: faltam instrumentos.")
                metadata = {
                    **identity,
                    "cache_id": key,
                    "sources": names,
                    "bleed_estimate": None,
                    "separation_confidence": "unverified",
                    "stem_sha256": {
                        name: hashlib.sha256(
                            (temporary / f"{name}.wav").read_bytes()
                        ).hexdigest()
                        for name in names
                    },
                    "limitations": [
                        "Guitar pode conter base e solo sobrepostos.",
                        "Vazamento e artefatos não foram medidos contra stems verdadeiros.",
                    ],
                }
                (temporary / "manifest.json").write_text(json.dumps(metadata, indent=2))
                temporary.rename(target)
                return SeparationResult(target / "guitar.wav", target, metadata)
            except (subprocess.SubprocessError, OSError) as exc:
                raise ValueError(
                    "A separação de instrumentos falhou ou excedeu o tempo limite. Nenhum preset foi gerado da mixagem; confira o ambiente Demucs."
                ) from exc
            finally:
                if temporary.exists():
                    shutil.rmtree(temporary)


def crop_saved_stems(cache_id, relative_start, duration):
    """Recorta saídas já separadas; nenhuma inferência ou normalização adicional."""
    import soundfile as sf

    if len(cache_id) != 64 or any(c not in "0123456789abcdef" for c in cache_id):
        raise ValueError("Referência salva inválida")
    parent = data_directory() / "separations"
    source = parent / cache_id
    manifest = json.loads((source / "manifest.json").read_text())
    available = sf.info(source / "guitar.wav").duration
    duration = duration if duration is not None else available - relative_start
    if (
        relative_start < 0
        or duration < 3
        or relative_start + duration > available + 0.01
    ):
        raise ValueError("Trecho fora da referência de guitarra salva")
    for name, digest in manifest["stem_sha256"].items():
        if (
            name not in {"guitar", "vocals", "drums", "bass", "piano", "other"}
            or hashlib.sha256((source / f"{name}.wav").read_bytes()).hexdigest()
            != digest
        ):
            raise ValueError("Integridade dos instrumentos não confirmada")
    if relative_start == 0 and abs(duration - available) < 0.01:
        return SeparationResult(source / "guitar.wav", source, manifest)
    identity = {
        "parent": cache_id,
        "start_seconds": relative_start,
        "duration_seconds": duration,
        "operation": "crop-v1",
    }
    key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    target = parent / key
    with _LOCK:
        if not target.exists():
            temporary = Path(tempfile.mkdtemp(prefix="crop_", dir=parent))
            try:
                for name in manifest["sources"]:
                    # Stems silenciosos são válidos; não usar o preprocessor com teste de audibilidade.
                    import subprocess

                    subprocess.run(
                        [
                            "ffmpeg",
                            "-v",
                            "error",
                            "-nostdin",
                            "-i",
                            str(source / f"{name}.wav"),
                            "-ss",
                            str(relative_start),
                            "-t",
                            str(duration),
                            "-c:a",
                            "pcm_f32le",
                            str(temporary / f"{name}.wav"),
                        ],
                        check=True,
                        capture_output=True,
                        timeout=180,
                    )
                metadata = {
                    **manifest,
                    "cache_id": key,
                    "selection": identity,
                    "stem_sha256": {
                        n: hashlib.sha256(
                            (temporary / f"{n}.wav").read_bytes()
                        ).hexdigest()
                        for n in manifest["sources"]
                    },
                }
                (temporary / "manifest.json").write_text(json.dumps(metadata, indent=2))
                temporary.rename(target)
            finally:
                if temporary.exists():
                    shutil.rmtree(temporary)
        metadata = json.loads((target / "manifest.json").read_text())
        if any(
            hashlib.sha256((target / f"{n}.wav").read_bytes()).hexdigest() != digest
            for n, digest in metadata["stem_sha256"].items()
        ):
            raise ValueError("Cache recortado corrompido")
    return SeparationResult(target / "guitar.wav", target, metadata)
