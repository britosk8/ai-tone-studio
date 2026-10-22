"""Modelos de dispositivos de pedaleira."""
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field


class DeviceModel(str, Enum):
    MK20 = "MK20"
    MK300 = "MK300"
    UNKNOWN = "UNKNOWN"


class PresetRole(str, Enum):
    RHYTHM = "rhythm"
    LEAD = "lead"
    CLEAN = "clean"
    CRUNCH = "crunch"
    UNKNOWN = "unknown"


class EffectType(str, Enum):
    COMPRESSOR = "compressor"
    WAH = "wah"
    EQ = "eq"
    DRIVE = "drive"
    AMP = "amp"
    CABINET = "cabinet"
    NOISE_GATE = "noise_gate"
    MODULATION = "modulation"
    DELAY = "delay"
    REVERB = "reverb"
    VOLUME = "volume"
    EXPRESSION = "expression"


class EffectParameter(BaseModel):
    name: str
    label: str
    min_value: float
    max_value: float
    default_value: float
    unit: Optional[str] = None
    step: Optional[float] = None


class EffectModel(BaseModel):
    id: str
    name: str
    type: EffectType
    parameters: list[EffectParameter]
    supported_devices: list[DeviceModel]


class DeviceCapabilities(BaseModel):
    model: DeviceModel
    catalog_version: str
    max_presets: int
    max_banks: int
    supports_ble: bool
    supports_usb_midi: bool
    ble_service_uuid: Optional[str] = None
    usb_vid: Optional[int] = None
    usb_pid: Optional[int] = None
    signal_chain_order: list[EffectType]
    effect_models: list[EffectModel]
    notes: Optional[str] = None
