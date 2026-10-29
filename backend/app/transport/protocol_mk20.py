"""Reviewed MK20 AM4 controls. Never sends commands to hardware."""

import math
import re
import struct
from pathlib import Path
import json

SIZE = 412
BLOCKS = {
    "noise_gate": "GATE",
    "drive": "DS",
    "amp": "AMP",
    "cabinet": "CAB",
    "eq": "EQ",
    "modulation": "MOD",
    "delay": "DLY",
    "reverb": "REV",
    "volume": "VOL",
}


def catalog():
    return json.loads(
        (Path(__file__).resolve().parents[3] / "catalogs/mk20/catalog.json").read_text()
    )


def controls(image):
    """Decode supported controls in display units; retain raw values as evidence."""
    cat = catalog()
    output = []
    for key, block in cat["blocks"].items():
        index = block["block_id"]
        model = next((m for m in block["models"] if m["id"] == image[50 + index]), None)
        raw = list(struct.unpack_from("<12h", image, 60 + 24 * index))
        output.append(
            {
                "block": key,
                "block_id": index,
                "enabled": bool(image[40 + index]),
                "model_id": image[50 + index],
                "model_name": model["name"] if model else None,
                "parameters": (
                    {
                        name: raw[k] / model["params"][name].get("wire_scale", 1)
                        for k, name in enumerate(model["knobs"])
                    }
                    if model
                    else {}
                ),
                "knobs_raw": raw,
            }
        )
    return output


def build_image(preset, name, original):
    from ..api.mk20_diagnostics import decode_image

    decode_image(original)
    if preset.get("device") != "MK20" or preset.get("catalog_version") != "0.4.0":
        raise ValueError("Preset MK20 exige catálogo 0.4.0")
    if (
        not isinstance(name, str)
        or not re.fullmatch(r"[\x20-\x7e]{1,16}", name)
        or not name.strip()
    ):
        raise ValueError("Nome MK20 inválido")
    image = bytearray(original)
    image[:20] = name.encode("ascii").ljust(20, b"\0")
    image[40:50] = bytes(10)
    selected = []
    enabled = set()
    cat = catalog()
    for block in preset.get("effect_chain", []):
        definition = cat["blocks"].get(BLOCKS.get(block.get("effect_type")))
        if not definition:
            raise ValueError("Bloco MK20 não mapeado")
        index = definition["block_id"]
        if index in selected:
            raise ValueError("Bloco duplicado")
        selected.append(index)
        model = next(
            (
                m
                for m in definition["models"]
                if str(m["id"]) == str(block.get("model_id"))
                and m["name"] == block.get("model_name")
            ),
            None,
        )
        if model is None:
            raise ValueError("Modelo MK20 não mapeado")
        params = block.get("parameters", {})
        if set(params) - set(model["params"]):
            raise ValueError("Parâmetro não mapeado")
        image[40 + index] = int(bool(block.get("enabled", True)))
        image[50 + index] = model["id"]
        if image[40 + index]:
            enabled.add(block["effect_type"])
        image[60 + 24 * index : 84 + 24 * index] = bytes(24)
        for k, key in enumerate(model["knobs"]):
            spec = model["params"][key]
            value = params.get(key, spec.get("default"))
            if (
                not isinstance(value, (float, int))
                or isinstance(value, bool)
                or not math.isfinite(value)
                or not spec["min"] <= value <= spec["max"]
            ):
                raise ValueError("Controle MK20 fora da escala")
            step = (value - spec["min"]) / spec.get("step", 1)
            raw = value * spec.get("wire_scale", 1)
            if abs(step - round(step)) > 1e-5 or abs(raw - round(raw)) > 1e-5:
                raise ValueError("Passo MK20 inválido")
            struct.pack_into("<h", image, 60 + 24 * index + 2 * k, round(raw))
    if not {"amp", "cabinet"} <= enabled:
        raise ValueError("AMP e CAB devem estar ligados")
    image[30:40] = bytes(selected + [i for i in range(10) if i not in selected])
    volume = preset.get("preset_volume")
    volume = 40 if volume is None else volume
    if type(volume) is not int or not 0 <= volume <= 100:
        raise ValueError("Volume MK20 inválido")
    struct.pack_into("<H", image, 24, volume)
    if preset.get("bpm") is not None:
        bpm = preset["bpm"]
        if not isinstance(bpm, (float, int)) or not math.isfinite(bpm):
            raise ValueError("BPM inválido")
        struct.pack_into("<H", image, 26, min(250, max(40, math.floor(bpm + 0.5))))
    if preset.get("center_pan"):
        struct.pack_into("<h", image, 28, 0)
    return bytes(image)
