"""Explicit offline library maintenance; never invoked at server startup."""

import json
import shutil
from datetime import datetime, timezone
from .storage import _connect, data_directory

LIBRARY_KINDS = (
    "pair",
    "job",
    "comparison_reference",
    "pair_tone_states",
    "pedal_reference",
    "saved_generation",
    "song_reference",
    "song_research",
    "tone_states",
)


def reset_library():
    """Caller must stop the backend and its workers before invoking this function."""
    directory = data_directory()
    # Reject unexpected symlinks before any deletion.
    paths = [directory / name for name in ("generation_inputs", "separations")]
    if any(path.is_symlink() for path in paths):
        raise ValueError("Diretório de biblioteca não pode ser link simbólico")
    with _connect() as connection:
        counts = dict(
            connection.execute(
                "SELECT kind,count(*) FROM records GROUP BY kind"
            ).fetchall()
        )
        connection.executemany(
            "DELETE FROM records WHERE kind=?", [(k,) for k in LIBRARY_KINDS]
        )
        result = {
            "reset_at": datetime.now(timezone.utc).isoformat(),
            "deleted": {k: counts.get(k, 0) for k in LIBRARY_KINDS},
        }
        connection.execute(
            "INSERT OR REPLACE INTO records VALUES (?,?,?)",
            ("maintenance", "library_reset_20261108", json.dumps(result)),
        )
    for path in paths:
        if path.exists():
            shutil.rmtree(path)
    return result
