"""Features objetivas; scores de distorção são proxies, não probabilidades."""

import librosa
import numpy as np
import soundfile as sf

BANDS = [
    (80, 150),
    (150, 250),
    (250, 400),
    (400, 800),
    (800, 1600),
    (1600, 3200),
    (3200, 6400),
    (6400, 12000),
]


class GuitarToneFeatureExtractor:
    def extract(self, path):
        raw, native_sr = sf.read(path, dtype="float32", always_2d=True)
        peak = float(np.max(np.abs(raw)))
        rms = float(np.sqrt(np.mean(raw.astype(float) ** 2)))
        # Evita cancelamento de fase entre guitarras L/R ao escolher canal representativo.
        channel_rms = np.sqrt(np.mean(raw.astype(float) ** 2, axis=0))
        mono = raw[:, int(np.argmax(channel_rms))]
        y = librosa.resample(mono, orig_sr=native_sr, target_sr=32000)
        sr = 32000
        S = np.abs(librosa.stft(y, n_fft=2048, hop_length=512))
        power = S**2
        frequencies = librosa.fft_frequencies(sr=sr, n_fft=2048)
        total = max(float(np.mean(np.sum(power, axis=0))), 1e-12)
        bands = {
            f"{low}_{high}": float(
                10
                * np.log10(
                    max(
                        float(
                            np.mean(
                                np.sum(
                                    power[(frequencies >= low) & (frequencies < high)],
                                    axis=0,
                                )
                            )
                        ),
                        1e-12,
                    )
                    / total
                )
            )
            for low, high in BANDS
        }
        frames = librosa.feature.rms(y=y)[0]
        frames_db = librosa.amplitude_to_db(np.maximum(frames, 1e-12), ref=1)
        flatness = float(librosa.feature.spectral_flatness(S=S).mean())
        onset = librosa.onset.onset_strength(
            S=librosa.power_to_db(power + 1e-12), sr=sr
        )
        crest = float(20 * np.log10(max(peak, 1e-12) / max(rms, 1e-12)))
        # Combina dinâmica e distribuição espectral. Não identifica circuito/amp.
        compression = float(np.clip((16 - crest) / 16, 0, 1))
        high_fraction = float(
            np.sum(power[frequencies >= 3200]) / max(float(power.sum()), 1e-12)
        )
        zcr = float(librosa.feature.zero_crossing_rate(y).mean())
        relevant = power[(frequencies >= 80) & (frequencies < 6400)]
        distribution = relevant / (relevant.sum(axis=0, keepdims=True) + 1e-12)
        entropy = -(distribution * np.log(distribution + 1e-12)).sum(axis=0) / np.log(
            len(relevant)
        )
        active = frames > max(float(frames.max()) * 0.1, 1e-9)
        harmonic_density = (
            float(np.median(entropy[: len(active)][active])) if np.any(active) else 0.0
        )
        distortion = float(
            np.clip(
                0.40 * np.clip(zcr / 0.12, 0, 1)
                + 0.35 * harmonic_density
                + 0.15 * compression
                + 0.10 * np.clip(flatness / 0.01, 0, 1),
                0,
                1,
            )
        )
        left, right = raw[:, 0], raw[:, -1]
        side_ratio = float(
            np.mean((left - right) ** 2)
            / max(float(np.mean((left + right) ** 2)), 1e-12)
        )
        return {
            "version": "guitar-features-v1",
            "sample_rate": sr,
            "duration_seconds": len(raw) / native_sr,
            "rms_dbfs": float(20 * np.log10(max(rms, 1e-12))),
            "peak_dbfs": float(20 * np.log10(max(peak, 1e-12))),
            "clipped_fraction": float(np.mean(np.abs(raw) >= 0.9999)),
            "crest_db": crest,
            "rms_range_db": float(
                np.percentile(frames_db, 95) - np.percentile(frames_db, 10)
            ),
            "lufs": None,
            "loudness_range_lu": None,
            "centroid_hz": float(librosa.feature.spectral_centroid(S=S, sr=sr).mean()),
            "rolloff_hz": float(
                librosa.feature.spectral_rolloff(S=S, sr=sr, roll_percent=0.95).mean()
            ),
            "flatness": flatness,
            "zcr": zcr,
            "spectral_flux": float(
                np.mean(
                    np.maximum(
                        np.diff(
                            S / (np.linalg.norm(S, axis=0, keepdims=True) + 1e-12),
                            axis=1,
                        ),
                        0,
                    )
                )
            ),
            "spectral_contrast": librosa.feature.spectral_contrast(S=S, sr=sr)
            .mean(axis=1)
            .tolist(),
            "mfcc": librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).mean(axis=1).tolist(),
            "bands_db": bands,
            "compression_proxy": compression,
            "attack_strength": float(np.clip(np.percentile(onset, 90) / 10, 0, 1)),
            "harmonic_density_proxy": harmonic_density,
            "high_frequency_energy": high_fraction,
            "distortion_score": distortion,
            "stereo_side_ratio": side_ratio,
            "possible_layering": side_ratio > 0.1,
            "limitations": [
                "LUFS e LRA não implementados; RMS range não é LRA.",
                "Distorção e compressão são proxies heurísticos, sem calibração do pedal.",
                "Largura estéreo não comprova duas guitarras.",
                "Delay, reverb e modulação não são determinados por estas features.",
            ],
        }
