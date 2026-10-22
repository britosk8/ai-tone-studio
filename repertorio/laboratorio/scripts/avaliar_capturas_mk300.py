"""Inventário reproduzível das capturas R1; não gera presets nem mede fidelidade.

Executar com backend/.venv/bin/python. FFmpeg decodifica em float32, sem
normalização, alteração de canais ou da taxa. Saída nova obrigatória.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
CAPTURES = ROOT / "repertorio/fase_1/01/gravacoes_pedal"


def db(value):
    return float(20 * np.log10(value)) if value > 0 else None


def inspect(path):
    metadata = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "a:0",
        "-show_entries", "stream=codec_name,sample_rate,channels", "-of", "json", str(path)
    ]))["streams"][0]
    channels = int(metadata["channels"])
    rate = int(metadata["sample_rate"])
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0",
        "-f", "f32le", "-acodec", "pcm_f32le", "-"
    ])
    samples = np.frombuffer(raw, dtype="<f4").reshape(-1, channels).astype(np.float64)
    if not len(samples) or not np.isfinite(samples).all():
        raise ValueError(f"Áudio vazio ou não finito: {path.name}")
    metrics = []
    for index in range(channels):
        signal = samples[:, index]
        peak = float(np.max(np.abs(signal)))
        rms = float(np.sqrt(np.mean(signal ** 2)))
        window = max(1, round(rate * .1))
        count = len(signal) // window
        windows = signal[:count * window].reshape(count, window)
        window_rms = np.sqrt(np.mean(windows ** 2, axis=1))
        # Limiar de atividade relativo ao máximo, com piso -60 dBFS.
        # Não identifica notas, ruído, guitarra ou região aprovada para comparação.
        threshold = max(float(window_rms.max()) * .1, .001) if count else .001
        active = np.flatnonzero(window_rms > threshold)
        metrics.append({
            "channel": index + 1,
            "sample_peak_dbfs": db(peak), "rms_dbfs": db(rms),
            "crest_db": db(peak / rms) if rms else None,
            "fraction_abs_ge_0_99": float(np.mean(np.abs(signal) >= .99)),
            "fraction_abs_gt_1": float(np.mean(np.abs(signal) > 1)),
            "activity_threshold_dbfs": db(threshold),
            "first_active_window_seconds": float(active[0] * window / rate) if len(active) else None,
            "last_active_window_end_seconds": float((active[-1] + 1) * window / rate) if len(active) else None,
            "active_window_fraction": float(len(active) / count) if count else 0,
        })
    return {
        "file": str(path.relative_to(ROOT)),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "codec": metadata["codec_name"], "sample_rate_hz": rate,
        "channels": channels, "decoded_duration_seconds": len(samples) / rate,
        "channel_metrics": metrics,
        "capture_metadata_status": "NEEDS_CAPTURE_DATA",
        "confirmed_preset_parameters": None,
        "confirmed_guitar_and_pickup": None,
        "firmware": None,
        "auditory_verdict": "pending",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    paths = sorted(p for p in CAPTURES.iterdir() if p.suffix.lower() in {".wav", ".m4a", ".flac", ".mp3"})
    if not paths:
        raise ValueError("Nenhuma captura encontrada")
    report = {
        "schema_version": 1, "device": "MK300", "track_id": "01",
        "purpose": "qualidade_tecnica_da_captura_sem_score_de_fidelidade",
        "limitations": [
            "Nome do arquivo não confirma guitarra, preset ou rota física.",
            "Pico de amostra e proximidade ao full scale não provam clipping analógico; AAC pode ultrapassar 0 dBFS na decodificação.",
            "RMS inclui pausas; atividade por limiar é apenas triagem, sem segmentação musical.",
            "Sem DI pareada/reamp validado, estas capturas não treinam uma resposta causal dos controles.",
            "Sem alinhamento e controle de execução, diferenças não podem ser atribuídas apenas ao preset.",
        ],
        "captures": [inspect(path) for path in paths],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")
    print(f"Relatório criado: {args.output}")
    for capture in report["captures"]:
        print(Path(capture["file"]).name, round(capture["decoded_duration_seconds"], 2), "s", capture["channel_metrics"])


if __name__ == "__main__":
    main()
