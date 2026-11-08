"""Versioned listening evaluations linked to original captures; never trains or writes a pedal."""

import hashlib
import json
from datetime import datetime, timezone
from typing import Literal
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field, ConfigDict
from .recordings import get_record
from ..core.storage import save_record, list_records

router = APIRouter(prefix="/api/v1")


class Evaluation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    guitar: Literal["konig_strat_sss", "strinberg_les_paul_hh", "other", "unknown"] = (
        "unknown"
    )
    guitar_other: str = Field(default="", max_length=80)
    pickup: Literal[
        "bridge", "bridge_middle", "middle", "middle_neck", "neck", "both", "unknown"
    ] = "unknown"
    route: Literal["pedal_usb", "mq44_analog", "other", "unknown"] = "unknown"
    signal: Literal["processed", "dry", "unknown"] = "unknown"
    preset_applied: bool = False
    assessment: Literal["unrated", "close", "needs_adjustment", "worse", "approved"] = (
        "unrated"
    )
    notes: str = Field(default="", max_length=1000)


@router.post("/recordings/{recording_id}/evaluation")
async def evaluate(recording_id: str, body: Evaluation):
    recording = get_record(recording_id)
    if recording.get("status") != "completed":
        raise HTTPException(
            400, "Conclua a comparação desta gravação antes de registrar a avaliação"
        )
    if body.guitar == "strinberg_les_paul_hh" and body.pickup in {
        "bridge_middle",
        "middle",
        "middle_neck",
    }:
        raise HTTPException(400, "Seleção de captador incompatível com a guitarra HH")
    if body.guitar == "konig_strat_sss" and body.pickup == "both":
        raise HTTPException(400, "Use uma posição de captador da Stratocaster SSS")
    result = recording.get("analysis_result", {})
    context = body.model_dump()
    identity = json.dumps(
        [recording_id, context, result], sort_keys=True, allow_nan=False
    )
    key = hashlib.sha256(identity.encode()).hexdigest()
    reasons = []
    if result.get("quality") == "clipped":
        reasons.append("clipped_recording")
    if result.get("reference_source") != "saved_excerpt_profile":
        reasons.append("reference_not_same_saved_excerpt")
    if not body.preset_applied:
        reasons.append("preset_not_confirmed_by_player")
    if body.signal != "processed":
        reasons.append("processed_signal_not_confirmed")
    if body.guitar == "unknown" or body.pickup == "unknown" or body.route == "unknown":
        reasons.append("incomplete_context")
    if body.assessment == "unrated":
        reasons.append("not_listened_by_player")
    record = {
        "id": key,
        "version": "calibration-test-v1",
        "recording_id": recording_id,
        "pair_id": recording["pair_id"],
        "role": recording["role"],
        "created_at": datetime.now(timezone.utc).isoformat(),
        "recording_sha256": recording["sha256"],
        "submitted_preset": recording["submitted_preset"],
        "reference_profile": recording.get("reference_profile"),
        "reference_context": result.get("reference_context"),
        "comparison_result": result,
        "context": context,
        "eligible_for_review": not reasons,
        "review_flags": reasons,
        "note": "Avaliação declarada pelo músico; não comprova precisão acústica nem treina automaticamente o motor.",
    }
    from ..core.storage import load_record

    previous = load_record("calibration_test", key)
    if previous:
        return previous
    save_record("calibration_test", key, record)
    return record


@router.get("/calibration-tests")
async def evaluations(
    pair_id: str | None = None,
    role: Literal["rhythm", "lead"] | None = None,
    limit: int = Query(50, ge=1, le=100),
):
    from ..core.storage import _connect

    # Filter before LIMIT so other songs do not hide this song's sessions.
    clauses = ["kind=?"]
    args = ["calibration_test"]
    for field, value in [("pair_id", pair_id), ("role", role)]:
        if value is not None:
            clauses.append(f"json_extract(data,'$.{field}')=?")
            args.append(value)
    args.append(limit)
    with _connect() as connection:
        rows = connection.execute(
            "SELECT data FROM records WHERE "
            + " AND ".join(clauses)
            + " ORDER BY json_extract(data,'$.created_at') DESC LIMIT ?",
            args,
        ).fetchall()
    return {"tests": [json.loads(row[0]) for row in rows]}


@router.post("/presets/{pair_id}/calibration-baseline")
async def baseline(pair_id: str):
    from ..core.calibration_baseline import approved_infest
    from .routes import _serialize_preset

    try:
        return {
            "preset": _serialize_preset(approved_infest(pair_id)),
            "instructions": "Selecione PAPA INFEST, slot 76, na MK20. Use a Konig Stratocaster e grave a saída processada. Este modo apenas registra a referência aprovada; não envia nem altera o preset.",
        }
    except (ValueError, KeyError, OSError, StopIteration) as exc:
        raise HTTPException(400, str(exc)) from exc
