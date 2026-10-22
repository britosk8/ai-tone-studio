"""Vectores de M-EFCS registrados em jpfaria/mvave (MIT)."""
from pathlib import Path
import pytest
from app.transport import protocol_mk300 as p
from app.transport import sysex_codec as codec

@pytest.mark.parametrize('built,expected', [
 (p.build_read_frame(1,0,448),'f0 00 32 0d 41 00 00 00 02 00 00 00 00 01 38 00 00 2a 00 f7'),
 (p.build_read_frame(2,0,86),'f0 00 32 0d 41 00 00 00 02 00 00 00 00 62 0a 00 00 05 01 f7'),
 (p.build_write_u16_frame(1,26,133),'f0 00 32 09 51 00 00 00 02 1a 00 00 00 21 00 00 00 05 01 28 02 f7'),
 (p.build_commit_frame(),'f0 00 32 09 41 00 00 00 02 00 00 00 00 0f 00 00 00 0b 00 f7'),
])
def test_captured_frames(built,expected):
 assert built == bytes.fromhex(expected)
 frame=codec.parse(built)
 assert codec.build(frame.cls,frame.cmd,frame.field,frame.length,frame.space,frame.payload)==built

def test_flash_image_and_full_byte_encoding():
 image=bytes.fromhex((Path(__file__).parent/'fixtures/mk300-jm-od.hex').read_text())
 frame=codec.write_preset_image(159,image)
 assert len(frame)==532
 assert codec.parse(frame).payload==image
 data=bytes(range(256))
 assert codec.unpack7(codec.pack7(data))==data
