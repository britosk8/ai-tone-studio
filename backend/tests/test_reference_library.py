import hashlib
import io
import json
from pathlib import Path
import numpy as np
import soundfile as sf
from app.core.storage import data_directory, save_record, load_record, list_records
from app.core.reference_library import reference_info, select_region
from app.models.devices import DeviceModel
from app.services.preset_generation.compiler import PresetCompiler
from app.services.device_catalog.loader import CatalogLoader
from tests.test_preset_generation import make_analysis
from tests.test_v1_flow import client


def seed_library():
    directory = data_directory()
    cache = "a" * 64
    target = directory / "separations" / cache
    target.mkdir(parents=True)
    sr = 44100
    t = np.arange(sr * 8) / sr
    samples = np.column_stack(
        [0.2 * np.sin(2 * np.pi * 220 * t), 0.15 * np.sin(2 * np.pi * 330 * t)]
    )
    raw = io.BytesIO()
    sf.write(raw, samples, sr, format="WAV", subtype="FLOAT")
    digest = hashlib.sha256(raw.getvalue()).hexdigest()
    originals = directory / "generation_inputs"
    originals.mkdir()
    (originals / (digest + ".wav")).write_bytes(raw.getvalue())
    names = ["guitar", "vocals", "drums", "bass", "piano", "other"]
    for name in names:
        (target / (name + ".wav")).write_bytes(raw.getvalue())
    manifest = {
        "cache_id": cache,
        "sources": names,
        "stem_sha256": {n: digest for n in names},
        "model": "htdemucs_6s",
    }
    (target / "manifest.json").write_text(json.dumps(manifest))
    pair = PresetCompiler(CatalogLoader()).compile_pair(
        make_analysis(), DeviceModel.MK300, DeviceModel.MK300, song_title="Library song"
    )
    pair.rhythm_preset.source_file_name = pair.lead_preset.source_file_name = (
        "Library.wav"
    )
    pair_id = str(pair.rhythm_preset.id)
    diagnostics = {
        "engine": "guitar_v2",
        "original_sha256": digest,
        "region": {"start_seconds": 0, "duration_seconds": 8},
        "separation": manifest,
        "lead": {"same_region": True},
    }
    save_record(
        "pair",
        pair_id,
        {
            "pair": pair.model_dump(mode="json"),
            "analysis": {"engine_diagnostics": diagnostics},
        },
    )
    return pair_id, target


def test_roles_keep_distinct_saved_regions_without_new_upload(client):
    pair_id, target = seed_library()
    response = client.get("/api/v1/reference-library")
    assert response.status_code == 200
    assert response.json()["songs"][0]["pair_id"] == pair_id
    result = client.put(
        f"/api/v1/presets/{pair_id}/reference/lead",
        json={"start_seconds": 4, "duration_seconds": 4},
    )
    assert result.status_code == 200, result.text
    assert result.json()["start_seconds"] == 4
    assert (
        client.get(f"/api/v1/presets/{pair_id}/reference/rhythm").json()[
            "start_seconds"
        ]
        == 0
    )
    assert (
        load_record("comparison_reference", json.dumps([pair_id, "lead"]))["profile"][
            "source_kind"
        ]
        == "separated_guitar"
    )
    from app.api.routes import _comparison_profile

    profile, _, _ = _comparison_profile(pair_id, {"role": "lead"})
    assert profile["duration_seconds"] == 4


def test_regenerate_from_saved_stems_and_reuse_job(client, monkeypatch):
    pair_id, target = seed_library()

    def forbidden(*args):
        raise AssertionError("Demucs não deve executar novamente")

    monkeypatch.setattr(
        "app.services.tone_engine.separation.DemucsGuitarProvider.separate_guitar",
        forbidden,
    )
    body = {
        "pair_id": pair_id,
        "rhythm_region": {"start_seconds": 0, "duration_seconds": 4},
        "lead_region": {"start_seconds": 4, "duration_seconds": 4},
    }
    response = client.post("/api/v1/analyze-saved", json=body)
    assert response.status_code == 200, response.text
    job = client.get("/api/v1/jobs/" + response.json()["job_id"]).json()
    assert job["status"] == "completed", job
    pair = client.get("/api/v1/presets/" + job["pair_id"]).json()
    assert pair["rhythm_preset"]["generation_metadata"]["region"]["start_seconds"] == 0
    assert pair["lead_preset"]["generation_metadata"]["region"]["start_seconds"] == 4
    for role in ["rhythm", "lead"]:
        assert (
            client.get(
                f"/api/v1/presets/{job['pair_id']}/stems/{role}/guitar"
            ).status_code
            == 200
        )
    repeated = client.post("/api/v1/analyze-saved", json=body).json()
    assert (
        repeated["reused"] is True and repeated["job_id"] == response.json()["job_id"]
    )
    assert len(list_records("pair")) == 2


def test_regions_and_integrity_are_validated(client):
    pair_id, target = seed_library()
    for region in [
        {"start_seconds": 7, "duration_seconds": 4},
        {"start_seconds": 0, "duration_seconds": 2},
    ]:
        assert client.put(
            f"/api/v1/presets/{pair_id}/reference/lead", json=region
        ).status_code in {400, 422}
    assert client.get(f"/api/v1/presets/{pair_id}/reference/vocals").status_code == 404
    (target / "guitar.wav").write_bytes(b"bad")
    assert client.get(f"/api/v1/presets/{pair_id}/reference/lead").status_code == 404
    assert client.get("/api/v1/reference-library").json()["songs"] == []
    assert (
        client.post("/api/v1/analyze-saved", json={"pair_id": pair_id}).status_code
        == 400
    )


def test_explicit_saved_role_is_reused_for_same_original(client):
    pair_id, _ = seed_library()
    select_region(pair_id, "lead", 4, 4)
    record = load_record("pair", pair_id)
    second = "another-pair"
    save_record("pair", second, record)
    assert reference_info(second, "lead")["start_seconds"] == 4
    assert reference_info(second, "rhythm")["start_seconds"] == 0
