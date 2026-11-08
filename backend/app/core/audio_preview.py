"""Small, bounded listening copies of saved guitar; originals are never changed."""

import io
import math
import hashlib
import numpy as np
import soundfile as sf
from .reference_library import saved_source


def preview(pair_id, role, start, duration, channel=None, listen_gain_db=0):
    source = saved_source(pair_id, role)
    if (
        not all(math.isfinite(v) for v in [start, duration, listen_gain_db])
        or not 3 <= duration <= 30
        or not -18 <= listen_gain_db <= 18
    ):
        raise ValueError("Escolha de 3 a 30 segundos para ouvir")
    relative = start - source["cache_start_seconds"]
    if relative < 0 or relative + duration > source["available_duration"] + 0.01:
        raise ValueError("Trecho fora da guitarra salva")
    with sf.SoundFile(source["guitar_path"]) as audio:
        if channel is None:
            channel = source.get("analysis_channel")
        if channel == -1:
            channel = None
        if channel is not None and (
            type(channel) is not int or not 0 <= channel < audio.channels
        ):
            raise ValueError("Canal de guitarra inválido")
        sr = audio.samplerate
        audio.seek(round(relative * sr))
        samples = audio.read(round(duration * sr), dtype="float32", always_2d=True)
    if not len(samples) or not np.isfinite(samples).all():
        raise ValueError("Áudio da referência inválido")
    if channel is None:
        channel = int(np.argmax(np.mean(samples.astype(float) ** 2, axis=0)))
    mono = samples[:, channel].astype(float)
    peak = float(np.max(np.abs(mono)))
    rms = float(np.sqrt(np.mean(mono**2)))
    gain = min(10 ** (listen_gain_db / 20), 0.89 / max(peak, 1e-12))
    output = io.BytesIO()
    sf.write(output, mono * gain, sr, format="WAV", subtype="PCM_16")
    return output.getvalue(), {
        "channel": channel,
        "listen_gain_db": 20 * math.log10(gain),
        "original_rms_dbfs": 20 * math.log10(max(rms, 1e-12)),
        "original_peak_dbfs": 20 * math.log10(max(peak, 1e-12)),
        "cache_id": source["cache_id"],
    }
