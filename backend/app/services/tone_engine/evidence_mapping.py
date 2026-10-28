"""Mapeamento de estados e priors documentais em modelos existentes do catálogo."""

import re
from ...models.devices import EffectType
from ...models.audio import GainCharacter, ConfidenceLevel
from .validation import models_for, validate_preset

FAMILY_PATTERNS = {
    "412": r"4[x ]?12|412",
    "mesa": r"mes|rect|mbos",
    "fender": r"fd|fend|fendi|twin|delux",
    "marshall": r"j900|j800|jvm|mar|jcm",
    "vox": r"ac30|vac|vox",
    "roland": r"j120|jc120|rj120",
}


def choose_model(catalog, device, kind, character, research):
    models = models_for(catalog, device, kind)
    if not models:
        raise ValueError(f"NEEDS_DEVICE_DATA: {device.value}/{kind.value}")
    type_weights = {
        "clean": {"clean": 1.0},
        "crunch": {"crunch": 1.0, "overdrive": 0.9},
        "distorted": {"high_gain": 1.0, "lead": 0.95, "overdrive": 0.8, "crunch": 0.7},
    }[character]
    scored = []
    for model in models:
        score = 0.0
        reasons = []
        if kind == EffectType.AMP:
            score = type_weights.get(model.get("type", model.get("character", "")), 0)
            if score == 0:
                continue
        else:
            size = str(model.get("config", "")) + " " + model["name"]
            score = 0.5 + (
                0.15
                if ("412" in size or "4x12" in size) and character != "clean"
                else 0
            )
        for hint in research.get("hints", []):
            pattern = FAMILY_PATTERNS.get(hint["family"])
            if (
                hint["block"] == kind.value
                and float(hint.get("weight", 0)) > 0
                and pattern
                and re.search(
                    pattern,
                    model["name"]
                    + " "
                    + model.get("based_on", "")
                    + " "
                    + model.get("config", ""),
                    re.I,
                )
            ):
                score += min(float(hint["weight"]), 0.5) * (
                    3 if kind == EffectType.AMP else 1
                )
                reasons.append(
                    {
                        "source_url": hint["url"],
                        "scope": hint["scope"],
                        "family": hint["family"],
                        "exact_equivalence": False,
                    }
                )
        scored.append((score, model, reasons))
    if not scored:
        raise ValueError(f"NEEDS_DEVICE_DATA: família {character} de {kind.value}")
    scored.sort(key=lambda item: (-item[0], str(item[1]["id"])))
    return scored[0][1], scored[0][2], [m["name"] for _, m, _ in scored[:5]]


def apply_state_mapping(compiler, preset, analysis, character, research):
    """O estado governa saturação; fatos sobre artista são apenas priors fracos."""
    notes = {}
    selected = {}
    for kind in [EffectType.AMP, EffectType.CABINET]:
        model, evidence, alternatives = choose_model(
            compiler.catalog, preset.device_model, kind, character, research
        )
        block = next(b for b in preset.effect_chain.blocks if b.effect_type == kind)
        block.model_id = str(model["id"])
        block.model_name = model["name"]
        selected[kind] = model
        notes[kind.value] = {
            "model": model["name"],
            "evidence": evidence,
            "alternatives": alternatives,
            "basis": "compatibilidade de estado + família documental; sem resposta acústica calibrada",
        }
    from .engine import GuitarToneEngine

    GuitarToneEngine(compiler).refine(preset, analysis)
    amp = next(b for b in preset.effect_chain.blocks if b.effect_type == EffectType.AMP)
    values = {p.name: p.raw_value for p in amp.parameters}
    values["Gain"] = {"clean": 15, "crunch": 38, "distorted": 65}[character]
    # Reutiliza limites e passos reais já presentes; nenhuma frequência física é inventada.
    amp.parameters = compiler._build_parameters(selected[EffectType.AMP], values)
    amp.generation_rationale = f"Estado {character}: ganho inicial por regra; o modelo não identifica o amplificador original."
    for block in preset.effect_chain.blocks:
        if block.effect_type == EffectType.DRIVE:
            block.enabled = False
            block.generation_rationale = "Distorção obtida inicialmente pelo AMP; DS desligado não significa som limpo."
    preset.generation_metadata["tone_character"] = character
    preset.generation_metadata["model_selection"] = notes
    preset.generation_metadata["research_id"] = research.get("id")
    preset.generation_metadata["research_scope"] = (
        "documentary_prior_not_original_rig_identification"
    )
    preset.overall_confidence = ConfidenceLevel.LOW
    validate_preset(compiler.catalog, preset)
    return preset
