"""
Converte um Preset (modelo de dados) para PresetStruct (formato de hardware MK300).
"""
import logging
import os
from pathlib import Path
from typing import Optional

from ..models.preset import Preset, EffectBlock
from ..models.devices import EffectType, DeviceModel
from ..services.device_catalog.loader import CatalogLoader
from .protocol_mk300 import (
    PresetStruct,
    BLOCK_WAH, BLOCK_FX, BLOCK_GATE, BLOCK_DS, BLOCK_AMP,
    BLOCK_CAB, BLOCK_EQ, BLOCK_MOD, BLOCK_DLY, BLOCK_REV, BLOCK_VOL,
    KNOBS_PER_BLOCK,
)

logger = logging.getLogger(__name__)

# Mapeamento: EffectType → block_id da MK300
EFFECT_TYPE_TO_BLOCK = {
    EffectType.WAH: BLOCK_WAH,
    EffectType.COMPRESSOR: BLOCK_FX,
    EffectType.NOISE_GATE: BLOCK_GATE,
    EffectType.DRIVE: BLOCK_DS,
    EffectType.AMP: BLOCK_AMP,
    EffectType.CABINET: BLOCK_CAB,
    EffectType.EQ: BLOCK_EQ,
    EffectType.MODULATION: BLOCK_MOD,
    EffectType.DELAY: BLOCK_DLY,
    EffectType.REVERB: BLOCK_REV,
    EffectType.VOLUME: BLOCK_VOL,
}

# Ordem de knobs por bloco (DS e AMP têm mesma estrutura)
# Mapeamento: param_name → knob_index no bloco
DS_AMP_KNOB_MAP = {
    "gain": 0, "level": 1, "bass": 2, "middle": 3,
    "treble": 4, "reso": 5, "pres": 6, "bright": 7,
    # Aliases também aceitos
    "volume": 1, "presence": 6,
}

GATE_KNOB_MAP = {"threshold": 0, "decay": 1}

DLY_KNOB_MAP = {"time": 0, "feedback": 1, "mix": 2}

REV_KNOB_MAP = {"decay": 0, "mix": 1, "pre_delay": 2, "pre delay": 2}

MOD_KNOB_MAP = {"rate": 0, "depth": 1, "mix": 2, "speed": 0}

CAB_KNOB_MAP = {"level": 0, "low_cut": 1, "high_cut": 2, "low cut": 1, "high cut": 2}

FX_KNOB_MAP = {"threshold": 0, "ratio": 1, "attack": 2, "release": 3, "level": 4}

BLOCK_KNOB_MAPS = {
    BLOCK_GATE: GATE_KNOB_MAP,
    BLOCK_DS: DS_AMP_KNOB_MAP,
    BLOCK_AMP: DS_AMP_KNOB_MAP,
    BLOCK_CAB: CAB_KNOB_MAP,
    BLOCK_MOD: MOD_KNOB_MAP,
    BLOCK_DLY: DLY_KNOB_MAP,
    BLOCK_REV: REV_KNOB_MAP,
    BLOCK_FX: FX_KNOB_MAP,
}


def preset_to_struct(preset: Preset, bpm: Optional[int] = None) -> PresetStruct:
    """
    Converte um Preset (modelo abstrato) em PresetStruct (formato MK300).

    Raises:
        ValueError: se preset contiver efeito incompatível com MK300
    """
    if preset.device_model != DeviceModel.MK300:
        raise ValueError("Perfil de struct disponível somente para MK300")
    directory = Path(os.environ.get("CATALOGS_DIR", str(Path(__file__).resolve().parents[3] / "catalogs")))
    device_catalog = CatalogLoader(directory)._catalogs[DeviceModel.MK300]
    ps = PresetStruct(
        name=preset.name[:19],
        vol=80,
        bpm=int(bpm or preset.bpm or 120),
    )

    # Começa com todos os blocos desativados
    for i in range(11):
        ps.block_enabled[i] = False

    for block in preset.effect_chain.blocks:
        block_id = EFFECT_TYPE_TO_BLOCK.get(block.effect_type)
        if block_id is None:
            logger.warning(f"EffectType '{block.effect_type}' sem mapeamento para MK300, ignorando")
            continue

        # Configura on/off
        ps.block_enabled[block_id] = block.enabled

        # Configura model_id
        ps.block_model[block_id] = int(block.model_id) if str(block.model_id).isdigit() else 0

        # Configura knobs
        catalog_block = next(b for b in device_catalog["blocks"].values() if b["block_id"] == block_id)
        model = next((m for m in catalog_block["models"] if str(m["id"]) == block.model_id and m["name"] == block.model_name), None)
        if model is None:
            raise ValueError("Modelo/ID não corresponde ao catálogo MK300")
        knob_map = {name.lower().replace("-", "_"): i for i, name in enumerate(model.get("knobs", []))}
        knobs = ps.block_knobs[block_id][:]

        for param in block.parameters:
            param_key = param.name.lower().replace("-", "_")
            knob_idx = knob_map.get(param_key)
            if knob_idx is not None and knob_idx < KNOBS_PER_BLOCK:
                knobs[knob_idx] = int(param.raw_value)
            else:
                logger.debug(f"Parâmetro '{param.name}' sem mapeamento em bloco {block_id}")

        ps.block_knobs[block_id] = knobs

    return ps


def struct_to_preset_dict(ps: PresetStruct) -> dict:
    """Converte PresetStruct em dicionário legível para debug."""
    return {
        "name": ps.name,
        "vol": ps.vol,
        "bpm": ps.bpm,
        "chain_order": ps.chain_order,
        "blocks": {
            block_id: {
                "enabled": ps.block_enabled[block_id],
                "model": ps.block_model[block_id],
                "knobs": ps.block_knobs[block_id],
            }
            for block_id in range(11)
        },
    }
