"""Evidence for a single-slot, name-only MK20 write pilot. No device I/O."""

import base64
import hashlib
import json
from datetime import datetime
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from ..core.storage import load_record, save_record, list_records
from ..transport import sysex_codec as codec
from .mk20_diagnostics import decode_image, decode64

router = APIRouter(prefix="/api/v1/mk20/name-pilots")
SIZE, SLOT, OFFSET = 412, 150, 149 * 412
TEST_NAME = b"AI TONE MK20"
LEGACY_NAME = b"AI TONE MK20 TEST"


def validate(report):
    if (
        report.get("format") != "ai-tone-mk20-name-pilot"
        or report.get("version") != 1
        or report.get("device") != "MK20"
        or report.get("transport") != "usb"
        or report.get("slot") != SLOT
        or report.get("operation") not in {"rename", "restore"}
    ):
        raise ValueError("Formato de teste de nome MK20 inválido")
    captured = datetime.fromisoformat(
        report.get("captured_at", "").replace("Z", "+00:00")
    )
    if captured.tzinfo is None:
        raise ValueError("Data sem fuso horário")
    backup = report.get("backup", {})
    if (
        backup.get("format") != "ai-tone-mk20-name-backup"
        or backup.get("version") != 1
        or backup.get("slot") != SLOT
    ):
        raise ValueError("Backup inválido")
    original = decode64(backup.get("original_base64"), SIZE)
    named = decode64(backup.get("named_base64"), SIZE)
    decoded = decode_image(original)
    expected_named = TEST_NAME.ljust(20, b"\0") + original[20:]
    if (
        named not in {expected_named, LEGACY_NAME.ljust(20, b"\0") + original[20:]}
        or named == original
    ):
        raise ValueError(
            "O teste só pode alterar o nome; controles e demais bytes devem permanecer intactos"
        )
    restore = report["operation"] == "restore"
    target = original if restore else named
    expected_before = named if restore else original
    preflight = False
    trace = report.get("trace")
    if not isinstance(trace, list) or len(trace) > 96:
        raise ValueError("Trace inválido")
    stage = "start"
    bank_sent = False
    last_query = None
    observed_original = False
    confirmed = False
    total = 0
    for event in trace:
        if not isinstance(event, dict) or event.get("direction") not in {"tx", "rx"}:
            raise ValueError("Evento inválido")
        raw = decode64(event.get("bytes_base64"), 4096)
        total += len(raw)
        if total > 65536:
            raise ValueError("Trace excede o limite")
        if event["direction"] == "rx" and raw == codec.ACK:
            if stage == "waiting_bank_ack":
                stage = "bank_ack"
            elif stage == "waiting_commit_ack":
                stage = "commit_ack"
            continue
        try:
            if any(b > 127 for b in raw[1:-1]):
                raise ValueError("Byte MIDI inválido")
            frame = codec.parse(raw)
        except (ValueError, IndexError):
            if event["direction"] == "tx":
                raise ValueError("Comando inválido no teste")
            continue
        if event["direction"] == "tx":
            last_query = None
            if (
                frame.cls == 13
                and frame.cmd == 0x41
                and frame.length == SIZE
                and not frame.payload
                and (frame.space, frame.field) in {(1, 0), (0, OFFSET)}
            ):
                last_query = (frame.space, frame.field)
            elif (
                frame.cls == 9
                and frame.space == 0
                and frame.field == OFFSET
                and frame.length == SIZE
                and frame.cmd == 0x41 + 8 * SIZE
                and frame.payload == target
                and not bank_sent
                and stage == "start"
                and preflight
            ):
                bank_sent = True
                stage = "waiting_bank_ack"
            elif (
                frame.cls == 9
                and frame.space == 15
                and frame.field == 0
                and frame.length == 0
                and frame.cmd == 0x41
                and not frame.payload
                and stage == "bank_ack"
            ):
                stage = "waiting_commit_ack"
            else:
                raise ValueError(
                    "Comando fora do teste de nome do slot 150; gravação repetida ou sequência inválida"
                )
        elif (
            last_query == (frame.space, frame.field)
            and frame.cls == 13
            and frame.cmd in {0x41, 0x101, 0xD21}
            and frame.length == SIZE
            and len(frame.payload) == SIZE
        ):
            try:
                decode_image(frame.payload)
            except ValueError:
                continue
            if frame.space == 0:
                if stage == "start":
                    preflight = frame.payload == expected_before or (
                        restore
                        and named[:20] == LEGACY_NAME.ljust(20, b"\0")
                        and frame.payload
                        == LEGACY_NAME[:16].ljust(20, b"\0") + named[20:]
                    )
                observed_original = frame.payload == original
                confirmed = stage == "commit_ack" and frame.payload == target
    status = (
        ("restore_confirmed" if restore else "rename_confirmed")
        if confirmed
        else (
            "already_original"
            if restore and not bank_sent and observed_original
            else "unconfirmed" if bank_sent else "not_attempted"
        )
    )
    return {
        "status": status,
        "slot": SLOT,
        "operation": report["operation"],
        "original_name": decoded["name"],
        "test_name": decode_image(named)["name"],
        "original_sha256": hashlib.sha256(original).hexdigest(),
        "named_sha256": hashlib.sha256(named).hexdigest(),
        "write_attempted": bank_sent,
        "parameters_changed": False,
    }


class Body(BaseModel):
    report: dict


@router.post("")
async def receive(body: Body):
    if len(json.dumps(body.report)) > 150000:
        raise HTTPException(400, "Relatório excede o limite")
    try:
        summary = validate(body.report)
    except (ValueError, TypeError, KeyError, AttributeError) as exc:
        raise HTTPException(400, str(exc)) from exc
    key = hashlib.sha256(json.dumps(body.report, sort_keys=True).encode()).hexdigest()
    if not load_record("mk20_name_pilot", key):
        save_record(
            "mk20_name_pilot",
            key,
            {"id": key, "summary": summary, "report": body.report},
        )
    return {"id": key, **summary}


@router.get("")
async def index():
    return {
        "pilots": [
            {
                "id": row["id"],
                "captured_at": row["report"]["captured_at"],
                **row["summary"],
            }
            for row in list_records("mk20_name_pilot", 100)
        ]
    }


@router.get("/{record_id}")
async def retrieve(record_id: str):
    result = load_record("mk20_name_pilot", record_id)
    if result is None:
        raise HTTPException(404, "Teste de nome MK20 não encontrado")
    return result
