import base64
import copy
import pytest
from app.api.mk20_name_pilot import validate, TEST_NAME
from app.transport import sysex_codec as c
from tests.test_mk20_diagnostics import image
from tests.test_v1_flow import client


def event(direction, data):
    return {"direction": direction, "bytes_base64": base64.b64encode(data).decode()}


def report(restore=False):
    original = image()
    named = TEST_NAME.ljust(20, b"\0") + original[20:]
    target, before = (original, named) if restore else (named, original)
    return {
        "format": "ai-tone-mk20-name-pilot",
        "version": 1,
        "device": "MK20",
        "transport": "usb",
        "slot": 150,
        "operation": "restore" if restore else "rename",
        "captured_at": "2026-10-29T21:12:00Z",
        "status": "confirmed",
        "backup": {
            "format": "ai-tone-mk20-name-backup",
            "version": 1,
            "slot": 150,
            "original_base64": base64.b64encode(original).decode(),
            "named_base64": base64.b64encode(named).decode(),
        },
        "trace": [
            event("tx", c.read(61388, 412, 0)),
            event("rx", c.build(13, 0xD21, 61388, 412, 0, before)),
            event("tx", c.build(9, 0xD21, 61388, 412, 0, target)),
            event("rx", c.ACK),
            event("tx", c.build(9, 0x41, 0, 0, 15)),
            event("rx", c.ACK),
            event("tx", c.read(61388, 412, 0)),
            event("rx", c.build(13, 0xD21, 61388, 412, 0, target)),
        ],
    }


@pytest.mark.parametrize("restore", [False, True])
def test_pilot_is_verified_archived_and_idempotent(client, restore):
    data = report(restore)
    result = client.post("/api/v1/mk20/name-pilots", json={"report": data})
    assert result.status_code == 200, result.text
    summary = result.json()
    assert summary["status"] == ("restore_confirmed" if restore else "rename_confirmed")
    assert summary["parameters_changed"] is False
    assert (
        client.get("/api/v1/mk20/name-pilots/" + summary["id"]).json()["report"] == data
    )
    assert (
        client.post("/api/v1/mk20/name-pilots", json={"report": data}).json()["id"]
        == summary["id"]
    )
    assert len(client.get("/api/v1/mk20/name-pilots").json()["pilots"]) == 1


@pytest.mark.parametrize(
    "mutation",
    [
        "controls",
        "slot",
        "repeat",
        "commit_first",
        "missing_preflight",
        "wrong_command",
    ],
)
def test_pilot_rejects_other_changes_and_invalid_sequence(client, mutation):
    data = copy.deepcopy(report())
    if mutation == "controls":
        raw = bytearray(base64.b64decode(data["backup"]["named_base64"]))
        raw[100] ^= 1
        data["backup"]["named_base64"] = base64.b64encode(raw).decode()
    elif mutation == "slot":
        old = c.parse(base64.b64decode(data["trace"][2]["bytes_base64"]))
        data["trace"][2] = event("tx", c.build(9, 0xD21, 0, 412, 0, old.payload))
    elif mutation == "repeat":
        data["trace"].insert(4, data["trace"][2])
    elif mutation == "commit_first":
        data["trace"][2] = data["trace"][4]
    elif mutation == "missing_preflight":
        data["trace"] = data["trace"][2:]
    else:
        old = c.parse(base64.b64decode(data["trace"][2]["bytes_base64"]))
        data["trace"][2] = event("tx", c.build(9, 0xCC1, 61388, 412, 0, old.payload))
    assert (
        client.post("/api/v1/mk20/name-pilots", json={"report": data}).status_code
        == 400
    )


def test_acks_without_readback_never_confirm_and_failure_is_preserved(client):
    data = report()
    data["trace"] = data["trace"][:6]
    response = client.post("/api/v1/mk20/name-pilots", json={"report": data})
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "unconfirmed"
    assert response.json()["write_attempted"]


def test_original_without_write_is_recognized_on_restore(client):
    data = report(True)
    data["trace"] = [
        event("tx", c.read(61388, 412, 0)),
        event("rx", c.build(13, 0xD21, 61388, 412, 0, image())),
    ]
    assert validate(data)["status"] == "already_original"


@pytest.mark.parametrize("mutate_controls", [False, True])
def test_restore_of_legacy_name_truncated_at_16_is_narrowly_allowed(
    client, mutate_controls
):
    from app.api.mk20_name_pilot import LEGACY_NAME

    data = report(True)
    original = image()
    named = LEGACY_NAME.ljust(20, b"\0") + original[20:]
    data["backup"]["named_base64"] = base64.b64encode(named).decode()
    current = bytearray(LEGACY_NAME[:16].ljust(20, b"\0") + original[20:])
    if mutate_controls:
        current[100] ^= 1
    data["trace"][1] = event("rx", c.build(13, 0xD21, 61388, 412, 0, bytes(current)))
    response = client.post("/api/v1/mk20/name-pilots", json={"report": data})
    if mutate_controls:
        assert response.status_code == 400
    else:
        assert response.status_code == 200, response.text
        assert response.json()["status"] == "restore_confirmed"
        assert response.json()["test_name"] == LEGACY_NAME.decode()
