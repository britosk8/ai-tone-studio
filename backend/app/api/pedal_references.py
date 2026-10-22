"""Sincronização local-first das referências, separada da geração por áudio."""
import base64
import binascii
import struct
import os
from pathlib import Path
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..core.storage import load_record, save_record, list_records
from ..services.device_catalog.loader import CatalogLoader
from ..models.devices import DeviceModel

router = APIRouter(prefix="/api/v1")


class ReferenceSync(BaseModel):
    reference: dict
    generated_preset: dict


def decode_reference(reference: dict, catalog: dict) -> dict:
    if (reference.get("format") != "ai-tone-pedal-reference" or
        reference.get("version") != 1 or reference.get("device") != "MK300"):
        raise ValueError("Formato de referência inválido")
    slot = reference.get("slot")
    if type(slot) is not int or not 1 <= slot <= 160:
        raise ValueError("Slot deve estar entre 1 e 160")
    try:
        captured = datetime.fromisoformat(reference.get("captured_at", "").replace("Z", "+00:00"))
        if captured.tzinfo is None:
            raise ValueError("Data sem fuso horário")
    except (ValueError, TypeError, AttributeError) as error:
        raise ValueError("Data de captura inválida") from error
    encoded = reference.get("image_base64", "")
    if not isinstance(encoded, str) or len(encoded) > 1024:
        raise ValueError("Imagem inválida")
    try:
        image = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValueError("Imagem base64 inválida") from error
    if len(image) != 448 or image[20:24] != bytes([255, 144, 30, 0]) or image[447] != 69:
        raise ValueError("Layout de referência MK300 inválido")
    if sorted(image[32:43]) != list(range(11)):
        raise ValueError("Ordem de cadeia inválida")
    blocks_by_id = {b["block_id"]: b for b in catalog["blocks"].values()}
    types = ["wah", "compressor", "noise_gate", "drive", "amp", "cabinet",
             "eq", "modulation", "delay", "reverb", "volume"]
    chain = []
    for order, block_id in enumerate(image[32:43]):
        model_id = image[54 + block_id]
        models = blocks_by_id[block_id]["models"]
        model = next((m for m in models if m["id"] == model_id), None)
        if image[43 + block_id] not in (0, 1) or model is None:
            raise ValueError("Modelo ou estado fora do catálogo MK300")
        chain.append({"slot": str(order), "effect_type": types[block_id],
            "model_id": str(model_id), "model_name": model["name"],
            "enabled": bool(image[43 + block_id]),
            "parameters": {name: struct.unpack_from("<h", image, 66 + 24 * block_id + 2 * k)[0]
                           for k, name in enumerate(model["knobs"])}})
    return {"name": image[:20].split(b"\0", 1)[0].decode("utf-8", errors="replace"),
            "device": "MK300", "catalog_version": catalog["_meta"]["catalog_version"],
            "preset_volume": struct.unpack_from("<H", image, 24)[0],
            "pan_raw": struct.unpack_from("<h", image, 28)[0],
            "bpm": struct.unpack_from("<H", image, 26)[0], "effect_chain": chain}


def _key(pair_id: str, role: str):
    if not 1 <= len(pair_id) <= 200 or role not in {"rhythm", "lead"}:
        raise HTTPException(400, "Análise ou função inválida")
    import json
    return json.dumps([pair_id, role])


def configuration_rows(generated: dict, reference: dict):
    labels = {"wah": "Wah", "compressor": "Compressor", "noise_gate": "Noise gate",
              "drive": "Drive", "amp": "Amplificador", "cabinet": "Gabinete", "eq": "EQ",
              "modulation": "Modulação", "delay": "Delay", "reverb": "Reverb", "volume": "Volume"}
    chain = generated["effect_chain"]
    if len(chain) > 11 or any(not isinstance(b, dict) or b.get("effect_type") not in labels or
                              not isinstance(b.get("parameters", {}), dict) for b in chain):
        raise ValueError("Cadeia do preset gerado inválida")
    rows = []
    def add(label, left, right):
        rows.append({"label": label, "generated": left, "reference": right, "changed": left != right})
    def value(v):
        return "Ausente" if v is None else format(v, "g") if isinstance(v, (int, float)) else str(v)
    add("Cadeia ativa", " → ".join(b.get("model_name", "") for b in chain if b.get("enabled")),
        " → ".join(b["model_name"] for b in reference["effect_chain"] if b["enabled"]))
    add("Volume do preset", str(generated.get("preset_volume")) if generated.get("preset_volume") is not None else "Herdado do destino", str(reference["preset_volume"]))
    add("Panorama", "Centro" if generated.get("center_pan") else "Herdado do destino", "Centro" if reference["pan_raw"] == 0 else "Fora do centro")
    a = {b["effect_type"]: b for b in chain}
    b = {block["effect_type"]: block for block in reference["effect_chain"]}
    for kind in dict.fromkeys([*a, *b]):
        left, right = a.get(kind, {}), b.get(kind, {})
        add(labels[kind] + " • estado", "Ligado" if left.get("enabled") else "Desligado", "Ligado" if right.get("enabled") else "Desligado")
        if not left.get("enabled") and not right.get("enabled"):
            continue
        add(labels[kind] + " • modelo", left.get("model_name", "Ausente"), right.get("model_name", "Ausente"))
        lp, rp = left.get("parameters", {}), right.get("parameters", {})
        suffix = "" if left.get("model_id") == right.get("model_id") and left.get("model_name") == right.get("model_name") else " (modelos distintos)"
        for knob in dict.fromkeys([*lp, *rp]):
            add(labels[kind] + " • " + knob + suffix, value(lp.get(knob)), value(rp.get(knob)))
    return rows


@router.put("/presets/{pair_id}/pedal-reference/{role}")
async def sync_reference(pair_id: str, role: str, body: ReferenceSync):
    key = _key(pair_id, role)
    import json
    try:
        length = len(json.dumps(body.model_dump(), allow_nan=False))
    except ValueError as error:
        raise HTTPException(400, "Referência contém valores não finitos") from error
    if length > 150_000:
        raise HTTPException(413, "Referência acima do limite")
    preset = body.generated_preset
    if (preset.get("device") != "MK300" or preset.get("role") != role or
        not isinstance(preset.get("effect_chain"), list)):
        raise HTTPException(400, "Preset gerado incompatível com a referência")
    try:
        catalog = CatalogLoader(Path(os.environ["CATALOGS_DIR"]) if "CATALOGS_DIR" in os.environ else None)._catalogs[DeviceModel.MK300]
        decoded = decode_reference(body.reference, catalog)
        comparison = configuration_rows(preset, decoded)
    except (ValueError, KeyError, TypeError) as error:
        raise HTTPException(400, str(error)) from error
    record = {"pair_id": pair_id, "role": role, "reference": body.reference,
              "decoded_reference": decoded, "generated_preset": preset,
              "synced_at": datetime.now(timezone.utc).isoformat(),
              "comparison_kind": "configuration_not_audio_similarity"}
    record["comparison"] = comparison
    existing = load_record("pedal_reference", key)
    if existing:
        previous = datetime.fromisoformat(existing["reference"]["captured_at"].replace("Z", "+00:00"))
        captured = datetime.fromisoformat(body.reference["captured_at"].replace("Z", "+00:00"))
        if previous > captured:
            return existing
    save_record("pedal_reference", key, record)
    return record


@router.get("/presets/{pair_id}/pedal-reference/{role}")
async def get_reference(pair_id: str, role: str):
    record = load_record("pedal_reference", _key(pair_id, role))
    if record is None:
        raise HTTPException(404, "Referência do pedal ainda não sincronizada")
    return record


@router.get("/pedal-references")
async def references():
    return {"references": list_records("pedal_reference")}
