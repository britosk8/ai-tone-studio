import hashlib
import uuid
import mimetypes
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse
from ..core.storage import load_record, data_directory
from ..core.recordings import KIND, list_recordings

router = APIRouter(prefix='/api/v1')


def get_record(recording_id: str):
    try:
        uuid.UUID(recording_id)
    except ValueError as error:
        raise HTTPException(400, 'Identificador de gravação inválido') from error
    record = load_record(KIND, recording_id)
    if record is None:
        raise HTTPException(404, 'Gravação não encontrada')
    return record


@router.get('/recordings')
async def recordings(pair_id: str | None = None, role: str | None = None,
                     limit: int = Query(100, ge=1, le=100)):
    if role is not None and role not in {'rhythm', 'lead'}:
        raise HTTPException(400, 'Função inválida')
    return {'recordings': list_recordings(pair_id, role, limit)}


@router.get('/recordings/{recording_id}')
async def recording(recording_id: str):
    return get_record(recording_id)


@router.get('/recordings/{recording_id}/audio')
async def audio(recording_id: str):
    record = get_record(recording_id)
    directory = (data_directory() / 'recordings').resolve()
    path = (directory / record['file_name']).resolve()
    if not path.is_relative_to(directory) or not path.is_file():
        raise HTTPException(404, 'Arquivo da gravação não disponível')
    if hashlib.sha256(path.read_bytes()).hexdigest() != record['sha256']:
        raise HTTPException(409, 'Integridade do arquivo não confirmada')
    return FileResponse(path, filename=record['original_file_name'] or path.name,
                        media_type=mimetypes.guess_type(path.name)[0] or 'application/octet-stream')
