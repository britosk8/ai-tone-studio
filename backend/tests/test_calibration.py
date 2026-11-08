import hashlib
from app.core.storage import save_record, load_record
from tests.test_v1_flow import client

ID = "12345678-1234-1234-1234-123456789abc"


def seed():
    record = {
        "id": ID,
        "pair_id": "infest",
        "role": "rhythm",
        "status": "completed",
        "sha256": "a" * 64,
        "submitted_preset": {
            "id": "preset-1",
            "device": "MK20",
            "role": "rhythm",
            "effect_chain": [{"model_name": "70OD2_meas", "parameters": {"Gain": 56}}],
        },
        "reference_profile": {"source_kind": "separated_guitar", "brightness": 0.5},
        "analysis_result": {
            "quality": "usable",
            "reference_source": "saved_excerpt_profile",
            "reference_context": {
                "start_seconds": 141,
                "duration_seconds": 12,
                "channel": 0,
                "cache_id": "b" * 64,
            },
        },
    }
    save_record("guitar_recording", ID, record)
    return record


def test_evaluation_versioned_idempotent_snapshot_and_audio_untouched(client):
    original = seed()
    body = {
        "guitar": "konig_strat_sss",
        "pickup": "bridge",
        "route": "pedal_usb",
        "signal": "processed",
        "preset_applied": True,
        "assessment": "close",
        "notes": "Mais ataque nesta versão",
    }
    url = f"/api/v1/recordings/{ID}/evaluation"
    response = client.post(url, json=body)
    assert response.status_code == 200, response.text
    test = response.json()
    assert test["eligible_for_review"]
    assert test["reference_context"]["start_seconds"] == 141
    assert client.post(url, json=body).json()["id"] == test["id"]
    changed = client.post(url, json={**body, "assessment": "approved"}).json()
    assert changed["id"] != test["id"]
    assert load_record("guitar_recording", ID) == original
    assert (
        len(
            client.get(
                "/api/v1/calibration-tests",
                params={"pair_id": "infest", "role": "rhythm"},
            ).json()["tests"]
        )
        == 2
    )
    assert (
        client.get("/api/v1/calibration-tests", params={"pair_id": "other"}).json()[
            "tests"
        ]
        == []
    )


def test_partial_context_and_clipping_do_not_become_validated_calibration(client):
    record = seed()
    record["analysis_result"]["quality"] = "clipped"
    save_record("guitar_recording", ID, record)
    response = client.post(
        f"/api/v1/recordings/{ID}/evaluation", json={"assessment": "approved"}
    )
    assert response.status_code == 200
    assert not response.json()["eligible_for_review"]
    assert "clipped_recording" in response.json()["review_flags"]
    assert "incomplete_context" in response.json()["review_flags"]


def test_invalid_context_and_missing_or_unfinished_capture_rejected(client):
    record = seed()
    assert (
        client.post(
            f"/api/v1/recordings/{ID}/evaluation",
            json={"guitar": "strinberg_les_paul_hh", "pickup": "middle"},
        ).status_code
        == 400
    )
    assert (
        client.post(
            f"/api/v1/recordings/{ID}/evaluation", json={"write_pedal": True}
        ).status_code
        == 422
    )
    assert (
        client.post("/api/v1/recordings/not-an-id/evaluation", json={}).status_code
        == 400
    )
    record["status"] = "failed"
    save_record("guitar_recording", ID, record)
    assert (
        client.post(f"/api/v1/recordings/{ID}/evaluation", json={}).status_code == 400
    )


def test_approved_baseline_uses_verified_capture_without_changing_library(
    client, monkeypatch
):
    from tests.test_reference_library import seed_library
    from tests.test_mk20_transfers import preset
    from tests.test_mk20_diagnostics import report, image
    from app.transport.protocol_mk20 import build_image
    import hashlib

    pair, _ = seed_library()
    parent = load_record("pair", pair)
    parent["pair"]["rhythm_preset"]["song_title"] = "Infest"
    save_record("pair", pair, parent)
    original = load_record("pair", pair)
    raw = build_image(preset(), "PAPA INFEST", image())
    monkeypatch.setattr("tests.test_mk20_diagnostics.image", lambda: raw)
    monkeypatch.setattr("app.core.calibration_baseline.DIAGNOSTIC_ID", "qa-approved")
    monkeypatch.setattr(
        "app.core.calibration_baseline.IMAGE_SHA", hashlib.sha256(raw).hexdigest()
    )
    save_record("mk20_diagnostic", "qa-approved", {"report": report(76)})
    url = f"/api/v1/presets/{pair}/calibration-baseline"
    response = client.post(url)
    assert response.status_code == 200, response.text
    data = response.json()["preset"]
    assert data["device"] == "MK20" and data["generation_metadata"]["source_slot"] == 76
    assert data["generation_metadata"]["calibration_baseline"]
    amp = next(b for b in data["effect_chain"] if b["effect_type"] == "amp")
    assert amp["model_id"] == "69" and amp["parameters"]["Gain"] == 56
    assert client.post(url).json()["preset"]["id"] == data["id"]
    assert load_record("pair", pair) == original
    monkeypatch.setattr("app.core.calibration_baseline.IMAGE_SHA", "f" * 64)
    assert client.post(url).status_code == 400
