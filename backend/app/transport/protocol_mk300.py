"""
Protocolo SysEx da M-VAVE MK300 — baseado em jpfaria/mvave (MIT).

Fonte: https://github.com/jpfaria/mvave
Engenharia reversa do M-EFCS, firmware V73.

IMPORTANTE:
- Verificado em macOS via USB MIDI (CoreMIDI/python-rtmidi)
- Android: adaptador nativo android.media.midi em PedalDeviceBridge.kt; ainda sem teste físico local
- BLE: protocolo ainda NÃO capturado/verificado
- NUNCA enviar comandos de firmware, reset ou flash experimental
"""
import struct
import logging
from dataclasses import dataclass
from typing import Optional

logger = logging.getLogger(__name__)

# Identificador de fabricante M-VAVE
MANUFACTURER_ID = bytes([0x00, 0x32])

# Constantes de classe de mensagem
CLS_WRITE = 0x09
CLS_READ_REPLY = 0x0D
CLS_ACK = 0x01

# Constantes de comando
CMD_READ = 0x41
CMD_WRITE_1B = 0x49
CMD_WRITE_2B = 0x51

# Espaços de memória
SPACE_PRESET_FLASH = 0x0    # 160 × 448 bytes; offset = slot × 448
SPACE_EDIT_BUFFER = 0x1     # 448 bytes
SPACE_GLOBAL = 0x2          # 86 bytes
SPACE_COMMAND = 0xE         # Comandos (carregar preset)
SPACE_COMMIT = 0xF          # Dispara gravação no flash

# Tamanho de preset
PRESET_SIZE = 448

# Offsets no struct do preset
OFFSET_NAME = 0x00          # 20 bytes, NUL-padded
OFFSET_CONSTANT = 0x14      # FF 90 1E 00
OFFSET_VOL = 0x18           # u16
OFFSET_BPM = 0x1A           # u16
OFFSET_PAN = 0x1C           # u16
OFFSET_CHAIN_ORDER = 0x20   # 11 bytes (block IDs)
OFFSET_ONOFF = 0x2B         # 11 bytes (1=on, 0=off)
OFFSET_MODEL = 0x36         # 12 bytes (model index per block)
OFFSET_KNOBS = 0x42         # 264 bytes (11 × 12 knobs × u16)

# IDs de bloco
BLOCK_WAH = 0
BLOCK_FX = 1
BLOCK_GATE = 2
BLOCK_DS = 3
BLOCK_AMP = 4
BLOCK_CAB = 5
BLOCK_EQ = 6
BLOCK_MOD = 7
BLOCK_DLY = 8
BLOCK_REV = 9
BLOCK_VOL = 10

# Máximo de knobs por bloco
KNOBS_PER_BLOCK = 12


def knob_offset(block_id: int, knob_index: int) -> int:
    """Calcula offset de um knob na struct do preset."""
    return OFFSET_KNOBS + 24 * block_id + 2 * knob_index


def model_offset(block_id: int) -> int:
    """Offset do model index de um bloco."""
    return OFFSET_MODEL + block_id


def onoff_offset(block_id: int) -> int:
    """Offset do on/off de um bloco."""
    return OFFSET_ONOFF + block_id


class ChecksumError(Exception):
    pass


from . import sysex_codec as codec


def build_read_frame(memory_space: int, offset: int, length: int) -> bytes:
    return codec.read(offset, length, memory_space)


def build_write_u8_frame(memory_space: int, offset: int, value: int) -> bytes:
    return codec.write_u8(offset, value, memory_space)


def build_write_u16_frame(memory_space: int, offset: int, value: int) -> bytes:
    return codec.write_u16(offset, value, memory_space)


def build_load_preset_frame(preset_index: int) -> bytes:
    if not 0 <= preset_index < 160:
        raise ValueError("Slot MK300 inválido")
    return codec.load_preset(preset_index)


def build_commit_frame() -> bytes:
    return codec.COMMIT


@dataclass
class PresetStruct:
    """Representação do preset em memória da MK300."""
    name: str
    vol: int = 80
    bpm: int = 120
    pan: int = 0
    chain_order: list[int] = None
    block_enabled: dict[int, bool] = None
    block_model: dict[int, int] = None
    block_knobs: dict[int, list[int]] = None

    def __post_init__(self):
        if self.chain_order is None:
            self.chain_order = [BLOCK_GATE, BLOCK_FX, BLOCK_WAH, BLOCK_DS,
                                BLOCK_AMP, BLOCK_CAB, BLOCK_EQ, BLOCK_MOD,
                                BLOCK_DLY, BLOCK_REV, BLOCK_VOL]
        if self.block_enabled is None:
            self.block_enabled = {i: False for i in range(11)}
        if self.block_model is None:
            self.block_model = {i: 0 for i in range(11)}
        if self.block_knobs is None:
            self.block_knobs = {i: [50] * KNOBS_PER_BLOCK for i in range(11)}

    def to_bytes(self) -> bytes:
        """Serializa preset em 448 bytes para envio ao dispositivo."""
        buf = bytearray(PRESET_SIZE)

        # Nome (20 bytes, NUL-padded)
        name_bytes = self.name.encode("utf-8")[:19]
        buf[OFFSET_NAME:OFFSET_NAME + len(name_bytes)] = name_bytes

        # Constante
        buf[0x14:0x18] = bytes([0xFF, 0x90, 0x1E, 0x00])

        # Vol, BPM, Pan
        struct.pack_into("<H", buf, OFFSET_VOL, self.vol)
        struct.pack_into("<H", buf, OFFSET_BPM, self.bpm)
        struct.pack_into("<H", buf, OFFSET_PAN, self.pan)

        # Ordem da cadeia
        for i, block_id in enumerate(self.chain_order[:11]):
            buf[OFFSET_CHAIN_ORDER + i] = block_id

        # On/Off por bloco
        for block_id, enabled in self.block_enabled.items():
            buf[OFFSET_ONOFF + block_id] = 1 if enabled else 0

        # Model index por bloco
        for block_id, model in self.block_model.items():
            buf[OFFSET_MODEL + block_id] = model

        # Knobs
        for block_id, knobs in self.block_knobs.items():
            for k, val in enumerate(knobs[:KNOBS_PER_BLOCK]):
                offset = knob_offset(block_id, k)
                struct.pack_into("<H", buf, offset, val & 0xFFFF)

        # Constante final
        buf[0x1BF] = 0x45

        return bytes(buf)

    @classmethod
    def from_bytes(cls, data: bytes) -> "PresetStruct":
        """Desserializa 448 bytes lidos do dispositivo."""
        if len(data) < PRESET_SIZE:
            raise ValueError(f"Preset com tamanho inválido: {len(data)} bytes (esperado {PRESET_SIZE})")

        name = data[OFFSET_NAME:OFFSET_NAME + 20].rstrip(b"\x00").decode("utf-8", errors="replace")
        vol = struct.unpack_from("<H", data, OFFSET_VOL)[0]
        bpm = struct.unpack_from("<H", data, OFFSET_BPM)[0]
        pan = struct.unpack_from("<H", data, OFFSET_PAN)[0]

        chain_order = list(data[OFFSET_CHAIN_ORDER:OFFSET_CHAIN_ORDER + 11])
        block_enabled = {i: bool(data[OFFSET_ONOFF + i]) for i in range(11)}
        block_model = {i: data[OFFSET_MODEL + i] for i in range(11)}

        block_knobs = {}
        for block_id in range(11):
            knobs = []
            for k in range(KNOBS_PER_BLOCK):
                offset = knob_offset(block_id, k)
                val = struct.unpack_from("<H", data, offset)[0]
                knobs.append(val)
            block_knobs[block_id] = knobs

        return cls(
            name=name, vol=vol, bpm=bpm, pan=pan,
            chain_order=chain_order,
            block_enabled=block_enabled,
            block_model=block_model,
            block_knobs=block_knobs,
        )


def is_ack_frame(data: bytes) -> bool:
    return codec.is_ack(data)
