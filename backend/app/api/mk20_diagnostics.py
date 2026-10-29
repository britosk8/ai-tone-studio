"""MK20 read-only evidence. Never produces or authorizes a bank-write command."""

import base64
import binascii
import hashlib
import json
import struct
from datetime import datetime
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from ..core.storage import load_record, save_record, list_records
from ..transport import sysex_codec as codec

router = APIRouter(prefix="/api/v1/mk20/diagnostics")
SIZE = 412


def decode_image(image):
    if (
        len(image) != SIZE
        or image[20:24] != bytes([255, 144, 30, 0])
        or sorted(image[30:40]) != list(range(10))
        or any(b not in (0, 1) for b in image[40:50])
    ):
        raise ValueError("Layout MK20 de 412 bytes não confirmado")
    return {
        "name": image[:20].split(b"\0", 1)[0].decode("utf-8", errors="replace"),
        "volume_raw": struct.unpack_from("<H", image, 24)[0],
        "bpm_raw": struct.unpack_from("<H", image, 26)[0],
        "chain_raw": list(image[30:40]),
        "enabled_raw": list(image[40:50]),
        "model_ids_raw": list(image[50:60]),
        "image_sha256": hashlib.sha256(image).hexdigest(),
    }


def decode64(value, limit):
    if not isinstance(value, str) or len(value) > (limit + 2) // 3 * 4:
        raise ValueError("Pacote excede o limite")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise ValueError("Pacote base64 inválido") from exc
    if len(decoded) > limit:
        raise ValueError("Pacote excede o limite")
    return decoded


def validate_report(report):
    if (
        report.get("format") != "ai-tone-mk20-diagnostic"
        or report.get("version") != 1
        or report.get("device") != "MK20"
        or report.get("transport") != "usb"
        or report.get("write_enabled") is not False
    ):
        raise ValueError("Formato de diagnóstico MK20 inválido")
    slot = report.get("slot")
    if type(slot) is not int or not 1 <= slot <= 150:
        raise ValueError("Slot MK20 deve estar entre 1 e 150")
    try:
        date = datetime.fromisoformat(
            report.get("captured_at", "").replace("Z", "+00:00")
        )
        if date.tzinfo is None:
            raise ValueError("Data sem fuso horário")
    except (ValueError, TypeError, AttributeError) as exc:
        raise ValueError("Data de captura inválida") from exc
    for key in ["device_name", "firmware_reported"]:
        if not isinstance(report.get(key), str) or len(report[key]) > 200:
            raise ValueError("Identificação do equipamento inválida")
    trace = report.get("trace")
    if not isinstance(trace, list) or len(trace) > 96:
        raise ValueError("Trace inválido")
    requests, replies = set(), {}
    total = 0
    for entry in trace:
        if not isinstance(entry, dict) or entry.get("direction") not in {
            "tx",
            "rx",
            "rx_raw",
        }:
            raise ValueError("Evento de trace inválido")
        raw = decode64(entry.get("bytes_base64"), 4096)
        total += len(raw)
        if total > 32768:
            raise ValueError("Trace excede o limite")
        if entry["direction"] == "rx_raw":
            continue
        try:
            if any(b > 127 for b in raw[1:-1]):
                raise ValueError("Byte MIDI não codificado")
            frame = codec.parse(raw)
        except (ValueError, IndexError):
            if entry["direction"] == "tx":
                raise ValueError("Consulta inválida no trace")
            continue
        key = (frame.space, frame.field)
        expected = key in {(1, 0), (0, (slot - 1) * SIZE)}
        if entry["direction"] == "tx":
            if not (
                expected
                and frame.cls == 13
                and frame.cmd == 0x41
                and frame.length == SIZE
                and not frame.payload
            ):
                raise ValueError(
                    "Diagnóstico aceita apenas leitura do preset ativo e do slot selecionado"
                )
            requests.add(key)
        elif (
            expected
            and key in requests
            and frame.cls == 13
            and frame.cmd in {0x41, 0x101}
            and frame.length == SIZE
            and len(frame.payload) == SIZE
        ):
            try:
                decoded = decode_image(frame.payload)
                replies[key] = decoded
            except ValueError:
                pass
    reads = report.get("reads")
    if not isinstance(reads, list) or len(reads) != 2:
        raise ValueError("Informe o resultado das duas leituras")
    expected_keys = {(1, 0), (0, (slot - 1) * SIZE)}
    seen = set()
    for read in reads:
        if not isinstance(read, dict):
            raise ValueError("Leitura inválida")
        key = (read.get("space"), read.get("field"))
        if key not in expected_keys or key in seen:
            raise ValueError("Leitura não corresponde ao slot")
        seen.add(key)
        decoded = read.get("decoded")
        if decoded is not None:
            if not isinstance(decoded, dict):
                raise ValueError("Imagem inválida")
            image = decode64(decoded.get("image_base64"), SIZE)
            verified = decode_image(image)
            if key not in replies or verified != replies[key]:
                raise ValueError("Imagem não corresponde à resposta registrada")
    complete = all(key in replies for key in expected_keys)
    return {
        "status": "read_layout_confirmed" if complete else "read_incomplete",
        "slot": slot,
        "write_enabled": False,
        "reads": [{"space": k[0], "field": k[1], **v} for k, v in replies.items()],
        "note": "Leitura compatível não valida comandos de gravação nem mapeamento dos modelos MK20.",
    }


class DiagnosticBody(BaseModel):
    report: dict = Field(...)


@router.post("")
async def receive(body: DiagnosticBody):
    # The base64/trace limits are also enforced before parsing individual frames.
    if len(json.dumps(body.report)) > 80000:
        raise HTTPException(400, "Diagnóstico excede o limite")
    try:
        summary = validate_report(body.report)
    except (ValueError, TypeError, KeyError) as exc:
        raise HTTPException(400, str(exc)) from exc
    key = hashlib.sha256(json.dumps(body.report, sort_keys=True).encode()).hexdigest()
    save_record(
        "mk20_diagnostic", key, {"id": key, "summary": summary, "report": body.report}
    )
    return {"id": key, **summary}


@router.get("")
async def index():
    return {
        "diagnostics": [
            {
                "id": r["id"],
                "captured_at": r["report"]["captured_at"],
                "device_name": r["report"]["device_name"],
                **r["summary"],
            }
            for r in list_records("mk20_diagnostic", 100)
        ]
    }


@router.get("/{report_id}")
async def retrieve(report_id: str):
    result = load_record("mk20_diagnostic", report_id)
    if not result:
        raise HTTPException(404, "Diagnóstico MK20 não encontrado")
    return result
