"""Archive complete-preset MK20 pilot evidence; no hardware I/O."""

import hashlib
import json
from datetime import datetime
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from .mk20_diagnostics import decode_image, decode64
from ..transport.protocol_mk20 import build_image, controls
from ..transport import sysex_codec as codec
from ..core.storage import save_record, list_records, load_record

router = APIRouter(prefix="/api/v1/mk20/transfers")


def validate(report):
    if (
        report.get("format") != "ai-tone-mk20-full-transfer"
        or report.get("version") != 1
        or report.get("device") != "MK20"
        or report.get("transport") != "usb"
        or report.get("slot") != 150
        or report.get("operation") not in {"send", "restore"}
    ):
        raise ValueError("Formato de envio MK20 inválido")
    date = datetime.fromisoformat(report.get("captured_at", "").replace("Z", "+00:00"))
    if date.tzinfo is None:
        raise ValueError("Data inválida")
    backup = report["backup"]
    if (
        backup.get("format") != "ai-tone-mk20-full-backup"
        or backup.get("version") != 1
        or backup.get("slot") != 150
        or backup.get("device") != "MK20"
    ):
        raise ValueError("Backup MK20 inválido")
    original, image = decode64(backup["image_base64"], 412), decode64(
        backup["target_base64"], 412
    )
    decode_image(original)
    decode_image(image)
    name = image[:20].split(b"\0", 1)[0].decode("ascii")
    if build_image(backup["preset"], name, original) != image:
        raise ValueError("Imagem não corresponde ao preset catalogado")
    restore = report["operation"] == "restore"
    target, before = (original, image) if restore else (image, original)
    trace = report.get("trace")
    if not isinstance(trace, list) or len(trace) > 192:
        raise ValueError("Trace inválido")
    stage = "preflight"
    confirmed = False
    writes = 0
    pending_read = False
    for entry in trace:
        raw = decode64(entry["bytes_base64"], 4096)
        direction = entry.get("direction")
        if direction not in {"tx", "rx"}:
            raise ValueError("Direção inválida")
        if direction == "rx" and raw == codec.ACK:
            if stage == "bank_ack":
                stage = "commit"
            elif stage == "commit_ack":
                stage = "readback"
            continue
        try:
            frame = codec.parse(raw)
        except ValueError:
            if direction == "tx":
                raise
            continue
        if direction == "tx":
            if frame.cls == 13:
                if (
                    frame.cmd != 0x41
                    or frame.length != 412
                    or frame.payload
                    or (frame.space, frame.field) != (0, 149 * 412)
                ):
                    raise ValueError("Consulta fora do piloto MK20")
                pending_read = True
            elif frame.cls == 9:
                writes += 1
                if stage == "bank" and (
                    frame.cmd,
                    frame.space,
                    frame.field,
                    frame.length,
                    frame.payload,
                ) == (0xD21, 0, 149 * 412, 412, target):
                    stage = "bank_ack"
                elif stage == "commit" and (
                    frame.cmd,
                    frame.space,
                    frame.field,
                    frame.length,
                    frame.payload,
                ) == (0x41, 15, 0, 0, b""):
                    stage = "commit_ack"
                else:
                    raise ValueError("Escrita fora da sequência MK20")
            else:
                raise ValueError("Comando não permitido")
        elif (
            pending_read
            and frame.cls == 13
            and frame.cmd in {0x41, 0x101, 0xD21}
            and frame.space == 0
            and frame.field == 149 * 412
            and frame.length == 412
            and len(frame.payload) == 412
        ):
            pending_read = False
            if stage == "preflight":
                if restore and frame.payload == original:
                    confirmed = True
                if frame.payload == before:
                    stage = "bank"
            elif stage == "readback" and frame.payload == target:
                confirmed = True
    return {
        "status": (
            ("restore_confirmed" if restore else "send_confirmed")
            if confirmed
            else "unconfirmed" if writes else "not_attempted"
        ),
        "slot": 150,
        "name": name,
        "writes": writes,
        "controls": controls(image),
        "original_sha256": hashlib.sha256(original).hexdigest(),
        "target_sha256": hashlib.sha256(image).hexdigest(),
    }


class Body(BaseModel):
    report: dict


@router.post("")
async def receive(body: Body):
    if len(json.dumps(body.report)) > 150000:
        raise HTTPException(400, "Relatório excede o limite")
    try:
        summary = validate(body.report)
    except (ValueError, TypeError, KeyError, AttributeError, UnicodeError) as exc:
        raise HTTPException(400, str(exc)) from exc
    key = hashlib.sha256(json.dumps(body.report, sort_keys=True).encode()).hexdigest()
    save_record(
        "mk20_transfer", key, {"id": key, "summary": summary, "report": body.report}
    )
    return {"id": key, **summary}


@router.get("")
async def index():
    return {
        "transfers": [
            {"id": r["id"], "captured_at": r["report"]["captured_at"], **r["summary"]}
            for r in list_records("mk20_transfer", 100)
        ]
    }


@router.get("/{report_id}")
async def retrieve(report_id: str):
    record = load_record("mk20_transfer", report_id)
    if not record:
        raise HTTPException(404, "Envio MK20 não encontrado")
    return record
