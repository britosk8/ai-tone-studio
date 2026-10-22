"""Representação intermediária independente do aparelho."""

import numpy as np


def describe(features):
    bands = features["bands_db"]

    def energy(*names):
        return float(np.clip((np.mean([bands[n] for n in names]) + 30) / 30, 0, 1))

    return {
        "version": 1,
        "distortion": features["distortion_score"],
        "compression": features["compression_proxy"],
        "bass": energy("80_150", "150_250"),
        "low_mids": energy("250_400", "400_800"),
        "mids": energy("800_1600"),
        "high_mids": energy("1600_3200"),
        "treble": energy("3200_6400"),
        "fizz": energy("6400_12000"),
        "attack": features["attack_strength"],
        "delay": None,
        "reverb": None,
        "modulation": None,
    }
