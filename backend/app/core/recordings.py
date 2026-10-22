"""Preserva bytes originais da captura e o contexto declarado pelo aplicativo."""
import hashlib
import json
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path

from .storage import data_directory, load_record, save_record, _connect

KIND = 'guitar_recording'


def archive_recording(path: Path, pair_id: str, preset: dict, input_kind: str, original_name: str):
    content = path.read_bytes()
    digest = hashlib.sha256(content).hexdigest()
    identity = json.dumps([digest, pair_id, preset, input_kind, path.suffix.lower()], sort_keys=True, allow_nan=False)
    recording_id = str(uuid.uuid5(uuid.NAMESPACE_URL, identity))
    directory = data_directory() / 'recordings'
    directory.mkdir(parents=True, exist_ok=True)
    filename = recording_id + path.suffix.lower()
    destination = directory / filename
    created = not destination.exists()
    if created:
        temporary = directory / (str(uuid.uuid4()) + '.tmp')
        try:
            temporary.write_bytes(content)
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)
    if hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
        raise OSError('Arquivo de gravação não corresponde ao conteúdo recebido')
    previous = load_record(KIND, recording_id) or {}
    now = datetime.now(timezone.utc).isoformat()
    record = {**previous, 'id': recording_id, 'pair_id': pair_id, 'role': preset['role'],
              'input_kind': input_kind, 'submitted_preset': preset,
              'original_file_name': (original_name or '').replace('\\', '/').rsplit('/', 1)[-1],
              'file_name': filename, 'sha256': digest, 'size_bytes': len(content),
              'created_at': previous.get('created_at', now), 'updated_at': now,
              'status': 'received', 'last_error': None,
              'audio_url': f'/api/v1/recordings/{recording_id}/audio'}
    try:
        save_record(KIND, recording_id, record)
    except Exception:
        if created:
            destination.unlink(missing_ok=True)
        raise
    return recording_id


def finish_recording(recording_id, *, result=None, error=None, measured=None, reference=None):
    record = load_record(KIND, recording_id)
    if record is None:
        raise ValueError('Gravação não encontrada')
    record['updated_at'] = datetime.now(timezone.utc).isoformat()
    record['last_error'] = error
    record['status'] = 'completed' if error is None else (
        'needs_reference' if isinstance(error, dict) and error.get('code') == 'reference_required' else 'failed')
    if result is not None:
        record['analysis_result'] = result
    if measured is not None:
        record['measured_recording'] = measured
    if reference is not None:
        record['reference_profile'] = reference
    save_record(KIND, recording_id, record)


def list_recordings(pair_id=None, role=None, limit=100):
    query = 'SELECT data FROM records WHERE kind=?'
    params = [KIND]
    for field, value in [('pair_id', pair_id), ('role', role)]:
        if value is not None:
            query += f" AND json_extract(data, '$.{field}')=?"
            params.append(value)
    query += " ORDER BY json_extract(data, '$.created_at') DESC, id LIMIT ?"
    params.append(limit)
    with _connect() as connection:
        rows = connection.execute(query, params).fetchall()
    return [json.loads(row[0]) for row in rows]
