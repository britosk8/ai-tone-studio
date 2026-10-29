import base64
import copy
import json
import struct
from pathlib import Path
import pytest
from app.transport.protocol_mk20 import build_image, controls
from app.transport import sysex_codec as c
from app.api.mk20_transfers import validate
from tests.test_mk20_diagnostics import image
from tests.test_mk20_name_pilot import event
from tests.test_v1_flow import client


def preset():
    return {
        "id": "mk20-qa",
        "name": "MK20 QA",
        "device": "MK20",
        "catalog_version": "0.4.0",
        "role": "rhythm",
        "preset_volume": 60,
        "effect_chain": [
            {
                "effect_type": "noise_gate",
                "model_id": "0",
                "model_name": "AI Gate",
                "parameters": {"Gate": 40, "Bias": 50},
            },
            {
                "effect_type": "drive",
                "model_id": "21",
                "model_name": "22TS-9",
                "parameters": {
                    "Gain": 10,
                    "Level": 80,
                    "Bass": 42,
                    "Middle": 58,
                    "Treble": 52,
                    "Reso": 0,
                    "Pres": 50,
                    "Bright": 60,
                },
            },
            {
                "effect_type": "amp",
                "model_id": "69",
                "model_name": "70OD2_meas",
                "parameters": {
                    "Gain": 56,
                    "Level": 60,
                    "Bass": 58,
                    "Middle": 49,
                    "Treble": 60,
                    "Reso": 35,
                    "Pres": 58,
                    "Bright": 45,
                },
            },
            {
                "effect_type": "cabinet",
                "model_id": "53",
                "model_name": "54MbSOSS4t412",
                "parameters": {"Level": 80, "Low Cut": 80, "High Cut": 7500},
            },
            {
                "effect_type": "eq",
                "model_id": "0",
                "model_name": "Guitar EQ 6",
                "parameters": {
                    "100Hz": 2,
                    "200Hz": 0,
                    "400Hz": -1.5,
                    "800Hz": 1,
                    "1.6kHz": 2.5,
                    "3.2kHz": 0.5,
                },
            },
        ],
    }


def report(restore=False):
    original = image()
    target = build_image(preset(), "QA INFEST", original)
    before, after = (target, original) if restore else (original, target)
    return {
        "format": "ai-tone-mk20-full-transfer",
        "version": 1,
        "device": "MK20",
        "transport": "usb",
        "slot": 150,
        "operation": "restore" if restore else "send",
        "captured_at": "2026-10-29T22:30:00Z",
        "backup": {
            "format": "ai-tone-mk20-full-backup",
            "version": 1,
            "device": "MK20",
            "slot": 150,
            "image_base64": base64.b64encode(original).decode(),
            "target_base64": base64.b64encode(target).decode(),
            "preset": preset(),
        },
        "trace": [
            event("tx", c.read(61388, 412, 0)),
            event("rx", c.build(13, 0xD21, 61388, 412, 0, before)),
            event("tx", c.build(9, 0xD21, 61388, 412, 0, after)),
            event("rx", c.ACK),
            event("tx", c.build(9, 0x41, 0, 0, 15)),
            event("rx", c.ACK),
            event("tx", c.read(61388, 412, 0)),
            event("rx", c.build(13, 0xD21, 61388, 412, 0, after)),
        ],
    }


def test_verified_controls_scales_tail_and_matching_android_catalog():
    before = image()
    after = build_image(preset(), "QA INFEST", before)
    assert after[300:] == before[300:]
    blocks = {b["block"]: b for b in controls(after)}
    assert blocks["DS"]["model_id"] == 21
    assert blocks["AMP"]["model_id"] == 69
    assert blocks["CAB"]["model_id"] == 53
    assert blocks["CAB"]["knobs_raw"][:3] == [80, 80, 75]
    assert blocks["EQ"]["knobs_raw"][:6] == [4, 0, -3, 2, 5, 1]
    assert blocks["EQ"]["parameters"]["400Hz"] == -1.5
    assert blocks["CAB"]["parameters"]["High Cut"] == 7500
    root = Path(__file__).resolve().parents[2]
    assert json.loads((root / "catalogs/mk20/catalog.json").read_text()) == json.loads(
        (root / "android/assets/mk20_catalog.json").read_text()
    )


@pytest.mark.parametrize("restore", [False, True])
def test_archive_verified_send_and_restore(client, restore):
    data = report(restore)
    result = client.post("/api/v1/mk20/transfers", json={"report": data})
    assert result.status_code == 200, result.text
    assert result.json()["status"] == (
        "restore_confirmed" if restore else "send_confirmed"
    )
    assert result.json()["writes"] == 2
    assert (
        client.post("/api/v1/mk20/transfers", json={"report": data}).json()["id"]
        == result.json()["id"]
    )
    assert len(client.get("/api/v1/mk20/transfers").json()["transfers"]) == 1


@pytest.mark.parametrize(
    "mutation",
    [
        "slot",
        "repeat",
        "no_preflight",
        "no_ack",
        "wrong_command",
        "payload",
        "unknown_control",
    ],
)
def test_invalid_write_evidence_rejected(client, mutation):
    data = report()
    if mutation == "slot":
        data["slot"] = 76
    elif mutation == "repeat":
        data["trace"].insert(4, data["trace"][2])
    elif mutation == "no_preflight":
        data["trace"] = data["trace"][2:]
    elif mutation == "no_ack":
        del data["trace"][3]
    elif mutation == "wrong_command":
        f = c.parse(base64.b64decode(data["trace"][2]["bytes_base64"]))
        data["trace"][2] = event("tx", c.build(9, 0xCC1, f.field, 412, 0, f.payload))
    elif mutation == "payload":
        raw = bytearray(base64.b64decode(data["backup"]["target_base64"]))
        raw[120] ^= 1
        data["backup"]["target_base64"] = base64.b64encode(raw).decode()
    else:
        data["backup"]["preset"]["effect_chain"][2]["parameters"]["invented"] = 50
    result = client.post("/api/v1/mk20/transfers", json={"report": data})
    assert result.status_code == 400, result.text


def test_missing_readback_never_claims_success():
    data = report()
    data["trace"] = data["trace"][:-2]
    assert validate(data)["status"] == "unconfirmed"
    data["trace"] = data["trace"][:2]
    assert validate(data)["status"] == "not_attempted"


@pytest.mark.parametrize("value", [7501, 4999, 18001, float("nan")])
def test_invalid_cabinet_value(value):
    data = preset()
    data["effect_chain"][3]["parameters"]["High Cut"] = value
    with pytest.raises(ValueError):
        build_image(data, "QA", image())
