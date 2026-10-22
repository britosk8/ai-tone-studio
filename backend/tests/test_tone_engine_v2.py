"""Motor novo: unidade não baixa pesos neurais."""

import io
import json
import numpy as np
import pytest
import soundfile as sf
from app.core.pipeline import ToneAnalysisPipeline
from app.models.devices import DeviceModel, EffectType
from app.services.tone_engine.features import GuitarToneFeatureExtractor
from app.services.tone_engine.descriptor import describe
from app.services.tone_engine.validation import validate_preset
from tests.test_v1_flow import client


def wave(seconds=4, sr=44100, frequency=220):
    t = np.arange(sr * seconds) / sr
    y = 0.2 * np.sin(2 * np.pi * frequency * t)
    stream = io.BytesIO()
    sf.write(stream, y, sr, format="WAV", subtype="PCM_16")
    return stream.getvalue()


def test_features_preserve_level_and_bands(tmp_path):
    path = tmp_path / "tone.wav"
    path.write_bytes(wave())
    features = GuitarToneFeatureExtractor().extract(path)
    assert len(features["bands_db"]) == 8 and len(features["mfcc"]) == 13
    assert -15 < features["peak_dbfs"] < -13
    assert features["clipped_fraction"] == 0
    assert max(features["bands_db"], key=features["bands_db"].get) == "150_250"
    assert features["lufs"] is None
    assert 0 <= describe(features)["distortion"] <= 1


@pytest.mark.asyncio
@pytest.mark.parametrize("device", [DeviceModel.MK300, DeviceModel.MK20])
async def test_isolated_generation_validates_each_device_and_candidates(
    tmp_path, device
):
    path = tmp_path / "guitar.wav"
    path.write_bytes(wave())
    pipeline = ToneAnalysisPipeline()
    analysis, pair = await pipeline.process(
        path, device, device, source_kind="isolated", engine_mode="guitar_v2"
    )
    for preset in [pair.rhythm_preset, pair.lead_preset]:
        validate_preset(pipeline.catalog, preset)
        assert preset.generation_metadata["generator"] == "guitar-v2-heuristic"
        assert all(
            not block.enabled
            for block in preset.effect_chain.blocks
            if block.effect_type
            in {EffectType.DRIVE, EffectType.DELAY, EffectType.REVERB}
        )
        amp = next(
            b for b in preset.effect_chain.blocks if b.effect_type == EffectType.AMP
        )
        amp.model_id = "99999"
        with pytest.raises(ValueError, match="NEEDS_DEVICE_DATA"):
            validate_preset(pipeline.catalog, preset)
    assert analysis.engine_diagnostics["candidates"]["rhythm"]
    assert analysis.engine_diagnostics["optimization_score"] is None


def test_v2_missing_separator_does_not_silently_analyze_mix(client, monkeypatch):
    monkeypatch.setenv("TONE_DEMUCS_PYTHON", "/missing/python")
    response = client.post(
        "/api/v1/analyze",
        files={"file": ("song.wav", wave())},
        data={"engine_mode": "guitar_v2"},
    )
    job = client.get("/api/v1/jobs/" + response.json()["job_id"]).json()
    assert job["status"] == "failed" and "TONE_DEMUCS_PYTHON" in job["error_message"]
    assert "pair_id" not in job


def test_v2_role_profiles_candidates_and_restart(client):
    audio = io.BytesIO()
    a, _ = sf.read(io.BytesIO(wave(frequency=110)))
    b, _ = sf.read(io.BytesIO(wave(frequency=3000)))
    sf.write(audio, np.concatenate([a, b]), 44100, format="WAV")
    response = client.post(
        "/api/v1/analyze",
        files={"file": ("original.wav", audio.getvalue())},
        data={
            "source_kind": "isolated",
            "engine_mode": "guitar_v2",
            "excerpt_duration": "4",
            "lead_start": "4",
            "lead_duration": "4",
        },
    )
    job = client.get("/api/v1/jobs/" + response.json()["job_id"]).json()
    assert job["status"] == "completed", job
    pair = client.get("/api/v1/presets/" + job["pair_id"]).json()
    details = pair["analysis"]["engine_diagnostics"]
    assert (
        details["features"]["centroid_hz"] < details["lead"]["features"]["centroid_hz"]
    )
    from app.core.storage import load_record

    profiles = [
        load_record("comparison_reference", json.dumps([job["pair_id"], role]))[
            "profile"
        ]
        for role in ["rhythm", "lead"]
    ]
    assert profiles[0]["bands_db"] != profiles[1]["bands_db"]
    alternatives = client.get(
        f"/api/v1/presets/{job['pair_id']}/candidates/rhythm"
    ).json()
    assert len(alternatives["candidates"]) >= 1
    assert (
        client.get(f"/api/v1/presets/{job['pair_id']}/stems/rhythm/guitar").status_code
        == 404
    )


def test_invalid_engine_and_solo_region(client):
    for data in [
        {"engine_mode": "invented"},
        {"lead_start": "0"},
        {"lead_start": "nan", "lead_duration": "20"},
    ]:
        assert (
            client.post(
                "/api/v1/analyze", files={"file": ("s.wav", wave())}, data=data
            ).status_code
            == 400
        )


def test_separation_cache_is_reused_and_corruption_is_reported(tmp_path, monkeypatch):
    from app.services.tone_engine.separation import DemucsGuitarProvider
    import app.services.tone_engine.separation as module

    monkeypatch.setenv("TONE_DATA_DIR", str(tmp_path / "data"))
    monkeypatch.setenv("TONE_DEMUCS_PYTHON", __import__("sys").executable)
    source = tmp_path / "stereo.wav"
    source.write_bytes(wave())
    calls = []

    def worker(command, **kwargs):
        calls.append(command)
        output = __import__("pathlib").Path(command[3])
        for name in ["drums", "bass", "other", "vocals", "piano", "guitar"]:
            (output / f"{name}.wav").write_bytes(wave())

    monkeypatch.setattr(module.subprocess, "run", worker)
    provider = DemucsGuitarProvider()
    first = provider.separate_guitar(source)
    second = provider.separate_guitar(source)
    assert first.guitar_stem == second.guitar_stem and len(calls) == 1
    assert first.metadata["bleed_estimate"] is None
    first.guitar_stem.write_bytes(b"corrupted")
    with pytest.raises(ValueError, match="corrompido"):
        provider.separate_guitar(source)


def test_native_clipping_not_resampler_overshoot(tmp_path):
    from app.services.audio_analysis.tone_comparison import measure

    path = tmp_path / "hot.wav"
    sr = 44100
    t = np.arange(sr * 3) / sr
    y = 0.98 * np.sign(np.sin(2 * np.pi * 1000 * t))
    sf.write(path, y, sr, subtype="PCM_16")
    result = measure(path)
    assert result["clipped_fraction"] == 0
    assert result["peak_dbfs"] < 0


def test_distortion_proxy_responds_to_harmonics_without_loudness_gain(tmp_path):
    sr = 44100
    t = np.arange(sr * 4) / sr
    extractor = GuitarToneFeatureExtractor()
    scores = []
    for name, y in [
        ("clean", 0.2 * np.sin(2 * np.pi * 220 * t)),
        ("saturated", 0.2 * np.tanh(10 * np.sin(2 * np.pi * 220 * t))),
    ]:
        path = tmp_path / f"{name}.wav"
        sf.write(path, y, sr)
        scores.append(extractor.extract(path)["distortion_score"])
    assert scores[1] > scores[0]
