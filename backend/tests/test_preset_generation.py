"""Testes de geração de presets."""
import pytest
from uuid import uuid4
from pathlib import Path

from app.models.audio import (
    AudioAnalysisResult, SpectralProfile, DynamicsProfile,
    EffectPresenceEstimate, GainCharacter, ConfidenceLevel, MusicSection
)
from app.models.devices import DeviceModel
from app.models.preset import Preset, PresetPair
from app.services.device_catalog.loader import CatalogLoader
from app.services.preset_generation.compiler import PresetCompiler
from app.transport.preset_builder import preset_to_struct

CATALOGS_DIR = Path(__file__).parent.parent.parent / "catalogs"


def make_analysis(
    gain_char: GainCharacter = GainCharacter.OVERDRIVE,
    distortion: float = 0.6,
    reverb_present: bool = True,
    delay_present: bool = True,
    bpm: float = 120.0,
) -> AudioAnalysisResult:
    return AudioAnalysisResult(
        duration_seconds=240.0,
        sample_rate=22050,
        bpm_estimate=bpm,
        bpm_confidence=ConfidenceLevel.MEDIUM,
        source_separation_available=False,
        overall_spectral=SpectralProfile(
            bass_energy=0.6,
            low_mid_energy=0.5,
            mid_energy=0.7,
            high_mid_energy=0.4,
            treble_energy=0.3,
            spectral_centroid_hz=2500.0,
            brightness=0.5,
        ),
        overall_dynamics=DynamicsProfile(
            rms_db=-18.0,
            peak_db=-3.0,
            dynamic_range_db=15.0,
            transient_strength=0.6,
            compression_estimate=0.4,
            sustain_estimate=0.6,
        ),
        effect_estimates=EffectPresenceEstimate(
            distortion_level=distortion,
            gain_character=gain_char,
            gain_confidence=ConfidenceLevel.LOW,
            reverb_present=reverb_present,
            reverb_amount=0.4 if reverb_present else 0.0,
            reverb_confidence=ConfidenceLevel.LOW,
            delay_present=delay_present,
            delay_ms_estimate=375.0 if delay_present else None,
            delay_confidence=ConfidenceLevel.LOW,
            chorus_present=False,
            chorus_confidence=ConfidenceLevel.SPECULATIVE,
            wah_present=False,
            wah_confidence=ConfidenceLevel.SPECULATIVE,
            compression_present=True,
            compression_confidence=ConfidenceLevel.MEDIUM,
        ),
        overall_confidence=ConfidenceLevel.LOW,
        limitations=["Análise em mixagem completa"],
    )


@pytest.fixture
def compiler():
    loader = CatalogLoader(catalogs_dir=CATALOGS_DIR)
    return PresetCompiler(loader)


class TestPresetPairGeneration:
    def test_compile_pair_mk300(self, compiler):
        analysis = make_analysis()
        pair = compiler.compile_pair(
            analysis,
            rhythm_device=DeviceModel.MK300,
            lead_device=DeviceModel.MK300,
            artist="Test Artist",
            song_title="Test Song",
        )
        assert isinstance(pair, PresetPair)
        assert pair.rhythm_preset is not None
        assert pair.lead_preset is not None

    def test_rhythm_preset_has_amp(self, compiler):
        analysis = make_analysis()
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        blocks_types = [b.effect_type.value for b in pair.rhythm_preset.effect_chain.blocks]
        assert "amp" in blocks_types

    def test_lead_preset_has_delay(self, compiler):
        analysis = make_analysis(delay_present=True)
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        blocks_types = [b.effect_type.value for b in pair.lead_preset.effect_chain.blocks]
        assert "delay" in blocks_types

    def test_clean_tone_no_drive(self, compiler):
        analysis = make_analysis(gain_char=GainCharacter.CLEAN, distortion=0.05)
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        # Guitarra clean: bloco de drive deve estar desligado ou ausente
        rhythm_blocks = pair.rhythm_preset.effect_chain.blocks
        drive_blocks = [b for b in rhythm_blocks if b.effect_type.value == "drive"]
        if drive_blocks:
            # Se existir, deve estar desligado
            assert not drive_blocks[0].enabled

    def test_all_params_within_catalog_bounds(self, compiler):
        """Nenhum parâmetro deve ultrapassar os limites do catálogo."""
        for gain_char in GainCharacter:
            analysis = make_analysis(gain_char=gain_char)
            try:
                pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
                for preset in [pair.rhythm_preset, pair.lead_preset]:
                    for block in preset.effect_chain.blocks:
                        for param in block.parameters:
                            assert param.raw_value >= 0, f"Parâmetro {param.name} negativo"
                            assert param.raw_value <= 100 or "time" in param.name.lower(), \
                                f"Parâmetro {param.name}={param.raw_value} acima de 100"
            except ValueError:
                pass  # Dispositivo não suportado é OK aqui

    def test_rhythm_preset_role(self, compiler):
        analysis = make_analysis()
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        assert pair.rhythm_preset.role.value == "rhythm"

    def test_lead_preset_role(self, compiler):
        analysis = make_analysis()
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        assert pair.lead_preset.role.value == "lead"

    def test_preset_confidence_not_high_without_separation(self, compiler):
        """Sem separação de fontes, confiança nunca deve ser HIGH."""
        analysis = make_analysis()
        assert not analysis.source_separation_available
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        # Confiança geral não deve ser HIGH sem separação
        assert pair.rhythm_preset.overall_confidence.value in ["low", "medium"]

    def test_preset_has_limitations_noted(self, compiler):
        analysis = make_analysis()
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        assert len(pair.rhythm_preset.limitations_noted) > 0

    def test_slots_unique_in_chain(self, compiler):
        """Slots na cadeia de efeitos devem ser únicos."""
        analysis = make_analysis()
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        for preset in [pair.rhythm_preset, pair.lead_preset]:
            slots = [b.slot for b in preset.effect_chain.blocks]
            assert len(slots) == len(set(slots))


class TestPresetExport:
    def test_to_device_json(self, compiler):
        analysis = make_analysis()
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        device_json = pair.rhythm_preset.to_device_json()
        assert "preset_id" in device_json
        assert "effects" in device_json
        assert device_json["device"] == "MK300"

    def test_to_readable_guide(self, compiler):
        analysis = make_analysis()
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        guide = pair.rhythm_preset.to_readable_guide()
        assert "PRESET" in guide
        assert "CADEIA DE EFEITOS" in guide
        assert "LIMITAÇÕES" in guide

    def test_readable_guide_contains_artist(self, compiler):
        analysis = make_analysis()
        pair = compiler.compile_pair(
            analysis, DeviceModel.MK300, DeviceModel.MK300,
            artist="Led Zeppelin", song_title="Stairway to Heaven"
        )
        guide = pair.rhythm_preset.to_readable_guide()
        assert "Led Zeppelin" in guide


class TestPresetToStruct:
    def test_rhythm_preset_to_struct(self, compiler):
        analysis = make_analysis()
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        struct = preset_to_struct(pair.rhythm_preset, bpm=120)
        assert struct is not None
        data = struct.to_bytes()
        assert len(data) == 448

    def test_lead_preset_to_struct(self, compiler):
        analysis = make_analysis()
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        struct = preset_to_struct(pair.lead_preset, bpm=120)
        data = struct.to_bytes()
        assert len(data) == 448

    def test_struct_name_matches_preset(self, compiler):
        analysis = make_analysis()
        pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
        struct = preset_to_struct(pair.rhythm_preset)
        assert struct.name in pair.rhythm_preset.name or len(struct.name) <= 19
