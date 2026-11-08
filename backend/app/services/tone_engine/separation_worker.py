"""Processo isolado; executado no ambiente Demucs, nunca importa torch na API."""

import os
import sys
from pathlib import Path
import numpy as np
import soundfile as sf
import torch
from demucs.pretrained import get_model
from demucs.apply import apply_model
import importlib
from worker_progress import emit, ChunkProgress


def main():
    source, destination = map(Path, sys.argv[1:3])
    torch.set_num_threads(int(os.environ.get("TONE_DEMUCS_THREADS", "2")))
    torch.manual_seed(0)
    emit("loading")
    model = get_model("htdemucs_6s").cpu().eval()
    if "guitar" not in model.sources:
        raise ValueError("Modelo sem stem guitar")
    y, sr = sf.read(source, dtype="float32", always_2d=True)
    if sr != model.samplerate or y.shape[1] != model.audio_channels:
        raise ValueError("Formato de entrada incompatível")
    mix = torch.from_numpy(y.T.copy())
    ref = mix.mean(0)
    mean, std = ref.mean(), ref.std()
    if std < 1e-6:
        raise ValueError("Sinal insuficiente para separação")
    # Intercept only the progress iterator; inference and overlap remain unchanged.
    importlib.import_module("demucs.apply").tqdm.tqdm = ChunkProgress(
        len(model.models) if hasattr(model, "models") else 1
    )
    with torch.inference_mode():
        stems = (
            apply_model(
                model,
                ((mix - mean) / std)[None],
                device="cpu",
                shifts=0,
                split=True,
                overlap=0.25,
                segment=4,
                num_workers=0,
                progress=True,
            )[0]
            * std
            + mean
        )
    if not torch.isfinite(stems).all():
        raise ValueError("Separação retornou valores não finitos")
    emit("saving")
    destination.mkdir(parents=True, exist_ok=True)
    for name, samples in zip(model.sources, stems):
        sf.write(destination / f"{name}.wav", samples.numpy().T, sr, subtype="FLOAT")


if __name__ == "__main__":
    main()
