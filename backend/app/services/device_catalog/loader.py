"""Carregador e validador de catálogos de dispositivos."""

import json
import logging
from pathlib import Path
from typing import Optional

from ...models.devices import DeviceModel, EffectType
from ...models.audio import GainCharacter

logger = logging.getLogger(__name__)

# Mapeamento: GainCharacter → tipos de amp preferidos (verificar campo "type" ou "character")
GAIN_TO_AMP_TYPES = {
    GainCharacter.CLEAN: ["clean"],
    GainCharacter.CRUNCH: ["crunch", "overdrive"],
    GainCharacter.OVERDRIVE: ["overdrive", "crunch"],
    GainCharacter.HIGH_GAIN: ["high_gain", "lead"],
    GainCharacter.LEAD: ["lead", "high_gain"],
    GainCharacter.UNKNOWN: ["clean"],
}

GAIN_TO_DS_TYPES = {
    GainCharacter.CLEAN: [],
    GainCharacter.CRUNCH: ["overdrive"],
    GainCharacter.OVERDRIVE: ["overdrive", "distortion"],
    GainCharacter.HIGH_GAIN: ["distortion", "high_gain"],
    GainCharacter.LEAD: ["distortion", "high_gain"],
    GainCharacter.UNKNOWN: [],
}

GAIN_TO_CAB_PREFERENCE = {
    GainCharacter.CLEAN: ["212", "110"],
    GainCharacter.CRUNCH: ["412", "212"],
    GainCharacter.OVERDRIVE: ["412"],
    GainCharacter.HIGH_GAIN: ["412"],
    GainCharacter.LEAD: ["412"],
    GainCharacter.UNKNOWN: ["412"],
}

# Mapeamento: EffectType → chave de bloco no catálogo
EFFECT_TO_BLOCK_KEY = {
    EffectType.NOISE_GATE: "GATE",
    EffectType.COMPRESSOR: "FX",
    EffectType.MODULATION: "MOD",
    EffectType.DELAY: "DLY",
    EffectType.REVERB: "REV",
    EffectType.WAH: "WAH",
    EffectType.EQ: "EQ",
    EffectType.VOLUME: "VOL",
}


class CatalogLoader:
    """Carrega e valida catálogos de dispositivos M-VAVE."""

    # Catálogos com dados suficientes para uso
    USABLE_STATUSES = {"COMMUNITY", "VERIFIED", "INFERRED"}

    def __init__(self, catalogs_dir: Optional[Path] = None):
        if catalogs_dir is None:
            # loader.py está em: backend/app/services/device_catalog/
            # catalogs/ está em: ai-tone-studio/catalogs/ (4 parents acima)
            here = Path(__file__).parent
            catalogs_dir = here.parent.parent.parent.parent / "catalogs"

        self.catalogs_dir = catalogs_dir
        self._catalogs: dict[DeviceModel, dict] = {}
        self._load_all()

    def _load_all(self):
        for device in DeviceModel:
            if device == DeviceModel.UNKNOWN:
                continue
            catalog_path = self.catalogs_dir / device.value.lower() / "catalog.json"
            if catalog_path.exists():
                try:
                    with open(catalog_path) as f:
                        data = json.load(f)
                    self._catalogs[device] = data
                    logger.info(f"Catálogo carregado: {device.value} ({catalog_path})")
                except Exception as e:
                    logger.error(f"Erro ao carregar catálogo {device.value}: {e}")
            else:
                logger.warning(f"Catálogo não encontrado: {catalog_path}")

    def is_supported(self, device: DeviceModel) -> bool:
        """Retorna True se o dispositivo tem catálogo suficientemente validado."""
        if device not in self._catalogs:
            return False
        cat = self._catalogs[device]
        meta = cat.get("_meta", {})
        status = meta.get("verification_status", "PLACEHOLDER")
        return status in self.USABLE_STATUSES

    def get_catalog_version(self, device: DeviceModel) -> str:
        cat = self._catalogs.get(device, {})
        return cat.get("_meta", {}).get("catalog_version", "unknown")

    def get_amp_model(
        self, device: DeviceModel, gain_char: GainCharacter
    ) -> Optional[dict]:
        """Retorna modelo de amp adequado para o timbre."""
        cat = self._catalogs.get(device, {})

        # Tenta estrutura nova (blocks.AMP.models)
        amps = cat.get("blocks", {}).get("AMP", {}).get("models", [])
        # Tenta estrutura alternativa (amp_models.models)
        if not amps:
            amps = cat.get("amp_models", {}).get("models", [])

        if not amps:
            return None

        preferred_types = GAIN_TO_AMP_TYPES.get(gain_char, ["clean"])

        # Busca modelo com tipo preferido
        for ptype in preferred_types:
            for amp in amps:
                amp_type = amp.get("type", amp.get("character", "")).lower()
                if amp_type == ptype:
                    # Adiciona parâmetros do catálogo
                    params = self._get_amp_params(cat)
                    return {**amp, "parameters": {**params, **amp.get("params", {})}}

        # Fallback: primeiro da lista
        if amps:
            params = self._get_amp_params(cat)
            return {**amps[0], "parameters": {**params, **amps[0].get("params", {})}}
        return None

    def _get_amp_params(self, cat: dict) -> dict:
        """Extrai parâmetros de AMP do catálogo."""
        # Tenta blocks.AMP.knob_ranges, depois amp_models.amp_parameters
        amp_block = cat.get("blocks", {}).get("AMP", {})
        params = amp_block.get("knob_ranges", amp_block.get("common_knob_ranges", {}))
        if not params:
            params = cat.get("amp_models", {}).get("amp_parameters", {})
        return params

    def get_drive_model(
        self, device: DeviceModel, gain_char: GainCharacter
    ) -> Optional[dict]:
        """Retorna modelo de drive/overdrive para o timbre, ou None se clean."""
        if gain_char == GainCharacter.CLEAN:
            return None

        cat = self._catalogs.get(device, {})

        # Tenta blocks.DS.models
        ds_block = cat.get("blocks", {}).get("DS", {})
        drives = ds_block.get("models", [])
        # Tenta ds_models.models (catálogo MK20)
        if not drives:
            ds_block = cat.get("ds_models", {})
            drives = ds_block.get("models", [])
        # Tenta effects.overdrive_models.models (formato antigo)
        if not drives:
            ds_block = cat.get("effects", {}).get("overdrive_models", {})
            drives = ds_block.get("models", [])

        if not drives:
            return None

        preferred_types = GAIN_TO_DS_TYPES.get(gain_char, [])
        params = ds_block.get(
            "ds_parameters", ds_block.get("knob_ranges", ds_block.get("parameters", {}))
        )

        for ptype in preferred_types:
            for drive in drives:
                drive_type = drive.get("type", "").lower()
                if drive_type == ptype:
                    return {
                        **drive,
                        "parameters": {**params, **drive.get("params", {})},
                    }

        if drives:
            return {
                **drives[0],
                "parameters": {**params, **drives[0].get("params", {})},
            }
        return None

    def get_cabinet_model(
        self, device: DeviceModel, gain_char: GainCharacter
    ) -> Optional[dict]:
        """Retorna cabinet adequado para o timbre."""
        cat = self._catalogs.get(device, {})

        # Tenta blocks.CAB.selected_models, blocks.CAB.models, cab_models.models
        cab_block = cat.get("blocks", {}).get("CAB", {})
        cabs = cab_block.get("selected_models", cab_block.get("models", []))
        if not cabs:
            cab_block = cat.get("cab_models", {})
            cabs = cab_block.get("models", [])
            if not cabs:
                cabs = cab_block.get("selected_models", [])

        if not cabs:
            return None

        params = cab_block.get(
            "cab_parameters",
            cab_block.get("knob_ranges", cab_block.get("parameters", {})),
        )

        # Prefere cabs que tenham "412" no nome para high gain
        preferred_sizes = GAIN_TO_CAB_PREFERENCE.get(gain_char, ["412"])
        for size in preferred_sizes:
            for cab in cabs:
                if size in cab.get("name", "") or size in cab.get("config", ""):
                    return {**cab, "parameters": {**params, **cab.get("params", {})}}

        return (
            {**cabs[0], "parameters": {**params, **cabs[0].get("params", {})}}
            if cabs
            else None
        )

    def get_effect_model(
        self, device: DeviceModel, effect_type: EffectType, model_index: int = 0
    ) -> Optional[dict]:
        """Retorna modelo de efeito específico pelo tipo e índice."""
        cat = self._catalogs.get(device, {})

        block_key = EFFECT_TO_BLOCK_KEY.get(effect_type)
        if not block_key:
            return None

        # Tenta blocks.<KEY>
        block_data = cat.get("blocks", {}).get(block_key, {})

        # Tenta effect_modules.<KEY> (catálogo MK20)
        if not block_data:
            module_key = (
                "NS"
                if device == DeviceModel.MK20 and block_key == "GATE"
                else block_key
            )
            block_data = cat.get("effect_modules", {}).get(module_key, {})

        # Tenta effects.<key_lower> (formato antigo)
        if not block_data:
            old_key = block_key.lower()
            key_map = {
                "gate": "noise_gate",
                "dly": "delay",
                "rev": "reverb",
                "mod": "modulation",
            }
            old_key = key_map.get(old_key, old_key)
            block_data = cat.get("effects", {}).get(old_key, {})

        if not block_data:
            return None

        params = block_data.get(
            "knob_ranges",
            block_data.get("common_knob_ranges", block_data.get("parameters", {})),
        )

        models = block_data.get("models", block_data.get("mono_models", None))
        if models and model_index < len(models):
            if effect_type == EffectType.COMPRESSOR:
                matches = [
                    model for model in models if model.get("name", "") == "Compress"
                ]
                if not matches:
                    return None
                model = matches[0]
            else:
                model = models[model_index]
            # Mescla parâmetros do modelo com parâmetros do bloco
            model_params = model.get("params", model.get("parameters", {}))
            merged_params = {**params, **model_params}
            return {**model, "parameters": merged_params}
        elif not models:
            # Efeito sem sub-modelos (noise gate, compressor)
            name = block_key.replace("_", " ").title()
            return {"id": 0, "name": name, "parameters": params}

        return None

    def validate_preset_params(
        self, device: DeviceModel, effect_type: EffectType, params: dict
    ) -> tuple[dict, list[str]]:
        """Valida e clipa parâmetros nos limites do catálogo."""
        model = self.get_effect_model(device, effect_type)
        if not model:
            return params, [
                f"Modelo de {effect_type.value} não encontrado no catálogo de {device.value}"
            ]

        validated = {}
        warnings = []
        specs = model.get("parameters", {})

        specs_lower = {k.lower(): (k, v) for k, v in specs.items()}

        for name, value in params.items():
            lookup = name.lower()
            if name in specs:
                spec = specs[name]
                canonical_name = name
            elif lookup in specs_lower:
                canonical_name, spec = specs_lower[lookup]
            else:
                warnings.append(
                    f"Parâmetro '{name}' ignorado — não existe no catálogo de {device.value}"
                )
                continue
            p_min = spec.get("min", 0)
            p_max = spec.get("max", 100)
            clamped = max(p_min, min(float(value), p_max))
            if clamped != float(value):
                warnings.append(
                    f"Parâmetro '{name}' ajustado de {value} para {clamped} (limite: {p_min}-{p_max})"
                )
            validated[canonical_name] = clamped

        return validated, warnings
