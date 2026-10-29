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
