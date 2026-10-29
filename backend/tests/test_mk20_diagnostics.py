"""Read-only MK20 validation; synthesized records never replace physical captures."""

import base64
import copy
import struct
import pytest
from app.api.mk20_diagnostics import decode_image
from app.transport import sysex_codec as codec
from tests.test_v1_flow import client


def image():
    raw = bytearray(412)
    raw[:7] = b"MK20 QA"
    raw[20:24] = bytes([255, 144, 30, 0])
    struct.pack_into("<HH", raw, 24, 60, 120)
    raw[30:40] = bytes(range(10))
    raw[40:50] = bytes([1, 0] * 5)
    raw[50:60] = bytes(range(10))
    return bytes(raw)


def report(slot=150):
    raw = image()
    result = {
        "format": "ai-tone-mk20-diagnostic",
        "version": 1,
        "device": "MK20",
        "transport": "usb",
        "device_name": "USB MK20",
        "firmware_reported": "Não sei",
        "slot": slot,
        "captured_at": "2026-10-29T12:00:00Z",
        "write_enabled": False,
        "reads": [],
        "trace": [],
    }
    for space, field in [(1, 0), (0, (slot - 1) * 412)]:
        result["trace"].extend(
            [
                {
                    "direction": "tx",
                    "bytes_base64": base64.b64encode(
                        codec.read(field, 412, space)
                    ).decode(),
                },
                {
                    "direction": "rx",
                    "bytes_base64": base64.b64encode(
                        codec.build(13, 0x41, field, 412, space, raw)
                    ).decode(),
                },
            ]
        )
        result["reads"].append(
            {
                "space": space,
                "field": field,
                "decoded": {"image_base64": base64.b64encode(raw).decode()},
            }
        )
    return result


def test_reads_are_verified_saved_and_idempotent(client):
    original = report()
    response = client.post("/api/v1/mk20/diagnostics", json={"report": original})
    assert response.status_code == 200, response.text
    result = response.json()
    assert (
        result["status"] == "read_layout_confirmed" and result["write_enabled"] is False
    )
    assert result["reads"][0]["name"] == "MK20 QA"
    assert result["reads"][1]["field"] == 61388
    assert (
        client.get("/api/v1/mk20/diagnostics/" + result["id"]).json()["report"]
        == original
    )
    assert (
        client.post("/api/v1/mk20/diagnostics", json={"report": original}).json()["id"]
        == result["id"]
    )
    assert len(client.get("/api/v1/mk20/diagnostics").json()["diagnostics"]) == 1


def test_failure_and_partial_reads_remain_diagnostic_not_success(client):
    partial = report()
    partial["trace"] = partial["trace"][:2]
    partial["reads"][1] = {"space": 0, "field": 61388, "error": "Timeout"}
    response = client.post("/api/v1/mk20/diagnostics", json={"report": partial})
    assert response.status_code == 200
    assert response.json()["status"] == "read_incomplete"
    partial["trace"] = []
    partial["reads"][0] = {"space": 1, "field": 0, "error": "USB indisponível"}
    assert (
        client.post("/api/v1/mk20/diagnostics", json={"report": partial}).json()[
            "status"
        ]
        == "read_incomplete"
    )


@pytest.mark.parametrize(
    "mutation",
    [
        "write",
        "load",
        "commit",
        "wrong_slot",
        "fabricated_image",
        "oversized",
        "wrong_device",
    ],
)
def test_rejects_writes_mismatched_images_and_bad_metadata(client, mutation):
    data = copy.deepcopy(report())
    if mutation in {"write", "load", "commit"}:
        cmd = {
            "write": codec.build(9, 0x51, 24, 2, 1, b"\x01\x00"),
            "load": codec.build(9, 0x49, 5, 1, 14, b"\x01"),
            "commit": codec.build(9, 0x41, 0, 0, 15),
        }[mutation]
        data["trace"][0]["bytes_base64"] = base64.b64encode(cmd).decode()
    elif mutation == "wrong_slot":
        data["slot"] = 151
    elif mutation == "fabricated_image":
        raw = bytearray(image())
        raw[100] = 5
        data["reads"][0]["decoded"]["image_base64"] = base64.b64encode(raw).decode()
    elif mutation == "oversized":
        data["trace"][0]["bytes_base64"] = "A" * 6000
    else:
        data["device"] = "MK300"
    assert (
        client.post("/api/v1/mk20/diagnostics", json={"report": data}).status_code
        == 400
    )


def test_layout_rejects_mk300_size_duplicate_chain_and_invalid_states():
    assert decode_image(image())["volume_raw"] == 60
    for field, value in [(30, 9), (40, 2), (20, 0)]:
        invalid = bytearray(image())
        invalid[field] = value
        with pytest.raises(ValueError):
            decode_image(invalid)
    with pytest.raises(ValueError):
        decode_image(image() + bytes(36))


def test_block_read_reply_command_is_supported(client):
    data = report()
    for entry in data["trace"]:
        if entry["direction"] == "rx":
            old = codec.parse(base64.b64decode(entry["bytes_base64"]))
            entry["bytes_base64"] = base64.b64encode(
                codec.build(13, 0x101, old.field, old.length, old.space, old.payload)
            ).decode()
    result = client.post("/api/v1/mk20/diagnostics", json={"report": data})
    assert result.status_code == 200, result.text
    assert result.json()["status"] == "read_layout_confirmed"
