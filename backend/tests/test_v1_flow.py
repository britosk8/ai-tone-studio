"""Regressões da integração API/análise/catálogos e recuperação após reinício."""
import io
import subprocess
import numpy as np
import pytest
import soundfile as sf
from fastapi.testclient import TestClient

from app.main import app
from app.api import routes
from app.core.storage import save_record


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("TONE_DATA_DIR", str(tmp_path / "data"))
    routes._jobs.clear()
    routes._presets.clear()
    routes._analyses.clear()
    # Exercita a análise real em CPU, sem baixar modelos opcionais.
    monkeypatch.setattr("app.services.audio_analysis.source_separator.SourceSeparator.is_available", lambda self: False)
    with TestClient(app) as client:
        yield client


def test_mp3_analysis_export_and_restart(client, tmp_path):
    sr = 22050
    t = np.arange(sr * 4) / sr
    signal = np.tanh(2 * (np.sin(2 * np.pi * 110 * t) + 0.3 * np.sin(2 * np.pi * 165 * t)))
    signal *= 0.3 * (0.6 + 0.4 * np.sin(2 * np.pi * 2 * t) ** 2)
    wav = tmp_path / "test.wav"
    mp3 = tmp_path / "test.mp3"
    sf.write(wav, signal, sr)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), str(mp3)], check=True)
    response = client.post("/api/v1/analyze", files={"file": ("Teste original.mix.mp3", mp3.read_bytes(), "audio/mpeg")},
                           data={"rhythm_device": "MK20", "lead_device": "MK300"})
    assert response.status_code == 200
    job_id = response.json()["job_id"]
    job = client.get(f"/api/v1/jobs/{job_id}").json()
    assert job["status"] == "completed", job
    assert job["job_id"] == job_id and job["progress_percent"] == 100
    pair_id = job["pair_id"]
    pair = client.get(f"/api/v1/presets/{pair_id}").json()
    assert pair["id"] == pair_id
    assert pair["rhythm_preset"]["song_title"] == "Teste original.mix"
    assert pair["lead_preset"]["song_title"] == "Teste original.mix"
    assert pair["lead_preset"]["source_file_name"] == "Teste original.mix.mp3"
    assert pair["rhythm_preset"]["device"] == "MK20"
    assert pair["lead_preset"]["device"] == "MK300"
    assert pair["rhythm_preset"]["effect_chain"] != pair["lead_preset"]["effect_chain"]
    for preset in [pair["rhythm_preset"], pair["lead_preset"]]:
        blocks = preset["effect_chain"]
        assert any(b["effect_type"] == "noise_gate" for b in blocks)
        amp = next(b for b in blocks if b["effect_type"] == "amp")
        assert {"Gain", "Level", "Pres"} <= set(amp["parameters"])
        for block in blocks:
            for name, value in block["parameters"].items():
                spec = block["parameter_specs"][name]
                assert spec["min"] <= value <= spec["max"]
        gate = next(b for b in blocks if b["effect_type"] == "noise_gate")
        assert gate["parameters"]
        if preset["device"] == "MK300":
            reverb = next(b for b in blocks if b["effect_type"] == "reverb")
            assert set(reverb["parameters"]) == {"Decay", "Mix"}
    # Simula perda dos caches em memória ao reiniciar o processo.
    routes._jobs.clear(); routes._presets.clear(); routes._analyses.clear()
    assert client.get(f"/api/v1/jobs/{job_id}").json()["status"] == "completed"
    assert client.get(f"/api/v1/presets/{pair_id}").json() == pair
    assert client.get(f"/api/v1/presets/{pair_id}/export/json").status_code == 200
    assert "Teste" in client.get(f"/api/v1/presets/{pair_id}/export/guide").text


def test_silent_audio_has_visible_failure(client):
    audio = io.BytesIO()
    sf.write(audio, np.zeros(22050), 22050, format="WAV")
    response = client.post("/api/v1/analyze", files={"file": ("silent.wav", audio.getvalue())})
    job = client.get("/api/v1/jobs/" + response.json()["job_id"]).json()
    assert job["status"] == "failed"
    assert "audível" in job["error_message"]


def test_interrupted_job_has_actionable_error(client):
    save_record("job", "interrupted", {"job_id": "interrupted", "status": "queued"})
    result = client.get("/api/v1/jobs/interrupted").json()
    assert result["status"] == "failed"
    assert "novamente" in result["error_message"]


def test_upload_limit_and_unknown_device(client, monkeypatch):
    monkeypatch.setattr(routes, "MAX_FILE_SIZE", 8)
    assert client.post("/api/v1/analyze", files={"file": ("large.wav", b"x" * 9)}).status_code == 413
    assert client.post("/api/v1/analyze", files={"file": ("test.wav", b"x")}, data={"rhythm_device": "UNKNOWN"}).status_code == 400
