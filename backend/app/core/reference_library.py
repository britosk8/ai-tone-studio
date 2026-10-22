"""Referências de guitarra persistidas: função e intervalo, sem reconhecer solo por título."""

import hashlib
import json
from pathlib import Path
import numpy as np
import soundfile as sf
import librosa
from .storage import load_record, save_record, list_records, data_directory
from ..services.audio_analysis.tone_comparison import fingerprint

ROLES = {"rhythm", "lead"}


def saved_source(pair_id, role):
    if role not in ROLES:
        raise ValueError("Função inválida")
    pair = load_record("pair", pair_id)
    if pair is None:
        raise ValueError("Análise não encontrada no backend")
    diagnostics = pair.get("analysis", {}).get("engine_diagnostics", {})
    details = diagnostics
    if role == "lead" and not diagnostics.get("lead", {}).get("same_region"):
        details = diagnostics.get("lead", {})
    cache = (details.get("separation") or {}).get("cache_id", "")
    if len(cache) != 64 or any(c not in "0123456789abcdef" for c in cache):
        raise ValueError("Esta análise ainda não tem guitarra separada salva")
    directory = data_directory() / "separations" / cache
    manifest = json.loads((directory / "manifest.json").read_text())
    guitar = directory / "guitar.wav"
    if (
        hashlib.sha256(guitar.read_bytes()).hexdigest()
        != manifest["stem_sha256"]["guitar"]
    ):
        raise ValueError("Integridade da guitarra separada não confirmada")
    region = details.get("region", {})
    start = float(region.get("start_seconds", 0))
    duration = sf.info(guitar).duration
    return {
        "cache_id": cache,
        "cache_start_seconds": start,
        "available_duration": duration,
        "original_sha256": diagnostics.get("original_sha256"),
        "guitar_path": guitar,
        "source_file_name": pair["pair"]["rhythm_preset"].get("source_file_name"),
        "title": pair["pair"]["rhythm_preset"].get("song_title") or "Música salva",
    }


def reference_info(pair_id, role):
    source = saved_source(pair_id, role)
    selection = load_record("comparison_reference", json.dumps([pair_id, role])) or {}
    # Uma região de outra referência nunca redefine o cache desta música implicitamente.
    if selection.get("cache_id") != source["cache_id"]:
        selection = {}
    registered = (
        load_record("song_reference", json.dumps([source["original_sha256"], role]))
        if source["original_sha256"]
        else None
    )
    if not selection and registered:
        start = registered["start_seconds"]
        duration = registered["duration_seconds"]
        if (
            source["cache_start_seconds"] <= start
            and start + duration
            <= source["cache_start_seconds"] + source["available_duration"] + 0.01
        ):
            selection = registered
    start = selection.get("start_seconds", source["cache_start_seconds"])
    duration = selection.get("duration_seconds", source["available_duration"])
    return {
        k: v
        for k, v in {
            **source,
            "pair_id": pair_id,
            "role": role,
            "start_seconds": start,
            "duration_seconds": duration,
            "needs_region": duration > 120,
            "selection_saved": bool(selection),
        }.items()
        if k != "guitar_path"
    }


def select_region(pair_id, role, start, duration, *, register=True):
    import math

    source = saved_source(pair_id, role)
    if (
        not math.isfinite(start)
        or not math.isfinite(duration)
        or not 3 <= duration <= 120
    ):
        raise ValueError("Selecione de 3 a 120 segundos de guitarra")
    relative = start - source["cache_start_seconds"]
    if relative < 0 or relative + duration > source["available_duration"] + 0.01:
        raise ValueError(
            "Trecho fora da guitarra salva. Escolha um intervalo disponível."
        )
    with sf.SoundFile(source["guitar_path"]) as audio:
        sr = audio.samplerate
        audio.seek(round(relative * sr))
        samples = audio.read(round(duration * sr), dtype="float32", always_2d=True)
    channel = int(np.argmax(np.mean(samples.astype(float) ** 2, axis=0)))
    mono = samples[:, channel]
    profile = fingerprint(librosa.resample(mono, orig_sr=sr, target_sr=22050), 22050)
    profile["source_kind"] = "separated_guitar"
    record = {
        "profile": profile,
        "cache_id": source["cache_id"],
        "start_seconds": start,
        "duration_seconds": duration,
        "original_sha256": source["original_sha256"],
        "binding_method": "saved_guitar_role_region",
        "channel": channel,
    }
    save_record("comparison_reference", json.dumps([pair_id, role]), record)
    if register and source["original_sha256"]:
        save_record(
            "song_reference", json.dumps([source["original_sha256"], role]), record
        )
    return reference_info(pair_id, role)


def library():
    records = sorted(
        list_records("pair", 1000),
        key=lambda p: p.get("pair", {}).get("generation_timestamp", ""),
        reverse=True,
    )
    songs = {}
    coverage = {}
    for record in records:
        pair = record.get("pair", {})
        pair_id = pair.get("rhythm_preset", {}).get("id")
        sha = (
            record.get("analysis", {})
            .get("engine_diagnostics", {})
            .get("original_sha256")
        )
        if not sha:
            continue
        try:
            roles = {role: reference_info(pair_id, role) for role in ["rhythm", "lead"]}
        except (ValueError, OSError, KeyError):
            continue
        span = sum(info["available_duration"] for info in roles.values())
        if sha not in songs or span > coverage[sha]:
            songs[sha] = {
                "pair_id": pair_id,
                "title": roles["rhythm"]["title"],
                "roles": roles,
            }
            coverage[sha] = span
    return list(songs.values())
