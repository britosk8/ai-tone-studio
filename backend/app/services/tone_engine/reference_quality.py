"""Conservative reference eligibility, separate from clean/distorted classification.

A quiet master is not rejected just for its level. A state is weak only when it
is also substantially quieter than another state on the SAME saved guitar/channel.
These thresholds flag a poor generation reference, not prove source leakage.
"""

import copy
import math

VERSION = "reference-quality-v1"


def assessed_collection(collection):
    result = copy.deepcopy(collection)
    for state_map in result.get("maps", []):
        peaks = {}
        for state in state_map.get("states", []):
            value = state.get("features", {}).get("rms_dbfs")
            if isinstance(value, (int, float)) and math.isfinite(value):
                channel = state.get("channel", 0)
                peaks[channel] = max(peaks.get(channel, -160), value)
        for state in state_map.get("states", []):
            value = state.get("features", {}).get("rms_dbfs")
            strongest = peaks.get(state.get("channel", 0))
            known = isinstance(value, (int, float)) and math.isfinite(value)
            gap = strongest - value if known and strongest is not None else None
            weak = known and gap is not None and value < -40 and gap > 18
            state["reference_quality"] = {
                "version": VERSION,
                "eligible": not weak,
                "status": (
                    "weak_relative_signal"
                    if weak
                    else "available" if known else "unassessed"
                ),
                "rms_dbfs": value if known else None,
                "relative_gap_db": gap,
                "message": (
                    "Guitarra muito fraca neste trecho em relação aos demais. Escolha um trecho em que ela esteja mais audível antes de gerar o preset."
                    if weak
                    else None
                ),
            }
        # Useful guitar first; never silently replaces a user's chosen state.
        state_map["states"].sort(key=lambda s: not s["reference_quality"]["eligible"])
    return result


def ensure_usable_excerpt(source, start, duration, channel=None):
    """Check the selected raw crop against the same saved guitar/channel.

    Used before saving a reference or creating a saved-audio generation job.
    A gain applied to listening copies can never influence this check.
    """
    import numpy as np
    import soundfile as sf

    with sf.SoundFile(source["guitar_path"]) as audio:
        relative = start - source["cache_start_seconds"]
        if relative < 0 or relative + duration > source["available_duration"] + 0.01:
            raise ValueError("Trecho fora da guitarra salva")
        sr = audio.samplerate
        audio.seek(round(relative * sr))
        selected = audio.read(round(duration * sr), dtype="float32", always_2d=True)
        if not len(selected) or not np.isfinite(selected).all():
            raise ValueError("Trecho de guitarra inválido")
        if channel is None or channel == -1:
            channel = int(np.argmax(np.mean(selected.astype(float) ** 2, axis=0)))
        if not 0 <= channel < audio.channels:
            raise ValueError("Canal de guitarra inválido")
        level = 20 * math.log10(
            max(float(np.sqrt(np.mean(selected[:, channel].astype(float) ** 2))), 1e-12)
        )
        if level >= -40:
            return
        audio.seek(0)
        levels = []
        while True:
            block = audio.read(sr * 5, dtype="float32", always_2d=True)
            if not len(block):
                break
            levels.append(
                20
                * math.log10(
                    max(
                        float(np.sqrt(np.mean(block[:, channel].astype(float) ** 2))),
                        1e-12,
                    )
                )
            )
    if levels and float(np.percentile(levels, 95)) - level > 18:
        raise ValueError(
            "A guitarra de referência está muito fraca no trecho escolhido. Ouça e escolha uma passagem mais audível da guitarra separada. Este aviso se refere à música separada, não à sua gravação USB."
        )
