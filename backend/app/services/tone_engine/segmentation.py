"""Estados recorrentes de timbre; não identifica guitarristas nem equipamento."""

import hashlib
import json
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.ndimage import median_filter
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score
from .features import GuitarToneFeatureExtractor
from ...core.storage import load_record, save_record

VERSION = "tone-states-v1.1"
LABELS = {
    "clean": "Limpo provável",
    "crunch": "Crunch provável",
    "distorted": "Distorcido provável",
}


def character_for(score):
    return "clean" if score < 0.35 else "crunch" if score < 0.55 else "distorted"


def cluster_windows(windows):
    """Agrupa por espectro/dinâmica; volume absoluto não determina o estado."""
    if not windows:
        return []
    raw = np.array([w["vector"] for w in windows], dtype=float)
    scale = np.std(raw, axis=0)
    x = (raw - np.mean(raw, axis=0)) / np.maximum(scale, 0.08)
    best = np.zeros(len(windows), dtype=int)
    best_score = 0.30
    if len(windows) >= 8 and np.max(np.std(raw, axis=0)) > 0.03:
        for k in range(2, min(4, len(windows) // 4) + 1):
            labels = KMeans(n_clusters=k, n_init=10, random_state=0).fit_predict(x)
            if len(np.unique(labels)) < k or min(np.bincount(labels)) < 3:
                continue
            score = float(silhouette_score(x, labels)) - 0.035 * (k - 2)
            if score > best_score:
                best, best_score = labels, score
    # Suaviza somente vizinhos temporalmente contíguos, nunca atravessa silêncio.
    for begin in range(len(windows)):
        if begin and windows[begin]["start"] - windows[begin - 1]["start"] <= 3.1:
            continue
        end = begin + 1
        while (
            end < len(windows)
            and windows[end]["start"] - windows[end - 1]["start"] <= 3.1
        ):
            end += 1
        if end - begin >= 5:
            best[begin:end] = median_filter(best[begin:end], size=3, mode="nearest")
    groups = []
    for label in sorted(set(best)):
        indexes = np.flatnonzero(best == label)
        chosen = [windows[i] for i in indexes]
        score = float(np.median([w["distortion"] for w in chosen]))
        runs = []
        for window in chosen:
            if runs and window["start"] <= runs[-1]["end"] + 0.01:
                runs[-1]["end"] = max(runs[-1]["end"], window["end"])
            else:
                runs.append({"start": window["start"], "end": window["end"]})
        # O centroide escolhe uma janela real, não uma média que nunca existiu na música.
        center = np.mean(x[indexes], axis=0)
        representative = int(
            indexes[np.argmin(np.linalg.norm(x[indexes] - center, axis=1))]
        )
        window = windows[representative]
        run = next(
            r
            for r in runs
            if r["start"] <= window["start"] and r["end"] >= window["end"] - 0.01
        )
        length = min(12.0, run["end"] - run["start"])
        reference_start = max(
            run["start"], min(window["start"] - 3, run["end"] - length)
        )
        groups.append(
            {
                "character": character_for(score),
                "distortion_score": score,
                "intervals": [
                    {
                        "start_seconds": r["start"],
                        "duration_seconds": r["end"] - r["start"],
                    }
                    for r in runs
                ],
                "representative": {
                    "start_seconds": reference_start,
                    "duration_seconds": length,
                },
                "windows": len(chosen),
                "features": window["features"],
                "clustering_separation": None if len(set(best)) == 1 else best_score,
                "confidence": "low",
                "role": "unassigned",
                "classification_ambiguous": min(abs(score - 0.35), abs(score - 0.55))
                < 0.06,
            }
        )
    return sorted(groups, key=lambda g: g["distortion_score"])


class ToneStateAnalyzer:
    def analyze(self, path: Path, *, cache_id: str, absolute_start=0):
        identity = {
            "version": VERSION,
            "cache_id": cache_id,
            "start": absolute_start,
            "window": 6,
            "hop": 3,
        }
        key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
        existing = load_record("tone_states", key)
        if existing:
            return existing
        info = sf.info(path)
        extractor = GuitarToneFeatureExtractor()
        channels = [0] if info.channels == 1 else [0, 1]
        states = []
        silence = 0
        for channel in channels:
            windows = []
            for start in np.arange(0, max(info.duration - 2.99, 0), 3):
                duration = min(6, info.duration - float(start))
                if duration < 3:
                    continue
                # Teste de sinal no canal antes de extrair features caras.
                with sf.SoundFile(path) as audio:
                    audio.seek(round(start * info.samplerate))
                    raw = audio.read(round(duration * info.samplerate), always_2d=True)
                if float(np.sqrt(np.mean(raw[:, channel] ** 2))) < 0.001:
                    silence += 1
                    continue
                f = extractor.extract(
                    path, start=float(start), duration=duration, channel=channel
                )
                bands = list(f["bands_db"].values())
                vector = [
                    *[(v + 30) / 30 for v in bands[:7]],
                    f["distortion_score"],
                    f["crest_db"] / 20,
                    *[v / 100 for v in f["mfcc"][1:7]],
                ]
                windows.append(
                    {
                        "start": absolute_start + float(start),
                        "end": absolute_start + float(start) + duration,
                        "vector": vector,
                        "distortion": f["distortion_score"],
                        "features": f,
                    }
                )
            groups = cluster_windows(windows)
            for index, state in enumerate(groups):
                state.update(
                    id=f"{key[:12]}-ch{channel}-{index}",
                    channel=channel,
                    label=f"{LABELS[state['character']]} — {'L' if channel==0 else 'R'} {index+1}",
                    confirmed=False,
                )
                states.append(state)
        # Estéreo idêntico não gera duas listas de presets redundantes.
        if info.channels == 2:
            parts = []
            with sf.SoundFile(path) as audio:
                for position in [
                    0,
                    max(0, info.duration / 2 - 5),
                    max(0, info.duration - 10),
                ]:
                    audio.seek(round(position * info.samplerate))
                    parts.append(
                        audio.read(
                            min(info.frames - audio.tell(), info.samplerate * 10),
                            always_2d=True,
                        )
                    )
            sample = np.concatenate(parts, axis=0)
            difference = np.sqrt(np.mean((sample[:, 0] - sample[:, 1]) ** 2))
            level = max(float(np.sqrt(np.mean(sample**2))), 1e-9)
            if difference / level < 0.02:
                states = [s for s in states if s["channel"] == 0]
        result = {
            "id": key,
            "version": VERSION,
            "source_cache_id": cache_id,
            "states": states,
            "ignored_silent_windows": silence,
            "limitations": [
                "Estados e rótulos são hipóteses de DSP, sem classificador treinado de distorção.",
                "L/R são canais; não equivalem necessariamente a base e solo.",
                "Mudanças de notas, execução, vazamentos e efeitos podem formar grupos diferentes.",
                "A classificação limpo/crunch/distorcido não comprova os controles originais.",
            ],
        }
        save_record("tone_states", key, result)
        return result
