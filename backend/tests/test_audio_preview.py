import io
import hashlib
import numpy as np
import soundfile as sf
from app.core.storage import load_record
from tests.test_reference_library import seed_library
from tests.test_v1_flow import client


def frequency(samples, sr):
    return np.fft.rfftfreq(len(samples), 1 / sr)[np.argmax(abs(np.fft.rfft(samples)))]


def test_preview_correct_channel_gain_and_no_original_or_selection_changes(
    client, monkeypatch
):
    pair, target = seed_library()
    before = hashlib.sha256((target / "guitar.wav").read_bytes()).hexdigest()

    def forbidden(*a, **k):
        raise AssertionError("Never separate again for listening")

    monkeypatch.setattr(
        "app.services.tone_engine.separation.DemucsGuitarProvider.separate_guitar",
        forbidden,
    )
    for channel, expected in [(0, 220), (1, 330), (-1, 220)]:
        response = client.get(
            f"/api/v1/presets/{pair}/reference/rhythm/preview",
            params={
                "start_seconds": 1,
                "duration_seconds": 3,
                "channel": channel,
                "listen_gain_db": 12,
            },
        )
        assert response.status_code == 200, response.text
        samples, sr = sf.read(io.BytesIO(response.content))
        assert samples.ndim == 1 and len(samples) == 3 * sr
        assert abs(frequency(samples, sr) - expected) < 1
        assert max(abs(samples)) <= 0.891
        assert response.headers["cache-control"] == "no-store"
    assert hashlib.sha256((target / "guitar.wav").read_bytes()).hexdigest() == before
    import json

    assert load_record("comparison_reference", json.dumps([pair, "rhythm"])) is None


def test_preview_bounds_and_role_validation(client):
    pair, _ = seed_library()
    base = f"/api/v1/presets/{pair}/reference/rhythm/preview"
    for params in [
        {"start_seconds": 7, "duration_seconds": 3},
        {"start_seconds": 0, "duration_seconds": 31},
        {"start_seconds": 0, "duration_seconds": 3, "channel": 2},
    ]:
        assert client.get(base, params=params).status_code in {400, 422}
    assert (
        client.get(
            f"/api/v1/presets/{pair}/reference/invalid/preview",
            params={"start_seconds": 0, "duration_seconds": 3},
        ).status_code
        == 400
    )


def test_selected_channel_used_by_reference_and_both_generated_roles(
    client, monkeypatch
):
    pair, _ = seed_library()
    selected = client.put(
        f"/api/v1/presets/{pair}/reference/rhythm",
        json={"start_seconds": 1, "duration_seconds": 3, "channel": 1},
    )
    assert selected.status_code == 200, selected.text
    assert selected.json()["analysis_channel"] == 1

    def forbidden(*a, **k):
        raise AssertionError("No new separation")

    monkeypatch.setattr(
        "app.services.tone_engine.separation.DemucsGuitarProvider.separate_guitar",
        forbidden,
    )
    body = {
        "pair_id": pair,
        "rhythm_region": {"start_seconds": 0, "duration_seconds": 4, "channel": 0},
        "lead_region": {"start_seconds": 0, "duration_seconds": 4, "channel": 1},
    }
    response = client.post("/api/v1/analyze-saved", json=body)
    assert response.status_code == 200, response.text
    job = client.get("/api/v1/jobs/" + response.json()["job_id"]).json()
    assert job["status"] == "completed", job
    saved = load_record("pair", job["pair_id"])["analysis"]["engine_diagnostics"]
    assert saved["features"]["analysis_channel"] == 0
    assert saved["lead"]["features"]["analysis_channel"] == 1
    assert client.post("/api/v1/analyze-saved", json=body).json()["reused"]


def test_state_custom_listened_region_is_used_and_idempotent(client, monkeypatch):
    monkeypatch.setenv("TONE_WEB_RESEARCH", "0")
    pair, _ = seed_library()
    detected = client.post(
        f"/api/v1/presets/{pair}/tone-states/analyze", json={}
    ).json()
    state = detected["maps"][0]["states"][0]
    original = load_record("pair", pair)
    body = {
        "role": "rhythm",
        "device": "MK20",
        "region": {"start_seconds": 1, "duration_seconds": 3},
    }
    url = f'/api/v1/presets/{pair}/tone-states/{state["id"]}/generate'
    response = client.post(url, json=body)
    assert response.status_code == 200, response.text
    variant = response.json()["pair_id"]
    metadata = load_record("pair", variant)["pair"]["rhythm_preset"][
        "generation_metadata"
    ]
    assert metadata["region"]["start_seconds"] == 1
    assert metadata["region"]["duration_seconds"] == 3
    assert client.post(url, json=body).json()["pair_id"] == variant
    assert (
        client.post(
            url, json={**body, "region": {"start_seconds": 7, "duration_seconds": 3}}
        ).status_code
        == 400
    )
    assert load_record("pair", pair) == original


def test_short_crop_cannot_bypass_reference_quality(client, monkeypatch):
    monkeypatch.setenv("TONE_WEB_RESEARCH", "0")
    pair, _ = seed_library()
    state = client.post(f"/api/v1/presets/{pair}/tone-states/analyze", json={}).json()[
        "maps"
    ][0]["states"][0]
    from tests.test_preset_generation import make_analysis

    def weak(*a, **k):
        analysis = make_analysis()
        analysis.engine_diagnostics = {"features": {"rms_dbfs": -70}}
        return analysis

    monkeypatch.setattr(
        "app.services.tone_engine.engine.GuitarToneEngine.analyze", weak
    )
    result = client.post(
        f"/api/v1/presets/{pair}/tone-states/{state['id']}/generate",
        json={
            "role": "rhythm",
            "device": "MK20",
            "region": {"start_seconds": 1, "duration_seconds": 3},
        },
    )
    assert result.status_code == 400, result.text
    assert "fraca no trecho" in result.json()["detail"]


def test_quiet_reference_can_be_heard_but_not_used_for_generation(client):
    import json

    pair, target = seed_library()
    audio, sr = sf.read(target / "guitar.wav", always_2d=True)
    audio[: sr * 4] *= 0.02
    sf.write(target / "guitar.wav", audio, sr, subtype="FLOAT")
    manifest = json.loads((target / "manifest.json").read_text())
    manifest["stem_sha256"]["guitar"] = hashlib.sha256(
        (target / "guitar.wav").read_bytes()
    ).hexdigest()
    (target / "manifest.json").write_text(json.dumps(manifest))
    params = {
        "start_seconds": 0,
        "duration_seconds": 3,
        "channel": 0,
        "listen_gain_db": 18,
    }
    assert (
        client.get(
            f"/api/v1/presets/{pair}/reference/rhythm/preview", params=params
        ).status_code
        == 200
    )
    selected = client.put(
        f"/api/v1/presets/{pair}/reference/rhythm",
        json={"start_seconds": 0, "duration_seconds": 3, "channel": 0},
    )
    assert selected.status_code == 400, selected.text
    generated = client.post(
        "/api/v1/analyze-saved",
        json={
            "pair_id": pair,
            "rhythm_region": {"start_seconds": 0, "duration_seconds": 3},
            "lead_region": {"start_seconds": 4, "duration_seconds": 3},
        },
    )
    assert generated.status_code == 400, generated.text
    assert "fraca no trecho" in generated.json()["detail"]
