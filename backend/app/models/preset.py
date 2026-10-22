"""Modelos de presets para pedaleiras."""
from enum import Enum
from typing import Any, Optional
from uuid import UUID, uuid4
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field, field_validator

from .devices import DeviceModel, EffectType, PresetRole
from .audio import ConfidenceLevel


class ParameterValue(BaseModel):
    """Valor validado de um parâmetro de efeito."""
    name: str
    raw_value: float
    display_value: str
    unit: Optional[str] = None
    min_value: Optional[float] = None
    max_value: Optional[float] = None
    step: Optional[float] = None


class EffectBlock(BaseModel):
    """Bloco de efeito dentro de um preset."""
    model_config = ConfigDict(protected_namespaces=())

    slot: int = Field(description="Posição na cadeia de efeitos (0-indexed)")
    effect_type: EffectType
    model_id: str = Field(description="ID do modelo de efeito no catálogo do dispositivo")
    model_name: str
    enabled: bool = True
    parameters: list[ParameterValue]

    # Metadados de geração
    generated_confidence: ConfidenceLevel
    generation_rationale: str = ""


class PresetEffectChain(BaseModel):
    """Cadeia completa de efeitos de um preset."""
    blocks: list[EffectBlock]

    @field_validator("blocks")
    @classmethod
    def validate_slots_unique(cls, blocks: list[EffectBlock]) -> list[EffectBlock]:
        slots = [b.slot for b in blocks]
        if len(slots) != len(set(slots)):
            raise ValueError("Cada slot deve ser único na cadeia de efeitos")
        return sorted(blocks, key=lambda b: b.slot)


class PresetVersion(BaseModel):
    """Versão histórica de um preset."""
    version_id: UUID = Field(default_factory=uuid4)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    effect_chain: PresetEffectChain
    change_reason: str = ""
    generated_by: str = "ai_v1"


class Preset(BaseModel):
    """Preset completo para uma pedaleira."""
    id: UUID = Field(default_factory=uuid4)
    name: str
    role: PresetRole
    device_model: DeviceModel
    catalog_version: str

    # Referência musical
    track_id: Optional[UUID] = None
    artist: Optional[str] = None
    song_title: Optional[str] = None
    source_file_name: Optional[str] = None
    section: Optional[str] = None
    bpm: Optional[float] = None

    # Configuração de efeitos (versão atual)
    effect_chain: PresetEffectChain

    # Histórico de versões
    versions: list[PresetVersion] = []

    # Metadados de qualidade da geração
    overall_confidence: ConfidenceLevel
    generation_summary: str = ""
    limitations_noted: list[str] = []
    analysis_warnings: list[str] = []

    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    def to_device_json(self) -> dict[str, Any]:
        """Serializa no formato esperado pelo protocolo do dispositivo."""
        return {
            "preset_id": str(self.id),
            "name": self.name,
            "device": self.device_model.value,
            "catalog_version": self.catalog_version,
            "role": self.role.value,
            "effects": [
                {
                    "slot": block.slot,
                    "type": block.effect_type.value,
                    "model_id": block.model_id,
                    "enabled": block.enabled,
                    "params": {p.name: p.raw_value for p in block.parameters},
                }
                for block in self.effect_chain.blocks
            ],
        }

    def to_readable_guide(self) -> str:
        """Gera guia legível para configuração manual na pedaleira."""
        lines = [
            f"=== PRESET: {self.name} ===",
            f"Dispositivo: {self.device_model.value}",
            f"Função: {self.role.value.upper()}",
        ]
        if self.artist or self.song_title:
            music = " — ".join(value for value in (self.artist, self.song_title) if value)
            lines.append(f"Música: {music}")
        if self.bpm:
            lines.append(f"BPM estimado: {self.bpm:.0f}")

        lines.append(f"\nConfiança da geração: {self.overall_confidence.value.upper()}")
        lines.append(f"\n{self.generation_summary}")

        lines.append("\n--- CADEIA DE EFEITOS ---")
        for block in self.effect_chain.blocks:
            status = "LIGADO" if block.enabled else "DESLIGADO"
            lines.append(f"\n[{block.slot + 1}] {block.model_name} ({status})")
            for param in block.parameters:
                lines.append(f"    {param.name}: {param.display_value}")

        if self.limitations_noted:
            lines.append("\n--- LIMITAÇÕES ---")
            for lim in self.limitations_noted:
                lines.append(f"• {lim}")

        return "\n".join(lines)


class PresetPair(BaseModel):
    """Par de presets gerados para uma música (base + solo)."""
    track_id: UUID
    rhythm_preset: Preset
    lead_preset: Preset
    generation_timestamp: datetime = Field(default_factory=datetime.utcnow)
    analysis_summary: str = ""
