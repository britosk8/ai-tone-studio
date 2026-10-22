"""Modelos de análise de áudio e músicas."""
from enum import Enum
from typing import Optional
from uuid import UUID, uuid4
from datetime import datetime
from pydantic import BaseModel, Field


class GainCharacter(str, Enum):
    CLEAN = "clean"
    CRUNCH = "crunch"
    OVERDRIVE = "overdrive"
    HIGH_GAIN = "high_gain"
    LEAD = "lead"
    UNKNOWN = "unknown"


class MusicSection(str, Enum):
    INTRO = "intro"
    VERSE = "verse"
    CHORUS = "chorus"
    BRIDGE = "bridge"
    SOLO = "solo"
    OUTRO = "outro"
    UNKNOWN = "unknown"


class ConfidenceLevel(str, Enum):
    HIGH = "high"       # Níveis qualitativos; não são probabilidades calibradas
    MEDIUM = "medium"
    LOW = "low"         # estimativa com muita incerteza
    SPECULATIVE = "speculative"  # não confiável, apenas orientativo


class SpectralProfile(BaseModel):
    """Perfil espectral estimado do instrumento."""
    bass_energy: float = Field(ge=0, le=1, description="Energia na faixa grave (20-250 Hz)")
    low_mid_energy: float = Field(ge=0, le=1, description="Médios graves (250-800 Hz)")
    mid_energy: float = Field(ge=0, le=1, description="Médios (800-2500 Hz)")
    high_mid_energy: float = Field(ge=0, le=1, description="Médios agudos (2.5-5 kHz)")
    treble_energy: float = Field(ge=0, le=1, description="Agudos (5-20 kHz)")
    spectral_centroid_hz: float = Field(description="Centroide espectral médio em Hz")
    brightness: float = Field(ge=0, le=1, description="Brilho geral (0=escuro, 1=brilhante)")


class DynamicsProfile(BaseModel):
    """Perfil dinâmico estimado."""
    rms_db: float = Field(description="RMS médio em dB")
    peak_db: float = Field(description="Pico em dB")
    dynamic_range_db: float = Field(description="Faixa dinâmica em dB")
    transient_strength: float = Field(ge=0, le=1, description="Força dos transientes")
    compression_estimate: float = Field(ge=0, le=1, description="Estimativa de compressão (0=sem, 1=muito)")
    sustain_estimate: float = Field(ge=0, le=1, description="Estimativa de sustain")


class EffectPresenceEstimate(BaseModel):
    """Presença estimada de efeitos na gravação."""
    distortion_level: float = Field(ge=0, le=1, description="Nível de distorção estimado")
    gain_character: GainCharacter
    gain_confidence: ConfidenceLevel

    reverb_present: bool
    reverb_amount: float = Field(ge=0, le=1)
    reverb_confidence: ConfidenceLevel

    delay_present: bool
    delay_ms_estimate: Optional[float] = None
    delay_confidence: ConfidenceLevel

    chorus_present: bool
    chorus_confidence: ConfidenceLevel

    wah_present: bool
    wah_confidence: ConfidenceLevel

    compression_present: bool
    compression_confidence: ConfidenceLevel


class GuitarRegion(BaseModel):
    """Região do áudio com guitarra identificada."""
    start_seconds: float
    end_seconds: float
    confidence: float = Field(ge=0, le=1)
    section_type: MusicSection
    has_lead_guitar: bool
    has_rhythm_guitar: bool
    dominant_character: GainCharacter


class AudioAnalysisResult(BaseModel):
    """Resultado completo da análise de áudio."""
    track_id: UUID = Field(default_factory=uuid4)
    analyzed_at: datetime = Field(default_factory=datetime.utcnow)

    # Metadados básicos
    duration_seconds: float
    sample_rate: int
    bpm_estimate: Optional[float] = None
    bpm_confidence: ConfidenceLevel = ConfidenceLevel.SPECULATIVE
    key_estimate: Optional[str] = None

    # Separação de fontes
    source_separation_available: bool = False
    source_separation_model: Optional[str] = None

    # Análise de guitarra
    guitar_regions: list[GuitarRegion] = []
    overall_spectral: SpectralProfile
    overall_dynamics: DynamicsProfile
    effect_estimates: EffectPresenceEstimate

    # Análise de seções
    sections_detected: list[GuitarRegion] = []

    # Metadados de confiança geral
    overall_confidence: ConfidenceLevel
    limitations: list[str] = []
    warnings: list[str] = []
    reference_profile: dict = Field(default_factory=dict)


class MusicTrack(BaseModel):
    """Faixa musical importada pelo usuário."""
    id: UUID = Field(default_factory=uuid4)
    filename: str
    artist: Optional[str] = None
    title: Optional[str] = None
    duration_seconds: Optional[float] = None
    file_format: str
    file_size_bytes: int
    upload_timestamp: datetime = Field(default_factory=datetime.utcnow)
    analysis_result: Optional[AudioAnalysisResult] = None
    s3_key: Optional[str] = None
    processing_status: str = "pending"
    processing_error: Optional[str] = None
