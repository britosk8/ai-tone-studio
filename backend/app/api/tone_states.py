"""Estados de timbre, pesquisa e variantes compatíveis com o fluxo de pares existente."""

import asyncio
import hashlib
import json
import tempfile
import uuid
from pathlib import Path
from typing import Literal
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from ..core.storage import load_record, save_record, data_directory
from ..core.reference_library import saved_source, reference_info
from ..models.preset import PresetPair
from ..models.devices import DeviceModel
from ..services.tone_engine.segmentation import ToneStateAnalyzer
from ..services.song_research.research import SongResearch
from ..services.tone_engine.engine import GuitarToneEngine
from ..services.tone_engine.evidence_mapping import apply_state_mapping
from ..core.pipeline import ToneAnalysisPipeline

router = APIRouter(prefix="/api/v1")


class AnalyzeStates(BaseModel):
    version: Literal["unknown", "studio", "live", "acoustic"] = "unknown"
    refresh_research: bool = False
    artist: str | None = Field(None, max_length=120)
    song_title: str | None = Field(None, max_length=180)


class GenerateState(BaseModel):
    role: Literal["rhythm", "lead"]
    device: DeviceModel = DeviceModel.MK300
    character: Literal["clean", "crunch", "distorted"] | None = None
    research_id: str | None = None
    research_revision: str | None = None


def analyze_states(
    pair_id, version="unknown", refresh=False, artist=None, song_title=None
):
    parent = load_record("pair", pair_id)
    if not parent:
        raise ValueError("Análise não encontrada")
    primary = parent["pair"]["rhythm_preset"]
    maps = []
    seen = set()
    for role in ["rhythm", "lead"]:
        source = saved_source(pair_id, role)
        identity = (source["cache_id"], source["cache_start_seconds"])
        if identity in seen:
            continue
        seen.add(identity)
        result = ToneStateAnalyzer().analyze(
            source["guitar_path"],
            cache_id=source["cache_id"],
            absolute_start=source["cache_start_seconds"],
        )
        maps.append({**result, "source_role": role})
    research = SongResearch().research(
        artist or primary.get("artist"),
        song_title or primary.get("song_title"),
        version,
        refresh,
    )
    result = {
        "pair_id": pair_id,
        "maps": maps,
        "research": research,
        "note": "Confirme os estados propostos. Canal L/R e estado sonoro não identificam base/solo automaticamente.",
    }
    save_record("pair_tone_states", pair_id, result)
    return result


@router.post("/presets/{pair_id}/tone-states/analyze")
async def detect_states(pair_id: str, body: AnalyzeStates):
    try:
        return await asyncio.to_thread(
            analyze_states,
            pair_id,
            body.version,
            body.refresh_research,
            body.artist,
            body.song_title,
        )
    except (ValueError, OSError, KeyError) as exc:
        raise HTTPException(400, str(exc)) from exc


@router.get("/presets/{pair_id}/tone-states")
async def states(pair_id: str):
    result = load_record("pair_tone_states", pair_id)
    if not result:
        raise HTTPException(
            404, "Estados ainda não analisados. A guitarra salva será reutilizada."
        )
    return result


def generate_variant(pair_id, state_id, body):
    if body.device == DeviceModel.UNKNOWN:
        raise ValueError("Dispositivo inválido")
    collection = load_record("pair_tone_states", pair_id)
    if not collection:
        raise ValueError("Analise os estados desta música primeiro")
    match = next(
        (
            (m, s)
            for m in collection["maps"]
            for s in m["states"]
            if s["id"] == state_id
        ),
        None,
    )
    if match is None:
        raise ValueError("Estado não pertence a esta música")
    state_map, state = match
    parent_record = load_record("pair", pair_id)
    parent = PresetPair.model_validate(parent_record["pair"])
    source = saved_source(pair_id, state_map["source_role"])
    if source["cache_id"] != state_map["source_cache_id"]:
        raise ValueError("Referência mudou; analise os estados novamente")
    research = collection["research"]
    if body.research_id and body.research_id != research.get("id"):
        raise ValueError("Pesquisa mudou; atualize os estados antes de gerar")
    if body.research_revision and body.research_revision != research.get("revision"):
        raise ValueError("As fontes mudaram; atualize a tela antes de gerar")
    character = body.character or state["character"]
    identity = {
        "version": "state-preset-v1",
        "parent_pair": pair_id,
        "cache": source["cache_id"],
        "state": state_id,
        "role": body.role,
        "device": body.device.value,
        "character": character,
        "research": research.get("id"),
        "research_revision": research.get("revision"),
    }
    unique = json.dumps(identity, sort_keys=True)
    variant_id = str(uuid.uuid5(uuid.NAMESPACE_URL, unique))
    existing = load_record("pair", variant_id)
    if existing:
        return {"pair_id": variant_id, "role": body.role, "reused": True}
    pipeline = ToneAnalysisPipeline()
    engine = GuitarToneEngine(pipeline.compiler)
    region = state["representative"]
    with tempfile.TemporaryDirectory(prefix="tone-state-") as directory:
        analysis = engine.analyze(
            Path("unused"),
            Path(directory),
            "mix",
            region["start_seconds"],
            region["duration_seconds"],
            lambda *args: None,
            source,
            preferred_channel=state["channel"],
        )
        # A classificação proposta pode ser corrigida pelo usuário sem editar knobs.
        from ..models.audio import GainCharacter

        analysis.effect_estimates.gain_character = {
            "clean": GainCharacter.CLEAN,
            "crunch": GainCharacter.CRUNCH,
            "distorted": GainCharacter.HIGH_GAIN,
        }[character]
        method = (
            pipeline.compiler._compile_rhythm_preset
            if body.role == "rhythm"
            else pipeline.compiler._compile_lead_preset
        )
        origin = parent.rhythm_preset
        preset = method(analysis, body.device, origin.artist, origin.song_title)
        apply_state_mapping(pipeline.compiler, preset, analysis, character, research)
    labels = {"clean": "Limpo", "crunch": "Crunch", "distorted": "Distorcido"}
    preset.id = uuid.uuid5(uuid.NAMESPACE_URL, unique + ":" + body.role)
    preset.name = f'{"Base" if body.role=="rhythm" else "Solo"} {labels[character]} - {origin.song_title or "Música"}'
    preset.source_file_name = origin.source_file_name
    preset.generation_metadata.update(
        generator="guitar-v3-state",
        source_pair_id=pair_id,
        state_id=state_id,
        state_channel=state["channel"],
        state_role=body.role,
        classification_overridden=body.character is not None
        and body.character != state["character"],
    )
    companion = (
        parent.lead_preset if body.role == "rhythm" else parent.rhythm_preset
    ).model_copy(deep=True)
    companion.id = uuid.uuid5(uuid.NAMESPACE_URL, unique + ":companion")
    pair = parent.model_copy(deep=True)
    if body.role == "rhythm":
        pair.rhythm_preset = preset
        pair.lead_preset = companion
    else:
        pair.rhythm_preset = companion
        pair.lead_preset = preset
    # O ID público dos pares é o ID da base. A outra parte permanece cópia do pai, sem fingir uma segunda geração.
    pair.rhythm_preset.id = uuid.UUID(variant_id)
    pair.analysis_summary = f"Variante {labels[character]} de {body.role}; outra parte preservada da análise de origem."
    diagnostics = json.loads(json.dumps(parent_record.get("analysis", {})))
    root = diagnostics.setdefault("engine_diagnostics", {})
    root.update(original_sha256=source["original_sha256"])
    if body.role == "rhythm":
        old_lead = root.get("lead", {})
        if old_lead.get("same_region"):
            old_lead = {k: v for k, v in root.items() if k != "lead"}
        root.update(analysis.engine_diagnostics)
        root["lead"] = old_lead
    else:
        root["lead"] = analysis.engine_diagnostics
    root["state_variant"] = {
        "state_id": state_id,
        "role": body.role,
        "character": character,
        "research_id": research.get("id"),
    }
    diagnostics.update(
        confidence="low",
        tone_reference=analysis.reference_profile,
        gain_character=analysis.effect_estimates.gain_character.value,
        distortion_level=analysis.effect_estimates.distortion_level,
        spectral_profile={
            "low": analysis.overall_spectral.bass_energy,
            "low_mid": analysis.overall_spectral.low_mid_energy,
            "mid": analysis.overall_spectral.mid_energy,
            "high_mid": analysis.overall_spectral.high_mid_energy,
            "high": analysis.overall_spectral.treble_energy,
            "brightness": analysis.overall_spectral.brightness,
        },
        effect_presence={
            "reverb_probability": analysis.effect_estimates.reverb_present,
            "delay_probability": analysis.effect_estimates.delay_present,
        },
    )
    save_record(
        "pair",
        variant_id,
        {"pair": pair.model_dump(mode="json"), "analysis": diagnostics},
    )
    for role in ["rhythm", "lead"]:
        original = load_record("comparison_reference", json.dumps([pair_id, role]))
        if role == body.role:
            save_record(
                "comparison_reference",
                json.dumps([variant_id, role]),
                {
                    "profile": analysis.reference_profile,
                    "start_seconds": region["start_seconds"],
                    "duration_seconds": region["duration_seconds"],
                    "cache_id": (
                        analysis.engine_diagnostics.get("separation") or {}
                    ).get("cache_id"),
                    "binding_method": "tone_state_variant",
                    "channel": state["channel"],
                },
            )
        elif original:
            save_record(
                "comparison_reference", json.dumps([variant_id, role]), original
            )
    return {"pair_id": variant_id, "role": body.role, "reused": False}


@router.post("/presets/{pair_id}/tone-states/{state_id}/generate")
async def generate(pair_id: str, state_id: str, body: GenerateState):
    try:
        return await asyncio.to_thread(generate_variant, pair_id, state_id, body)
    except (ValueError, OSError, KeyError) as exc:
        raise HTTPException(400, str(exc)) from exc
