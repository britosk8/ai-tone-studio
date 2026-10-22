"""Testes do protocolo SysEx MK300."""
import struct
import pytest

from app.transport.protocol_mk300 import (
    build_read_frame,
    build_write_u8_frame,
    build_write_u16_frame,
    build_load_preset_frame,
    build_commit_frame,
    PresetStruct,
    is_ack_frame,
    PRESET_SIZE,
    SPACE_EDIT_BUFFER,
    SPACE_COMMAND,
    MANUFACTURER_ID,
    OFFSET_NAME,
    OFFSET_VOL,
    OFFSET_BPM,
)


class TestFrameStructure:
    def test_frames_start_with_f0(self):
        frame = build_read_frame(SPACE_EDIT_BUFFER, 0, 448)
        assert frame[0] == 0xF0

    def test_frames_end_with_f7(self):
        frame = build_read_frame(SPACE_EDIT_BUFFER, 0, 448)
        assert frame[-1] == 0xF7

    def test_manufacturer_id_present(self):
        frame = build_read_frame(SPACE_EDIT_BUFFER, 0, 448)
        assert frame[1:3] == MANUFACTURER_ID

    def test_load_preset_frame_structure(self):
        frame = build_load_preset_frame(0)
        assert frame[0] == 0xF0
        assert frame[-1] == 0xF7
        assert frame[1:3] == MANUFACTURER_ID

    def test_commit_frame_structure(self):
        frame = build_commit_frame()
        assert frame[0] == 0xF0
        assert frame[-1] == 0xF7


class TestPresetStruct:
    def test_preset_serialization_size(self):
        ps = PresetStruct(name="Test Preset")
        data = ps.to_bytes()
        assert len(data) == PRESET_SIZE

    def test_preset_name_roundtrip(self):
        name = "Meu Preset"
        ps = PresetStruct(name=name)
        data = ps.to_bytes()
        ps2 = PresetStruct.from_bytes(data)
        assert ps2.name == name

    def test_preset_vol_roundtrip(self):
        ps = PresetStruct(name="Test", vol=75)
        data = ps.to_bytes()
        ps2 = PresetStruct.from_bytes(data)
        assert ps2.vol == 75

    def test_preset_bpm_roundtrip(self):
        ps = PresetStruct(name="Test", bpm=140)
        data = ps.to_bytes()
        ps2 = PresetStruct.from_bytes(data)
        assert ps2.bpm == 140

    def test_preset_block_enabled_roundtrip(self):
        ps = PresetStruct(name="Test")
        ps.block_enabled = {i: (i % 2 == 0) for i in range(11)}
        data = ps.to_bytes()
        ps2 = PresetStruct.from_bytes(data)
        for i in range(11):
            assert ps2.block_enabled[i] == ps.block_enabled[i]

    def test_preset_model_roundtrip(self):
        ps = PresetStruct(name="Test")
        ps.block_model = {i: i * 2 for i in range(11)}
        data = ps.to_bytes()
        ps2 = PresetStruct.from_bytes(data)
        for i in range(11):
            assert ps2.block_model[i] == ps.block_model[i]

    def test_preset_knob_roundtrip(self):
        ps = PresetStruct(name="Test")
        # Define um valor específico no bloco AMP, knob 0 (Gain)
        ps.block_knobs[4][0] = 75  # AMP block_id=4, Gain=knob 0
        data = ps.to_bytes()
        ps2 = PresetStruct.from_bytes(data)
        assert ps2.block_knobs[4][0] == 75

    def test_constant_preserved(self):
        ps = PresetStruct(name="Test")
        data = ps.to_bytes()
        assert data[0x14:0x18] == bytes([0xFF, 0x90, 0x1E, 0x00])
        assert data[0x1BF] == 0x45

    def test_name_truncated_to_19_chars(self):
        long_name = "X" * 30
        ps = PresetStruct(name=long_name)
        data = ps.to_bytes()
        stored_name = data[OFFSET_NAME:OFFSET_NAME + 20].rstrip(b"\x00").decode()
        assert len(stored_name) <= 19

    def test_invalid_size_raises(self):
        with pytest.raises(ValueError):
            PresetStruct.from_bytes(b"\x00" * 100)


class TestAckDetection:
    def test_valid_ack_detected(self):
        # Frame ACK real capturado: F0 00 32 01 08 00 00 00 00 7F 01 F7
        ack = bytes([0xF0, 0x00, 0x32, 0x01, 0x08, 0x00, 0x00, 0x00, 0x00, 0x7F, 0x01, 0xF7])
        assert is_ack_frame(ack)

    def test_non_ack_not_detected(self):
        # Frame de read não é ACK
        frame = build_read_frame(SPACE_EDIT_BUFFER, 0, 448)
        assert not is_ack_frame(frame)

    def test_empty_not_ack(self):
        assert not is_ack_frame(b"")
