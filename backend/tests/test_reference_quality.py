import copy
from app.services.tone_engine.reference_quality import assessed_collection
from app.core.storage import save_record, load_record
from tests.test_v1_flow import client


def collection(quiet=-55, strong=-15):
    return {
        "pair_id": "qa",
        "maps": [
            {
                "states": [
                    {
                        "id": "quiet",
                        "channel": 0,
                        "character": "clean",
                        "features": {"rms_dbfs": quiet},
                    },
                    {
                        "id": "strong",
                        "channel": 0,
                        "character": "distorted",
                        "features": {"rms_dbfs": strong},
                    },
                ]
            }
        ],
    }


def test_quiet_intro_not_eligible_and_strong_guitar_sorted_first_without_mutation():
    original = collection()
    before = copy.deepcopy(original)
    result = assessed_collection(original)
    assert original == before
    states = result["maps"][0]["states"]
    assert states[0]["id"] == "strong"
    assert states[0]["reference_quality"]["eligible"]
    assert states[1]["reference_quality"]["status"] == "weak_relative_signal"
    assert not states[1]["reference_quality"]["eligible"]


def test_quiet_master_and_other_channel_are_not_automatically_rejected():
    quiet = assessed_collection(collection(-55, -54))
    assert all(s["reference_quality"]["eligible"] for s in quiet["maps"][0]["states"])
    different_channel = collection()
    different_channel["maps"][0]["states"][1]["channel"] = 1
    assert all(
        s["reference_quality"]["eligible"]
        for s in assessed_collection(different_channel)["maps"][0]["states"]
    )


def test_generation_rejects_override_of_weak_reference_and_preserves_capture(
    client, monkeypatch
):
    data = collection()
    save_record("pair_tone_states", "qa", data)

    def forbidden(*a, **k):
        raise AssertionError("Do not extract or generate from the weak reference")

    monkeypatch.setattr(
        "app.services.tone_engine.engine.GuitarToneEngine.analyze", forbidden
    )
    result = client.post(
        "/api/v1/presets/qa/tone-states/quiet/generate",
        json={"role": "rhythm", "device": "MK20", "character": "distorted"},
    )
    assert result.status_code == 400, result.text
    assert "Guitarra muito fraca" in result.json()["detail"]
    assert load_record("pair_tone_states", "qa") == data
    listed = client.get("/api/v1/presets/qa/tone-states").json()
    assert listed["maps"][0]["states"][0]["id"] == "strong"
    assert listed["maps"][0]["states"][1]["reference_quality"]["eligible"] is False
