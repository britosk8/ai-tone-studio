"""Biblioteca e geração a partir de instrumentos existentes, sem novo upload."""

import asyncio
import hashlib
import json
import uuid
from typing import Optional
from fastapi import APIRouter, HTTPException, BackgroundTasks
from pydantic import BaseModel, Field
from ..core.storage import data_directory, load_record, save_record
from ..core.reference_library import (
    library,
    reference_info,
    select_region,
    saved_source,
)
from ..models.devices import DeviceModel

router = APIRouter(prefix="/api/v1")


class Region(BaseModel):
    start_seconds: float = Field(ge=0, le=7200)
    duration_seconds: float = Field(ge=3, le=120)


class SavedAnalysis(BaseModel):
    pair_id: str
    rhythm_device: DeviceModel = DeviceModel.MK300
    lead_device: DeviceModel = DeviceModel.MK300
    rhythm_region: Optional[Region] = None
    lead_region: Optional[Region] = None


@router.get("/reference-library")
async def references():
    return {"songs": await asyncio.to_thread(library)}


@router.get("/presets/{pair_id}/reference/{role}")
async def reference(pair_id: str, role: str):
    try:
        return await asyncio.to_thread(reference_info, pair_id, role)
    except (ValueError, OSError, KeyError) as exc:
        raise HTTPException(404, str(exc)) from exc


@router.put("/presets/{pair_id}/reference/{role}")
async def update_reference(pair_id: str, role: str, region: Region):
    try:
        return await asyncio.to_thread(
            select_region, pair_id, role, region.start_seconds, region.duration_seconds
        )
    except (ValueError, OSError, KeyError) as exc:
        raise HTTPException(400, str(exc)) from exc


@router.post("/analyze-saved")
async def analyze_saved(body: SavedAnalysis, background_tasks: BackgroundTasks):
    from .routes import _jobs, _run_analysis_job

    if DeviceModel.UNKNOWN in {body.rhythm_device, body.lead_device}:
        raise HTTPException(400, "Dispositivo inválido")
    try:
        sources = {r: saved_source(body.pair_id, r) for r in ["rhythm", "lead"]}
        infos = {r: reference_info(body.pair_id, r) for r in sources}
        regions = {}
        for role, requested in [
            ("rhythm", body.rhythm_region),
            ("lead", body.lead_region),
        ]:
            chosen = (
                requested.model_dump()
                if requested
                else {k: infos[role][k] for k in ["start_seconds", "duration_seconds"]}
            )
            start, duration = chosen["start_seconds"], chosen["duration_seconds"]
            if duration > 120:
                raise ValueError(
                    "Escolha uma vez o trecho de base e solo na guitarra já separada."
                )
            source = sources[role]
            if (
                start < source["cache_start_seconds"]
                or start + duration
                > source["cache_start_seconds"] + source["available_duration"] + 0.01
            ):
                raise ValueError("Trecho fora da referência disponível")
            regions[role] = chosen
        sha = sources["rhythm"]["original_sha256"]
        if not sha or len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha):
            raise ValueError("Original não preservado nesta análise")
        paths = list((data_directory() / "generation_inputs").glob(sha + ".*"))
        path = next(
            (
                p
                for p in paths
                if p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest() == sha
            ),
            None,
        )
        if path is None:
            raise ValueError(
                "Original preservado não disponível; seus instrumentos continuam salvos."
            )
    except (ValueError, OSError, KeyError) as exc:
        raise HTTPException(400, str(exc)) from exc
    identity = {
        "version": "saved-guitar-v1",
        "sha": sha,
        "devices": [body.rhythm_device.value, body.lead_device.value],
        "regions": regions,
        "caches": {r: s["cache_id"] for r, s in sources.items()},
    }
    key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    previous = load_record("saved_generation", key)
    if previous:
        job = _jobs.get(previous["job_id"]) or load_record("job", previous["job_id"])
        if job and (
            job["status"] == "completed"
            or previous["job_id"] in _jobs
            and job["status"] in {"queued", "processing"}
        ):
            return {
                "job_id": previous["job_id"],
                "status": job["status"],
                "reused": True,
            }
    job_id = str(uuid.uuid4())
    _jobs[job_id] = {
        "job_id": job_id,
        "status": "queued",
        "progress_percent": 0,
        "progress": "Reutilizando instrumentos salvos...",
    }
    save_record("job", job_id, _jobs[job_id])
    save_record("saved_generation", key, {"job_id": job_id})
    parent = load_record("pair", body.pair_id)["pair"]["rhythm_preset"]
    background_tasks.add_task(
        _run_analysis_job,
        job_id,
        path.read_bytes(),
        path.suffix,
        body.rhythm_device,
        body.lead_device,
        parent.get("artist"),
        parent.get("song_title"),
        parent.get("source_file_name"),
        "mix",
        regions["rhythm"]["start_seconds"],
        regions["rhythm"]["duration_seconds"],
        "guitar_v2",
        regions["lead"]["start_seconds"],
        regions["lead"]["duration_seconds"],
        sources,
    )
    return {"job_id": job_id, "status": "queued", "reused": False}
