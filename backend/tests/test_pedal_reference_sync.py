import base64
import copy
import json
import struct
from pathlib import Path

from app.api import routes
from app.core.storage import save_record
from app.services.audio_analysis.tone_comparison import fingerprint
from tests.test_v1_flow import client
from tests.test_tone_comparison import preset, guitar, wav


def payload():
    image = bytearray.fromhex((Path(__file__).parent / 'fixtures/mk300-jm-od.hex').read_text())
    image[:20] = b'Gohth' + bytes(15)
    image[54 + 6] = 0
    image[43 + 6] = 1
    struct.pack_into('<h', image, 66 + 24 * 6, -2)
    return {'reference': {'format': 'ai-tone-pedal-reference', 'version': 1, 'device': 'MK300',
        'slot': 10, 'connection': 'usb:test', 'captured_at': '2026-10-22T12:00:00Z',
        'image_base64': base64.b64encode(image).decode()}, 'generated_preset': preset()}


def test_sync_local_reference_is_idempotent_and_decoded_server_side(client):
    body = payload()
    for _ in range(2):
        response = client.put('/api/v1/presets/local-only/pedal-reference/lead', json=body)
        assert response.status_code == 200, response.text
    record = response.json()
    assert record['decoded_reference']['name'] == 'Gohth'
    eq = next(b for b in record['decoded_reference']['effect_chain'] if b['effect_type'] == 'eq')
    assert eq['parameters']['100Hz'] == -2
    assert record['generated_preset'] == body['generated_preset']
    assert any(row['label'] == 'Amplificador • modelo' for row in record['comparison'])
    assert any(row['reference'] == '-2' for row in record['comparison'])
    assert len(client.get('/api/v1/pedal-references').json()['references']) == 1
    routes._presets.clear()
    assert client.get('/api/v1/presets/local-only/pedal-reference/lead').json() == record
    assert client.get('/api/v1/presets/local-only').status_code == 404  # Não inventa análise de áudio.


def test_bad_reference_does_not_replace_saved_data(client):
    body = payload()
    url = '/api/v1/presets/local-only/pedal-reference/lead'
    assert client.put(url, json=body).status_code == 200
    for kind in ['image', 'slot', 'model', 'role']:
        bad = copy.deepcopy(body)
        if kind == 'image': bad['reference']['image_base64'] = 'bad'
        if kind == 'slot': bad['reference']['slot'] = 161
        if kind == 'model':
            image = bytearray(base64.b64decode(bad['reference']['image_base64']))
            image[54 + 4] = 255
            bad['reference']['image_base64'] = base64.b64encode(image).decode()
        if kind == 'role': bad['generated_preset']['role'] = 'rhythm'
        assert client.put(url, json=bad).status_code == 400
    assert client.get(url).json()['decoded_reference']['name'] == 'Gohth'
    newer = copy.deepcopy(body)
    newer['reference']['slot'] = 20
    newer['reference']['captured_at'] = '2026-10-22T13:00:00Z'
    assert client.put(url, json=newer).status_code == 200
    client.put(url, json=body)  # Retry antigo não sobrescreve importação recente.
    assert client.get(url).json()['reference']['slot'] == 20


def test_missing_local_pair_requests_original_instead_of_404_and_reuses_excerpt(client):
    data = {'pair_id': 'local-only', 'preset_json': json.dumps(preset())}
    files = {'file': ('capture.wav', wav(guitar(3)))}
    missing = client.post('/api/v1/compare-tone', data=data, files=files)
    assert missing.status_code == 400, missing.text
    assert missing.json()['detail']['code'] == 'reference_required'
    # Salvar os controles do pedal não inventa um perfil da música.
    client.put('/api/v1/presets/local-only/pedal-reference/lead', json=payload())
    assert client.post('/api/v1/compare-tone', data=data, files=files).status_code == 400
    selected = client.post('/api/v1/compare-tone', data=data,
        files={**files, 'reference_file': ('original.wav', wav(guitar()))})
    assert selected.status_code == 200, selected.text
    routes._analyses.clear()
    saved = client.post('/api/v1/compare-tone', data=data, files=files)
    assert saved.status_code == 200, saved.text
    assert saved.json()['reference_source'] == 'saved_excerpt_profile'
    assert saved.json()['suggestions']
    other = preset()
    other['role'] = 'rhythm'
    data['preset_json'] = json.dumps(other)
    assert client.post('/api/v1/compare-tone', data=data, files=files).status_code == 400


def test_candidate_uses_explicit_parent_audio_profile_after_restart(client):
    save_record('pair', 'parent', {'analysis': {'tone_reference': fingerprint(guitar())}})
    candidate = preset()
    candidate['generation_metadata'] = {'source_pair_id': 'parent'}
    result = client.post('/api/v1/compare-tone',
        data={'pair_id': 'local-candidate', 'preset_json': json.dumps(candidate)},
        files={'file': ('capture.wav', wav(guitar(3)))})
    assert result.status_code == 200, result.text
    assert result.json()['reference_source'] == 'saved_track_profile'
    assert result.json()['reference_pair_id'] == 'parent'
