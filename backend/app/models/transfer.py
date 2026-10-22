"""Modelos de transferência de preset para dispositivo."""
from enum import Enum
from typing import Optional
from uuid import UUID, uuid4
from datetime import datetime
from pydantic import BaseModel, Field

from .devices import DeviceModel


class TransportType(str, Enum):
    BLE = "ble"
    USB_MIDI = "usb_midi"
    SIMULATED = "simulated"
    MANUAL_EXPORT = "manual_export"


class TransferStatus(str, Enum):
    PENDING = "pending"
    CONNECTING = "connecting"
    BACKING_UP = "backing_up"
    TRANSFERRING = "transferring"
    VERIFYING = "verifying"
    SUCCESS = "success"
    FAILED = "failed"
    CANCELLED = "cancelled"


class DeviceInfo(BaseModel):
    """Informações do dispositivo detectado."""
    device_model: DeviceModel
    firmware_version: Optional[str] = None
    serial_number: Optional[str] = None
    transport: TransportType
    connection_address: Optional[str] = None
    is_validated: bool = False
    detection_notes: str = ""


class PresetBackup(BaseModel):
    """Backup do preset original antes da sobrescrita."""
    backup_id: UUID = Field(default_factory=uuid4)
    slot: int
    original_data: dict
    backup_timestamp: datetime = Field(default_factory=datetime.utcnow)
    device_info: DeviceInfo


class TransferRequest(BaseModel):
    """Solicitação de transferência de preset."""
    request_id: UUID = Field(default_factory=uuid4)
    preset_id: UUID
    device_info: DeviceInfo
    target_slot: int
    create_backup: bool = True
    user_confirmed: bool = False


class TransferResult(BaseModel):
    """Resultado de uma transferência."""
    request_id: UUID
    status: TransferStatus
    backup: Optional[PresetBackup] = None
    error_message: Optional[str] = None
    verified_readback: Optional[dict] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    warnings: list[str] = []
