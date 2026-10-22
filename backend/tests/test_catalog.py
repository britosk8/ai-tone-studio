"""Testes do catálogo de dispositivos."""
import pytest
from pathlib import Path

from app.models.devices import DeviceModel, EffectType
from app.models.audio import GainCharacter
from app.services.device_catalog.loader import CatalogLoader

# tests/ → backend/ → ai-tone-studio/ → catalogs/
CATALOGS_DIR = Path(__file__).parent.parent.parent / "catalogs"


@pytest.fixture
def loader():
    return CatalogLoader(catalogs_dir=CATALOGS_DIR)


class TestMK300Catalog:
    def test_mk300_is_supported(self, loader):
        assert loader.is_supported(DeviceModel.MK300)

    def test_mk300_catalog_version(self, loader):
        version = loader.get_catalog_version(DeviceModel.MK300)
        assert version != "unknown"
        assert "0.4" in version

    def test_mk300_amp_clean(self, loader):
        amp = loader.get_amp_model(DeviceModel.MK300, GainCharacter.CLEAN)
        assert amp is not None
        assert "clean" in amp.get("character", amp.get("type", "")).lower()

    def test_mk300_amp_high_gain(self, loader):
        amp = loader.get_amp_model(DeviceModel.MK300, GainCharacter.HIGH_GAIN)
        assert amp is not None

    def test_mk300_no_drive_for_clean(self, loader):
        drive = loader.get_drive_model(DeviceModel.MK300, GainCharacter.CLEAN)
        assert drive is None

    def test_mk300_drive_for_high_gain(self, loader):
        drive = loader.get_drive_model(DeviceModel.MK300, GainCharacter.HIGH_GAIN)
        assert drive is not None
        assert "parameters" in drive

    def test_mk300_noise_gate_exists(self, loader):
        gate = loader.get_effect_model(DeviceModel.MK300, EffectType.NOISE_GATE)
        assert gate is not None
        assert "Gate" in gate.get("parameters", {})

    def test_mk300_delay_exists(self, loader):
        delay = loader.get_effect_model(DeviceModel.MK300, EffectType.DELAY)
        assert delay is not None
        params = delay.get("parameters", {})
        # Deve ter parâmetro de tempo
        assert any("time" in k.lower() or "Time" in k for k in params)

    def test_mk300_reverb_exists(self, loader):
        reverb = loader.get_effect_model(DeviceModel.MK300, EffectType.REVERB)
        assert reverb is not None

    def test_mk300_cabinet_exists(self, loader):
        cab = loader.get_cabinet_model(DeviceModel.MK300, GainCharacter.HIGH_GAIN)
        assert cab is not None


class TestMK20Catalog:
    def test_mk20_is_supported(self, loader):
        assert loader.is_supported(DeviceModel.MK20)

    def test_mk20_amp_clean(self, loader):
        amp = loader.get_amp_model(DeviceModel.MK20, GainCharacter.CLEAN)
        assert amp is not None

    def test_mk20_amp_overdrive(self, loader):
        amp = loader.get_amp_model(DeviceModel.MK20, GainCharacter.OVERDRIVE)
        assert amp is not None

    def test_mk20_different_from_mk300_presets_count(self, loader):
        """MK20 tem 150 presets, MK300 tem 160. São diferentes."""
        mk20_cat = loader._catalogs.get(DeviceModel.MK20, {})
        mk300_cat = loader._catalogs.get(DeviceModel.MK300, {})
        mk20_presets = mk20_cat.get("device_info", {}).get("max_presets", 0)
        mk300_presets = mk300_cat.get("device_info", {}).get("max_presets", 0)
        assert mk20_presets == 150
        assert mk300_presets == 160
        assert mk20_presets != mk300_presets


class TestParameterValidation:
    def test_clamp_above_max(self, loader):
        params, warnings = loader.validate_preset_params(
            DeviceModel.MK300, EffectType.NOISE_GATE, {"Gate": 150, "Bias": 50}
        )
        # Chave canônica pode ser 'Threshold' ou 'threshold' dependendo do catálogo
        all_values = list(params.values())
        assert all(v <= 100 for v in all_values), f"Algum valor acima de 100: {params}"
        assert len(warnings) > 0

    def test_clamp_below_min(self, loader):
        params, warnings = loader.validate_preset_params(
            DeviceModel.MK300, EffectType.NOISE_GATE, {"Gate": -10, "Bias": 50}
        )
        all_values = list(params.values())
        assert all(v >= 0 for v in all_values), f"Algum valor negativo: {params}"

    def test_unknown_param_ignored(self, loader):
        params, warnings = loader.validate_preset_params(
            DeviceModel.MK300, EffectType.NOISE_GATE,
            {"Gate": 30, "Bias": 50, "parametro_falso": 999}
        )
        param_keys_lower = {k.lower() for k in params}
        assert "parametro_falso" not in param_keys_lower
        assert any("ignorado" in w or "ignorando" in w for w in warnings)
