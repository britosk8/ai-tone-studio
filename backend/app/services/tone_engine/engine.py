from pathlib import Path
import numpy as np
from ...models.audio import ConfidenceLevel, GainCharacter
from ...models.devices import EffectType
from ..audio_analysis.analyzer import AudioAnalyzer
from .preprocess import AudioPreprocessor
from .separation import DemucsGuitarProvider
from .features import GuitarToneFeatureExtractor
from .descriptor import describe
from .validation import models_for, validate_preset


class GuitarToneEngine:
    """Modo heurístico explícito: sem renderer, sem loss/fidelidade inventada."""

    def __init__(self, compiler, provider=None):
        self.compiler = compiler
        self.provider = provider or DemucsGuitarProvider()

    def analyze(
        self,
        source,
        work_dir,
        source_kind,
        start,
        duration,
        progress,
        cached_reference=None,
        preferred_channel=None,
    ):
        if cached_reference:
            from .separation import crop_saved_stems

            progress(
                25,
                "Reutilizando a guitarra já separada, sem enviar a música novamente...",
            )
            separation = crop_saved_stems(
                cached_reference["cache_id"],
                start - cached_reference["cache_start_seconds"],
                duration,
            )
            target = separation.guitar_stem
        else:
            progress(15, "Preparando áudio estéreo sem normalização...")
            prepared = AudioPreprocessor().prepare(
                source, work_dir / "reference.wav", start, duration
            )
            separation = None
            target = prepared
            if source_kind == "mix":
                progress(
                    25,
                    "Separando guitarra, voz, baixo, bateria e demais instrumentos... Isso pode levar vários minutos.",
                )
                separation = self.provider.separate_guitar(prepared)
                target = separation.guitar_stem
        progress(70, "Medindo espectro, dinâmica e ataque da guitarra...")
        features = GuitarToneFeatureExtractor().extract(
            target, channel=preferred_channel
        )
        descriptor = describe(features)
        # O stem dedicado ainda contém possíveis vazamentos; não o declarar isolado pelo usuário.
        import soundfile as sf

        samples, sample_rate = sf.read(target, dtype="float32", always_2d=True)
        channel = (
            int(np.argmax(np.mean(samples.astype(float) ** 2, axis=0)))
            if preferred_channel is None
            else preferred_channel
        )
        if channel < 0 or channel >= samples.shape[1]:
            raise ValueError("Canal indisponível na guitarra salva")
        analysis_path = work_dir / "analysis_channel.wav"
        sf.write(analysis_path, samples[:, channel], sample_rate, subtype="FLOAT")
        analysis = AudioAnalyzer(
            source_kind="isolated" if source_kind == "isolated" else "mix"
        ).analyze(analysis_path)
        level = descriptor["distortion"]
        character = (
            GainCharacter.CLEAN
            if level < 0.25
            else (
                GainCharacter.CRUNCH
                if level < 0.43
                else (
                    GainCharacter.OVERDRIVE if level < 0.55 else GainCharacter.HIGH_GAIN
                )
            )
        )
        analysis.effect_estimates.distortion_level = level
        analysis.effect_estimates.gain_character = character
        analysis.overall_confidence = ConfidenceLevel.LOW
        analysis.effect_estimates.gain_confidence = ConfidenceLevel.LOW
        # Decaimento na música não comprova um efeito no pedal: nada é adicionado por papel.
        analysis.effect_estimates.compression_present = False
        analysis.effect_estimates.delay_present = False
        analysis.effect_estimates.reverb_present = False
        analysis.effect_estimates.chorus_present = False
        analysis.source_separation_available = separation is not None
        analysis.source_separation_model = "htdemucs_6s" if separation else None
        analysis.limitations += [
            "Motor v2 em modo heurístico; sem modelo calibrado da MK300/MK20 nem percentual de similaridade.",
            "Base e solo são partes indicadas pelos trechos; o separador não desmembra guitarras simultâneas.",
            "Efeitos temporais permanecem desligados sem evidência suficiente.",
            "Cortes do gabinete usam pontos iniciais do catálogo, sem calibração acústica para sua cadeia.",
        ]
        if separation:
            analysis.limitations += separation.metadata.get(
                "limitations",
                ["A separação pode conter vazamentos e guitarras simultâneas."],
            )
        if features["possible_layering"]:
            analysis.warnings.append(
                "Referência estéreo larga: pode conter guitarras sobrepostas ou efeitos estéreo."
            )
        analysis.reference_profile["source_kind"] = (
            "separated_guitar" if separation else "isolated"
        )
        analysis.engine_diagnostics = {
            "engine": "guitar_v2",
            "mode": "heuristic",
            "features": features,
            "target_tone": descriptor,
            "analysis_channel": channel,
            "separation": separation.metadata if separation else None,
            "optimization_score": None,
            "region": {
                "start_seconds": start,
                "duration_seconds": features["duration_seconds"],
            },
        }
        return analysis

    def refine(self, preset, analysis):
        """Traduz o descriptor, usa modelos do catálogo e valida o resultado completo."""
        descriptor = analysis.engine_diagnostics["target_tone"]
        catalog = self.compiler.catalog
        for block in preset.effect_chain.blocks:
            if block.effect_type == EffectType.AMP:
                # Mantém a família tipada do catálogo; não infere um amp exato do áudio.
                values = {
                    "Gain": round(8 + descriptor["distortion"] * 65),
                    "Level": 40,
                    "Bass": round(35 + descriptor["bass"] * 25),
                    "Middle": round(35 + descriptor["mids"] * 30),
                    "Treble": round(35 + descriptor["treble"] * 30),
                    "Pres": round(30 + descriptor["high_mids"] * 30),
                    "Reso": 25,
                    "Bright": 30,
                }
            elif block.effect_type == EffectType.DRIVE:
                # Evita empilhar duas distorções como se fossem inferíveis da mixagem.
                block.enabled = False
                values = {"Gain": 10, "Level": 50}
            elif block.effect_type == EffectType.CABINET:
                values = {"Level": 60}
            else:
                continue
            model = next(
                (
                    m
                    for m in models_for(catalog, preset.device_model, block.effect_type)
                    if str(m["id"]) == block.model_id
                ),
                None,
            )
            if model is None:
                raise ValueError(f"NEEDS_DEVICE_DATA: {block.model_name}")
            specs = model["parameters"]
            # Defaults conhecidos para todos os knobs, sem herdar o destino no pedal.
            captured_defaults = {}
            if block.effect_type == EffectType.CABINET:
                # Somente valores efetivamente registrados no catálogo deste aparelho.
                examples = models_for(catalog, preset.device_model, block.effect_type)
                for name in specs:
                    known = next(
                        (
                            m["parameters"][name]["default"]
                            for m in examples
                            if "default" in m.get("parameters", {}).get(name, {})
                        ),
                        None,
                    )
                    if known is not None:
                        captured_defaults[name] = known
            values = {
                name: values.get(
                    name,
                    spec.get(
                        "default", captured_defaults.get(name, spec.get("min", 0))
                    ),
                )
                for name, spec in specs.items()
            }
            for name, spec in specs.items():
                minimum, maximum = spec.get("min", 0), spec.get("max", 100)
                step = spec.get("step", 1) or 1
                values[name] = max(
                    minimum,
                    min(
                        maximum, minimum + round((values[name] - minimum) / step) * step
                    ),
                )
            block.parameters = self.compiler._build_parameters(model, values)
            block.generated_confidence = ConfidenceLevel.LOW
            block.generation_rationale = (
                "Regra heurística aplicada ao perfil de guitarra; modelo da família "
                "do catálogo, sem equivalência acústica demonstrada."
            )
        preset.generation_metadata = {
            "generator": "guitar-v2-heuristic",
            "target_tone": descriptor,
            "region": analysis.engine_diagnostics["region"],
            "separation_cache_id": (
                analysis.engine_diagnostics.get("separation") or {}
            ).get("cache_id"),
        }
        preset.preset_volume = 40
        validate_preset(catalog, preset)
        return preset
