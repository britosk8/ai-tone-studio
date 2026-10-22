import io
import json
import numpy as np
import pytest
import soundfile as sf
from app.services.audio_analysis.tone_comparison import fingerprint,compare
from app.services.device_catalog.loader import CatalogLoader
from app.models.devices import DeviceModel
from app.services.preset_generation.compiler import PresetCompiler
from app.api.routes import _serialize_preset
from tests.test_preset_generation import make_analysis,CATALOGS_DIR
from tests.test_v1_flow import client

def guitar(bass=1):
    t=np.arange(22050*4)/22050
    return 0.12*(bass*np.sin(2*np.pi*110*t)+np.sin(2*np.pi*880*t)+0.6*np.sin(2*np.pi*4000*t))

def preset():
    compiler=PresetCompiler(CatalogLoader(CATALOGS_DIR))
    return _serialize_preset(compiler.compile_pair(make_analysis(),DeviceModel.MK300,DeviceModel.MK300).lead_preset)

def wav(data):
    file=io.BytesIO();sf.write(file,data,22050,format='WAV');return file.getvalue()

def test_same_tone_different_capture_gain_no_adjustments():
    reference=fingerprint(guitar())
    result=compare(reference,fingerprint(guitar()*0.5),preset(),CatalogLoader(CATALOGS_DIR))
    assert result['suggestions']==[]
    assert all(abs(value)<0.01 for value in result['differences_db'].values())
    assert 'similarity' not in result

def test_excess_bass_suggests_bounded_reduction():
    result=compare(fingerprint(guitar()),fingerprint(guitar(bass=3)),preset(),CatalogLoader(CATALOGS_DIR))
    bass=next(s for s in result['suggestions'] if s['parameter']=='Bass')
    assert bass['after']<bass['before']
    assert bass['min']<=bass['after']<=bass['max']
    assert result['confidence']=='low'

def test_clipping_blocks_adjustments():
    result=compare(fingerprint(guitar()),fingerprint(np.ones(22050*4)),preset(),CatalogLoader(CATALOGS_DIR))
    assert result['quality']=='clipped' and result['suggestions']==[]

def test_unknown_amp_and_old_catalog_rejected():
    current=preset();current['catalog_version']='0.3.0'
    with pytest.raises(ValueError):compare(fingerprint(guitar()),fingerprint(guitar()),current,CatalogLoader(CATALOGS_DIR))
    current=preset();next(b for b in current['effect_chain'] if b['effect_type']=='amp')['model_id']='9999'
    with pytest.raises(ValueError):compare(fingerprint(guitar()),fingerprint(guitar()),current,CatalogLoader(CATALOGS_DIR))

def test_compare_endpoint_with_original_file_and_silent_recording(client):
    response=client.post('/api/v1/compare-tone',data={'pair_id':'local-pair','preset_json':json.dumps(preset()),'input_kind':'usb'},
        files={'file':('guitar.wav',wav(guitar(3))),'reference_file':('original.wav',wav(guitar()))})
    assert response.status_code==200,response.text
    assert response.json()['reference_source']=='selected_excerpt'
    assert response.json()['suggestions']
    invalid=client.post('/api/v1/compare-tone',data={'pair_id':'local-pair','preset_json':json.dumps(preset())},
        files={'file':('silent.wav',wav(np.zeros(22050*4)))})
    assert invalid.status_code==400 and 'baixa' in invalid.json()['detail']
