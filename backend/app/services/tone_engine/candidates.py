"""Alternativas válidas de família; sem ranking acústico na ausência de renderer."""

from ...models.devices import EffectType
from .validation import models_for, validate_preset


class PresetCandidateGenerator:
    def __init__(self, compiler):
        self.compiler = compiler

    def generate(self, seed, analysis, count=5):
        from .engine import GuitarToneEngine

        character = analysis.effect_estimates.gain_character.value
        catalog = self.compiler.catalog
        amps = [
            m
            for m in models_for(catalog, seed.device_model, EffectType.AMP)
            if m.get("type", m.get("character")) == character
        ]
        if not amps:
            amps = [
                m
                for m in models_for(catalog, seed.device_model, EffectType.AMP)
                if m["name"]
                == next(
                    b.model_name
                    for b in seed.effect_chain.blocks
                    if b.effect_type == EffectType.AMP
                )
            ]
        if not amps:
            raise ValueError(
                "NEEDS_DEVICE_DATA: família de amplificador não catalogada"
            )
        # Amostra a família ao longo do catálogo, evitando os cinco primeiros modelos.
        if len(amps) > count:
            indexes = [round(i * (len(amps) - 1) / (count - 1)) for i in range(count)]
            amps = [amps[index] for index in indexes]
        candidates = []
        for index, model in enumerate(amps[:count]):
            candidate = seed.model_copy(deep=True)
            amp = next(
                b
                for b in candidate.effect_chain.blocks
                if b.effect_type == EffectType.AMP
            )
            amp.model_id, amp.model_name = str(model["id"]), model["name"]
            GuitarToneEngine(self.compiler).refine(candidate, analysis)
            candidate.generation_metadata["candidate_index"] = index
            validate_preset(catalog, candidate)
            candidates.append(candidate)
        return candidates
