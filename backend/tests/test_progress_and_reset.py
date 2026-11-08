import json
import os
import subprocess
import sys
import time
import pytest
from app.core.library_reset import reset_library, LIBRARY_KINDS
from app.core.storage import save_record, load_record
from app.services.tone_engine.worker_progress import ChunkProgress
from app.services.tone_engine.worker_runner import run_worker


def test_progress_only_advances_after_consumption_and_across_models(capsys):
    progress = ChunkProgress(2)
    for _ in range(2):
        iterator = progress([1, 2])
        assert next(iterator) == 1
        assert progress.completed % 2 == 0
        assert next(iterator) == 2
        with pytest.raises(StopIteration):
            next(iterator)
    events = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    assert [e["completed"] for e in events] == [0, 1, 2, 2, 3, 4]
    assert {e["total"] for e in events} == {4}


def test_worker_streams_before_exit_and_reports_failure(tmp_path):
    worker = tmp_path / "worker.py"
    worker.write_text(
        'import time,json,sys\nprint(json.dumps({"event":"progress","stage":"loading"}),flush=True)\ntime.sleep(1)\nsys.exit(2)\n'
    )
    received = []
    start = time.monotonic()
    with pytest.raises(subprocess.CalledProcessError):
        run_worker(
            [sys.executable, str(worker)],
            os.environ.copy(),
            lambda event: received.append((event, time.monotonic() - start)),
        )
    assert received[0][0]["stage"] == "loading"
    assert received[0][1] < 0.8
    assert len(received) == 1


def test_worker_timeout_kills_child(tmp_path):
    worker = tmp_path / "worker.py"
    worker.write_text("import time\ntime.sleep(20)\n")
    start = time.monotonic()
    with pytest.raises(subprocess.TimeoutExpired):
        run_worker(
            [sys.executable, str(worker)],
            os.environ.copy(),
            lambda _: None,
            timeout=0.2,
        )
    assert time.monotonic() - start < 3


def test_library_reset_removes_music_preserves_recordings_and_recovery(
    tmp_path, monkeypatch
):
    monkeypatch.setenv("TONE_DATA_DIR", str(tmp_path))
    for kind in LIBRARY_KINDS:
        save_record(kind, "old", {"old": True})
    for kind in [
        "mk20_transfer",
        "mk20_diagnostic",
        "mk20_name_pilot",
        "guitar_recording",
        "calibration_test",
    ]:
        save_record(kind, "keep", {"keep": True})
    for folder in ["generation_inputs", "separations", "recordings"]:
        (tmp_path / folder).mkdir()
        (tmp_path / folder / "audio").write_bytes(b"audio")
    result = reset_library()
    assert all(value == 1 for value in result["deleted"].values())
    assert all(load_record(kind, "old") is None for kind in LIBRARY_KINDS)
    assert load_record("mk20_transfer", "keep") == {"keep": True}
    assert load_record("guitar_recording", "keep") == {"keep": True}
    assert (tmp_path / "recordings/audio").exists()
    assert not (tmp_path / "separations").exists()
    assert all(value == 0 for value in reset_library()["deleted"].values())
