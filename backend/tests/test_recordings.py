import hashlib
import json
import copy
import numpy as np
from app.api import routes
from app.core.storage import load_record, save_record, data_directory
from tests.test_v1_flow import client
from tests.test_tone_comparison import preset, wav, guitar


def request(client, content, original=False, pair='local-recording', selected=None):
    files = {'file': ('usb-mk300.wav', content)}
    if original:
        files['reference_file'] = ('original.wav', wav(guitar()))
    return client.post('/api/v1/compare-tone',
        data={'pair_id': pair, 'input_kind': 'usb', 'preset_json': json.dumps(selected or preset())}, files=files)


def test_archive_exact_usb_audio_and_context_survive_restart(client):
    content = wav(guitar(3))
    selected = preset()
    response = request(client, content, original=True, selected=selected)
    assert response.status_code == 200, response.text
    result = response.json()
    assert result['recording_saved'] is True
    recording_id = result['recording_id']
    routes._analyses.clear()
    routes._presets.clear()
    record = client.get(f'/api/v1/recordings/{recording_id}').json()
    assert record['status'] == 'completed'
    assert record['input_kind'] == 'usb'
    assert record['submitted_preset'] == selected
    assert record['sha256'] == hashlib.sha256(content).hexdigest()
    assert record['size_bytes'] == len(content)
    assert record['analysis_result'] == result
    assert record['reference_profile'] and record['measured_recording']
    assert client.get(result['recording_audio_url']).content == content
    assert len(client.get('/api/v1/recordings?pair_id=local-recording&role=lead').json()['recordings']) == 1
    assert client.get('/api/v1/recordings?role=rhythm').json()['recordings'] == []


def test_failed_missing_reference_is_kept_and_retry_reuses_capture(client):
    content = wav(guitar())
    selected = preset()
    missing = request(client, content, selected=selected)
    assert missing.status_code == 400
    assert missing.json()['detail']['code'] == 'reference_required'
    recording_id = missing.json()['recording_id']
    assert missing.json()['recording_saved'] is True
    assert load_record('guitar_recording', recording_id)['status'] == 'needs_reference'
    success = request(client, content, original=True, selected=selected)
    assert success.status_code == 200, success.text
    assert success.json()['recording_id'] == recording_id
    assert load_record('guitar_recording', recording_id)['status'] == 'completed'
    assert len(client.get('/api/v1/recordings').json()['recordings']) == 1
    changed = copy.deepcopy(selected)
    next(b for b in changed['effect_chain'] if b['effect_type'] == 'amp')['parameters']['Gain'] += 1
    request(client, content, selected=changed)
    assert len(client.get('/api/v1/recordings').json()['recordings']) == 2


def test_silent_and_clipped_audio_are_preserved_for_diagnosis(client):
    silent = wav(np.zeros(22050 * 4))
    failed = request(client, silent)
    assert failed.status_code == 400 and 'baixa' in failed.json()['detail']
    recording_id = failed.json()['recording_id']
    assert load_record('guitar_recording', recording_id)['status'] == 'failed'
    assert client.get(f'/api/v1/recordings/{recording_id}/audio').content == silent
    clipped = request(client, wav(np.ones(22050 * 4)), original=True)
    assert clipped.status_code == 200 and clipped.json()['quality'] == 'clipped'
    assert clipped.json()['recording_saved'] is True


def test_invalid_empty_or_oversized_upload_does_not_create_archive(client):
    for filename, content, status in [('empty.wav', b'', 400),
                                      ('invalid.exe', b'abc', 400),
                                      ('big.wav', b'0' * (10 * 1024 * 1024 + 1), 413)]:
        response = client.post('/api/v1/compare-tone',
            data={'pair_id': 'empty', 'preset_json': json.dumps(preset())},
            files={'file': (filename, content)})
        assert response.status_code == status
        assert 'recording_id' not in response.json()
    assert client.get('/api/v1/recordings').json()['recordings'] == []


def test_download_checks_integrity_and_limits_path_to_archive(client):
    result = request(client, wav(guitar()), original=True).json()
    recording_id = result['recording_id']
    record = load_record('guitar_recording', recording_id)
    (data_directory() / 'recordings' / record['file_name']).write_bytes(b'corrupted')
    assert client.get(result['recording_audio_url']).status_code == 409
    record['file_name'] = '../tone-studio.sqlite3'
    save_record('guitar_recording', recording_id, record)
    assert client.get(result['recording_audio_url']).status_code == 404
    assert client.get('/api/v1/recordings/not-a-uuid').status_code == 400
