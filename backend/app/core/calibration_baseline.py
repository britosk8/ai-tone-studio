"""Known user-approved Infest reference, reconstructed from its verified read.

This is an explicit calibration capture, never a template for song generation.
Missing or modified evidence fails closed instead of inventing pedal settings.
"""

import uuid
from .storage import load_record
from ..api.mk20_diagnostics import validate_report, decode64, decode_image
from ..transport.protocol_mk20 import controls, BLOCKS
from ..models.preset import Preset, EffectBlock, PresetEffectChain
from ..models.devices import DeviceModel, EffectType, PresetRole
from ..models.audio import ConfidenceLevel
from ..services.device_catalog.loader import CatalogLoader
from ..services.preset_generation.compiler import PresetCompiler

DIAGNOSTIC_ID = "6cab272d890dddc769b496e7d9a60f928f69774b0f4bfbe8bc2b0c8ed29b7029"
IMAGE_SHA = "a4624316bb2231650664f1c319b9a24f80c87ec0babf47e7eb15a707afa1f24a"


def approved_infest(pair_id):
    parent = load_record("pair", pair_id)
    if not parent:
        raise ValueError("Análise não encontrada")
    original = parent["pair"]["rhythm_preset"]
    if str(original.get("song_title", "")).strip().casefold() != "infest":
        raise ValueError("Esta referência aprovada pertence somente a Infest")
    evidence = load_record("mk20_diagnostic", DIAGNOSTIC_ID)
    if not evidence:
        raise ValueError(
            "A leitura do preset aprovado ainda não está disponível neste backend"
        )
    summary = validate_report(evidence["report"])
    if summary["status"] != "read_layout_confirmed" or summary["slot"] != 76:
        raise ValueError("Leitura do preset aprovado não confirmada")
    read = next(r for r in evidence["report"]["reads"] if r["space"] == 0)
    image = decode64(read["decoded"]["image_base64"], 412)
    decoded = decode_image(image)
    if decoded["image_sha256"] != IMAGE_SHA or decoded["name"] != "PAPA INFEST":
        raise ValueError(
            "A leitura difere da referência aprovada; confira antes de calibrar"
        )
    loader = CatalogLoader()
    compiler = PresetCompiler(loader)
    cat = loader._catalogs[DeviceModel.MK20]
    reverse = {v: k for k, v in BLOCKS.items()}
    blocks = []
    mapped = {b["block_id"]: b for b in controls(image)}
    for index in decoded["chain_raw"]:
        b = mapped.get(index)
        if not b or not b["enabled"]:
            continue
        model = next(
            m for m in cat["blocks"][b["block"]]["models"] if m["id"] == b["model_id"]
        )
        blocks.append(
            EffectBlock(
                slot=len(blocks),
                effect_type=EffectType(reverse[b["block"]]),
                model_id=str(b["model_id"]),
                model_name=b["model_name"],
                enabled=True,
                parameters=compiler._build_parameters(
                    {**model, "parameters": model["params"]}, b["parameters"]
                ),
                generated_confidence=ConfidenceLevel.LOW,
                generation_rationale="Valores lidos do preset aprovado para calibração; não é uma nova geração pela música.",
            )
        )
    return Preset(
        id=uuid.uuid5(uuid.NAMESPACE_URL, "approved-mk20:" + IMAGE_SHA),
        name="PAPA INFEST - referencia",
        role=PresetRole.RHYTHM,
        device_model=DeviceModel.MK20,
        catalog_version=loader.get_catalog_version(DeviceModel.MK20),
        artist=original.get("artist"),
        song_title=original.get("song_title"),
        source_file_name=original.get("source_file_name"),
        bpm=decoded["bpm_raw"],
        preset_volume=decoded["volume_raw"],
        effect_chain=PresetEffectChain(blocks=blocks),
        overall_confidence=ConfidenceLevel.LOW,
        generation_metadata={
            "generator": "guitar-v3-calibration-baseline",
            "calibration_baseline": True,
            "source_pair_id": pair_id,
            "source_diagnostic_id": DIAGNOSTIC_ID,
            "source_image_sha256": IMAGE_SHA,
            "source_slot": 76,
            "guitar_profile": "konig_strat_sss",
        },
    )
