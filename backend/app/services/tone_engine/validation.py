"""Bloqueia modelo/parâmetro fora do catálogo, sem consultar outro aparelho."""

import math
from ...models.devices import EffectType
from ..device_catalog.loader import EFFECT_TO_BLOCK_KEY


def models_for(catalog, device, effect_type):
    cat = catalog._catalogs.get(device, {})
    key = {
        **EFFECT_TO_BLOCK_KEY,
        EffectType.AMP: "AMP",
        EffectType.CABINET: "CAB",
        EffectType.DRIVE: "DS",
    }[effect_type]
    if key == "AMP":
        block = cat.get("blocks", {}).get(key) or cat.get("amp_models", {})
        params = block.get(
            "knob_ranges",
            block.get("common_knob_ranges", block.get("amp_parameters", {})),
        )
    elif key == "CAB":
        block = cat.get("blocks", {}).get(key) or cat.get("cab_models", {})
        params = block.get("knob_ranges", block.get("cab_parameters", {}))
    elif key == "DS":
        block = cat.get("blocks", {}).get(key) or cat.get("ds_models", {})
        params = block.get("knob_ranges", block.get("ds_parameters", {}))
    else:
        found = []
        for index in range(256):
            model = catalog.get_effect_model(device, effect_type, index)
            if model is None:
                break
            if found and str(model["id"]) == str(found[-1]["id"]):
                break
            found.append(model)
        return found
    models = block.get("models", block.get("selected_models", []))
    return [
        {**m, "parameters": {**params, **m.get("params", m.get("parameters", {}))}}
        for m in models
    ]


def validate_preset(catalog, preset):
    for block in preset.effect_chain.blocks:
        matches = [
            m
            for m in models_for(catalog, preset.device_model, block.effect_type)
            if str(m["id"]) == block.model_id and m["name"] == block.model_name
        ]
        if not matches:
            raise ValueError(
                f"NEEDS_DEVICE_DATA: {preset.device_model.value}/{block.effect_type.value}/{block.model_name}"
            )
        specs = matches[0]["parameters"]
        for parameter in block.parameters:
            spec = specs.get(parameter.name)
            value = parameter.raw_value
            if (
                spec is None
                or not math.isfinite(value)
                or not spec.get("min", 0) <= value <= spec.get("max", 100)
            ):
                raise ValueError(
                    f"NEEDS_DEVICE_DATA: parâmetro inválido {block.model_name}/{parameter.name}"
                )
            step = spec.get("step", 1)
            if (
                step
                and abs(
                    (value - spec.get("min", 0)) / step
                    - round((value - spec.get("min", 0)) / step)
                )
                > 1e-5
            ):
                raise ValueError(f"NEEDS_DEVICE_DATA: passo inválido {parameter.name}")
    if not all(
        any(b.enabled and b.effect_type == kind for b in preset.effect_chain.blocks)
        for kind in (EffectType.AMP, EffectType.CABINET)
    ):
        raise ValueError("NEEDS_DEVICE_DATA: modelo AMP/CAB ausente.")
