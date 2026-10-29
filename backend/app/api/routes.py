"""Rotas da API REST do AI Tone Studio."""
import os
import logging
import uuid
import asyncio
from io import BytesIO
from pathlib import Path
from typing import Optional
import tempfile
import shutil

from fastapi import APIRouter, File, Form, UploadFile, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse, PlainTextResponse

from ..models.devices import DeviceModel
from ..models.audio import MusicTrack
from ..models.preset import PresetPair
from ..core.pipeline import ToneAnalysisPipeline
from ..core.storage import save_record, load_record

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1")

# Cache em memória; resultados concluídos também são persistidos em SQLite.
_jobs: dict[str, dict] = {}
_presets: dict[str, PresetPair] = {}
_analyses: dict[str, dict] = {}  # análise estruturada por pair_id

# Tamanho máximo de upload: 50 MB
MAX_FILE_SIZE = int(os.environ.get("MAX_UPLOAD_MB", "50")) * 1024 * 1024

# Formatos aceitos
ALLOWED_FORMATS = {".mp3", ".wav", ".flac", ".ogg", ".m4a", ".m4", ".mp4"}

# Diretório de catálogos
CATALOGS_DIR = Path(os.environ.get("CATALOGS_DIR", str(Path(__file__).parent.parent.parent.parent / "catalogs")))


def _get_pipeline() -> ToneAnalysisPipeline:
    return ToneAnalysisPipeline(catalogs_dir=CATALOGS_DIR)


@router.get("/health")
async def health():
    """Health check."""
    return {"status": "ok", "service": "AI Tone Studio API", "version": "1.5.4"}


@router.get("/devices")
async def list_devices():
    """Lista dispositivos suportados e status do catálogo."""
    from ..services.device_catalog.loader import CatalogLoader
    loader = CatalogLoader(catalogs_dir=CATALOGS_DIR)

    devices = []
    for model in DeviceModel:
        if model == DeviceModel.UNKNOWN:
            continue
        devices.append({
            "model": model.value,
            "supported": loader.is_supported(model),
            "catalog_version": loader.get_catalog_version(model),
        })
    return {"devices": devices}


@router.post("/analyze")
async def analyze_audio(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    rhythm_device: str = Form("MK300"),
    lead_device: str = Form("MK300"),
    artist: Optional[str] = Form(None),
    song_title: Optional[str] = Form(None),
    source_kind: str = Form("mix"),
    excerpt_start: float = Form(0),
    excerpt_duration: Optional[float] = Form(None),
    engine_mode: str = Form("legacy"),
    lead_start: Optional[float] = Form(None),
    lead_duration: Optional[float] = Form(None),
    analyze_states: bool = Form(False),
    reference_version: str = Form("unknown"),
):
    """
    Inicia análise assíncrona de áudio e geração de presets.
    Retorna job_id para polling de status.
    """
    import math
    if reference_version not in {"unknown","studio","live","acoustic"}:
        raise HTTPException(400,"Versão de referência inválida")
    if engine_mode not in {'legacy','guitar_v2'}:
        raise HTTPException(400, "Motor de análise inválido")
    if (lead_start is None) != (lead_duration is None):
        raise HTTPException(400, "Informe início e duração do trecho solo")
    if lead_start is not None and (not math.isfinite(lead_start) or not 0<=lead_start<=7200 or not math.isfinite(lead_duration) or not 3<=lead_duration<=120):
        raise HTTPException(400, "Trecho solo inválido")
    if source_kind not in {"mix", "isolated"}:
        raise HTTPException(400, "Tipo de referência inválido")
    if not math.isfinite(excerpt_start) or not 0 <= excerpt_start <= 7200:
        raise HTTPException(400, "Início do trecho deve estar entre 0 e 7200 segundos")
    if excerpt_duration is not None and (not math.isfinite(excerpt_duration) or not 3 <= excerpt_duration <= 120):
        raise HTTPException(400, "Duração do trecho deve estar entre 3 e 120 segundos")
    if excerpt_start != 0 and excerpt_duration is None:
        raise HTTPException(400, "Informe a duração para analisar um trecho")
    # Mantém o título informado; usa o nome original do arquivo como fallback.
    original_name = (file.filename or "").replace("\\", "/").rsplit("/", 1)[-1]
    song_title = (song_title or "").strip() or Path(original_name).stem or "Música importada"
    artist = (artist or "").strip() or None

    # Validação do arquivo
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in ALLOWED_FORMATS:
        raise HTTPException(400, f"Formato não suportado: {suffix}. Aceitos: {ALLOWED_FORMATS}")

    # Lê bytes antes do background task (FastAPI fecha o file após a request)
    chunks = []
    size = 0
    while chunk := await file.read(1024 * 1024):
        size += len(chunk)
        if size > MAX_FILE_SIZE:
            raise HTTPException(413, f"Arquivo muito grande. Máximo: {MAX_FILE_SIZE // 1024 // 1024} MB")
        chunks.append(chunk)
    file_bytes = b"".join(chunks)
    if len(file_bytes) == 0:
        raise HTTPException(400, "Arquivo vazio")

    # Valida dispositivos
    try:
        rhythm_dev = DeviceModel(rhythm_device)
        lead_dev = DeviceModel(lead_device)
        if DeviceModel.UNKNOWN in (rhythm_dev, lead_dev):
            raise ValueError("Dispositivo desconhecido")
    except ValueError:
        raise HTTPException(400, f"Dispositivo inválido. Opções: {[d.value for d in DeviceModel if d != DeviceModel.UNKNOWN]}")

    job_id = str(uuid.uuid4())
    _jobs[job_id] = {
        "job_id": job_id,
        "status": "queued",
        "progress_percent": 0,
        "progress": "Aguardando processamento...",
        "rhythm_device": rhythm_device,
        "lead_device": lead_device,
        "artist": artist,
        "song_title": song_title,
    }

    save_record("job", job_id, _jobs[job_id])

    # Processa em background
    background_tasks.add_task(
        _run_analysis_job,
        job_id, file_bytes, suffix, rhythm_dev, lead_dev, artist, song_title, original_name, source_kind, excerpt_start, excerpt_duration, engine_mode, lead_start, lead_duration, None, analyze_states, reference_version
    )

    return {"job_id": job_id, "status": "queued"}


async def _run_analysis_job(
    job_id: str,
    file_bytes: bytes,
    suffix: str,
    rhythm_device: DeviceModel,
    lead_device: DeviceModel,
    artist: Optional[str],
    song_title: Optional[str],
    original_name: Optional[str] = None,
    source_kind: str = "mix",
    excerpt_start: float = 0,
    excerpt_duration: Optional[float] = None,
    engine_mode: str = "legacy",
    lead_start: Optional[float] = None,
    lead_duration: Optional[float] = None,
    cached_sources=None,
    analyze_states=False,
    reference_version="unknown",
):
    """Executa o pipeline de análise em background."""
    work_dir = Path(tempfile.mkdtemp(prefix=f"toneai_{job_id[:8]}_"))
    try:
        _jobs[job_id]["status"] = "processing"
        _jobs[job_id]["progress"] = "Preparando arquivo de áudio..."

        # Salva arquivo temporário
        audio_path = work_dir / f"input{suffix}"
        audio_path.write_bytes(file_bytes)
        input_sha256 = None
        if engine_mode == 'guitar_v2':
            from ..core.storage import data_directory
            import hashlib
            input_sha256 = hashlib.sha256(file_bytes).hexdigest()
            originals = data_directory()/'generation_inputs'
            originals.mkdir(parents=True,exist_ok=True)
            preserved = originals/(input_sha256+suffix)
            # Mesmo conteúdo reaproveitado; escrita exclusiva impede sobrescrever.
            try:
                with preserved.open('xb') as output:
                    output.write(file_bytes)
            except FileExistsError:
                if hashlib.sha256(preserved.read_bytes()).hexdigest()!=input_sha256:
                    raise ValueError('Original preservado está corrompido; confira o backend.')

        _jobs[job_id]["progress"] = "Analisando áudio e gerando presets..."
        _jobs[job_id]["progress_percent"] = 10

        pipeline = _get_pipeline()
        def progress(percent, message):
            _jobs[job_id].update(progress_percent=max(percent,_jobs[job_id].get("progress_percent",0)), progress=message)
        analysis, preset_pair = await pipeline.process(
            audio_path=audio_path,
            rhythm_device=rhythm_device,
            lead_device=lead_device,
            artist=artist,
            song_title=song_title,
            source_kind=source_kind,
            excerpt_start=excerpt_start,
            excerpt_duration=excerpt_duration,
            engine_mode=engine_mode, lead_start=lead_start, lead_duration=lead_duration, progress=progress, cached_sources=cached_sources,
        )

        if input_sha256:
            analysis.engine_diagnostics['original_sha256'] = input_sha256
        preset_pair.rhythm_preset.source_file_name = original_name
        preset_pair.lead_preset.source_file_name = original_name

        # Salva resultado
        pair_id = str(preset_pair.rhythm_preset.id)
        _presets[pair_id] = preset_pair
        _analyses[pair_id] = {
            "tone_reference": analysis.reference_profile,
            "engine_diagnostics": analysis.engine_diagnostics,
            "gain_character": analysis.effect_estimates.gain_character.value,
            "confidence": analysis.overall_confidence.value,
            "distortion_level": analysis.effect_estimates.distortion_level,
            "estimated_bpm": analysis.bpm_estimate,
            "spectral_profile": {
                "low": analysis.overall_spectral.bass_energy,
                "low_mid": analysis.overall_spectral.low_mid_energy,
                "mid": analysis.overall_spectral.mid_energy,
                "high_mid": analysis.overall_spectral.high_mid_energy,
                "high": analysis.overall_spectral.treble_energy,
                "brightness": analysis.overall_spectral.brightness,
            },
            "effect_presence": {
                "reverb_probability": analysis.effect_estimates.reverb_present,
                "delay_probability": analysis.effect_estimates.delay_present,
            },
        }

        for role, profile in analysis.engine_diagnostics.get('reference_profiles',{}).items():
            import json
            save_record('comparison_reference',json.dumps([pair_id,role]), {'profile':profile})
        save_record("pair", pair_id, {"pair": preset_pair.model_dump(mode="json"), "analysis": _analyses[pair_id]})

        if analyze_states and analysis.source_separation_available:
            _jobs[job_id].update(progress_percent=90,progress='Detectando mudanças de timbre e pesquisando fontes...')
            try:
                from .tone_states import analyze_states as detect_tone_states
                await asyncio.to_thread(detect_tone_states,pair_id,reference_version)
            except Exception:
                logger.exception('Não foi possível completar estados/pesquisa; presets e áudio preservados')
                analysis.limitations.append('Análise adicional de estados indisponível. Tente novamente na tela de presets.')

        _jobs[job_id].update({
            "status": "completed",
            "progress_percent": 100,
            "progress": "Concluído",
            "pair_id": pair_id,
            "analysis_confidence": analysis.overall_confidence.value,
            "bpm": analysis.bpm_estimate,
            "limitations": analysis.limitations,
        })

    except ValueError as e:
        logger.warning(f"Erro de validação no job {job_id}: {e}")
        _jobs[job_id].update({"status": "failed", "error": str(e), "error_message": str(e)})
    except Exception as e:
        logger.exception(f"Erro no job {job_id}: {e}")
        _jobs[job_id].update({"status": "failed", "error": "Erro interno no processamento. Tente novamente.", "error_message": "Erro interno no processamento. Tente novamente."})
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
        save_record("job", job_id, _jobs[job_id])


@router.get("/jobs/{job_id}")
async def get_job_status(job_id: str):
    """Consulta status de um job de análise."""
    if job_id not in _jobs:
        saved = load_record("job", job_id)
        if saved is None:
            raise HTTPException(404, "Job não encontrado")
        if saved["status"] in {"queued", "processing"}:
            saved.update(status="failed", error_message="Processamento interrompido pelo reinício do servidor. Importe a música novamente.")
            save_record("job", job_id, saved)
        _jobs[job_id] = saved
    return _jobs[job_id]


def _ensure_pair(pair_id: str):
    if pair_id not in _presets:
        saved = load_record("pair", pair_id)
        if saved is None:
            raise HTTPException(404, "Preset não encontrado")
        _presets[pair_id] = PresetPair.model_validate(saved["pair"])
        _analyses[pair_id] = saved["analysis"]


def _comparison_profile(pair_id: str, preset: dict):
    """Usa somente perfil de áudio real, nunca parâmetros do pedal como áudio."""
    metadata = preset.get("generation_metadata", {})
    parent = metadata.get("source_pair_id") if isinstance(metadata, dict) else None
    ids = [pair_id] + ([parent] if isinstance(parent, str) and parent != pair_id else [])
    for candidate_id in ids:
        import json
        try:
            from ..core.reference_library import reference_info,select_region
            info=reference_info(candidate_id,preset.get('role'))
            if info['needs_region']:
                raise HTTPException(400,{'code':'reference_region_required','message':'Salve uma vez o trecho da guitarra base ou solo já separado antes de comparar.'})
            selected=load_record('comparison_reference',json.dumps([candidate_id,preset.get('role')])) or {}
            if info['selection_saved'] and any(selected.get(key)!=info.get(key) for key in ['cache_id','start_seconds','duration_seconds']):
                select_region(candidate_id,preset.get('role'),info['start_seconds'],info['duration_seconds'],register=False)
        except (ValueError,OSError,KeyError):
            pass  # Análises antigas mantêm seu perfil original; nunca inventar guitarra.
        excerpt = load_record("comparison_reference", json.dumps([candidate_id, preset.get("role")]))
        if excerpt and excerpt.get("profile"):
            return excerpt["profile"], candidate_id, "saved_excerpt_profile"
        analysis = _analyses.get(candidate_id)
        if analysis is None:
            saved = load_record("pair", candidate_id)
            analysis = saved.get("analysis", {}) if saved else {}
        profile = analysis.get("tone_reference")
        if profile:
            return profile, candidate_id, "saved_track_profile"
    raise HTTPException(400, detail={"code": "reference_required", "message":
        "Este preset está na biblioteca local, mas não há perfil de áudio da música no backend. "
        "Selecione o áudio original e o início do trecho para analisar e sugerir ajustes. "
        "A referência de configurações do pedal não substitui o áudio original."})


def _serialize_preset(preset) -> dict:
    """Serializa Preset no formato esperado pelo app Flutter."""
    return {
        "id": str(preset.id),
        "name": preset.name,
        "device": preset.device_model.value,
        "catalog_version": preset.catalog_version,
        "bpm": preset.bpm,
        "generation_metadata": preset.generation_metadata,
        "preset_volume": preset.preset_volume,
        "role": preset.role.value,
        "analysis_confidence": preset.overall_confidence.value,
        "artist": preset.artist or "",
        "song_title": preset.song_title or "",
        "source_file_name": preset.source_file_name or "",
        "effect_chain": [
            {
                "slot": str(block.slot),
                "effect_type": block.effect_type.value,
                "model_id": block.model_id,
                "model_name": block.model_name,
                "enabled": block.enabled,
                "parameters": {p.name: p.raw_value for p in block.parameters},
                "parameter_specs": {p.name: {"min": p.min_value, "max": p.max_value, "step": p.step, "unit": p.unit} for p in block.parameters},
                "generated_confidence": block.generated_confidence.value,
                "generation_rationale": block.generation_rationale,
            }
            for block in preset.effect_chain.blocks
        ],
    }


@router.get("/presets/{pair_id}")
async def get_preset_pair(pair_id: str):
    """Retorna par de presets gerados."""
    _ensure_pair(pair_id)
    pair = _presets[pair_id]
    return {
        "id": pair_id,
        "rhythm_preset": _serialize_preset(pair.rhythm_preset),
        "lead_preset": _serialize_preset(pair.lead_preset),
        "analysis_summary": pair.analysis_summary,
        "analysis": _analyses.get(pair_id, {}),
    }


@router.get("/presets/{pair_id}/stems/{role}/{instrument}")
async def download_stem(pair_id: str, role: str, instrument: str):
    from fastapi.responses import FileResponse
    from ..core.storage import data_directory
    import hashlib
    if role not in {'rhythm','lead'} or instrument not in {'guitar','vocals','bass','drums','other','piano'}:
        raise HTTPException(400, 'Instrumento ou função inválida')
    _ensure_pair(pair_id)
    diagnostics = _analyses[pair_id].get('engine_diagnostics',{})
    if role == 'lead' and not diagnostics.get('lead',{}).get('same_region'):
        diagnostics = diagnostics.get('lead',{})
    separation = diagnostics.get('separation') or {}
    key = separation.get('cache_id','')
    if len(key)!=64 or any(c not in '0123456789abcdef' for c in key):
        raise HTTPException(404, 'Esta análise não possui instrumentos separados')
    path = data_directory()/'separations'/key/f'{instrument}.wav'
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=separation.get('stem_sha256',{}).get(instrument):
        raise HTTPException(404, 'Instrumento indisponível ou arquivo alterado')
    return FileResponse(path, media_type='audio/wav',filename=f'{role}-{instrument}.wav')


@router.get("/presets/{pair_id}/candidates/{role}")
async def get_candidates(pair_id: str, role: str):
    from ..models.preset import Preset
    if role not in {'rhythm','lead'}:
        raise HTTPException(400,'Função inválida')
    _ensure_pair(pair_id)
    candidates = _analyses[pair_id].get('engine_diagnostics',{}).get('candidates',{}).get(role,[])
    return {'candidates':[_serialize_preset(Preset.model_validate(p)) for p in candidates],
            'ranking':'Alternativas da mesma família do catálogo, sem ranking de fidelidade sonora.'}


@router.get("/presets/{pair_id}/export/json")
async def export_preset_json(pair_id: str):
    """Exporta par de presets como JSON para hardware."""
    _ensure_pair(pair_id)
    pair = _presets[pair_id]
    return {
        "rhythm": pair.rhythm_preset.to_device_json(),
        "lead": pair.lead_preset.to_device_json(),
    }


@router.get("/presets/{pair_id}/export/guide", response_class=PlainTextResponse)
async def export_preset_guide(pair_id: str):
    """Exporta guia legível para configuração manual da pedaleira."""
    _ensure_pair(pair_id)
    pair = _presets[pair_id]
    guide = "=== AI TONE STUDIO — GUIA DE CONFIGURAÇÃO MANUAL ===\n\n"
    guide += pair.rhythm_preset.to_readable_guide()
    guide += "\n\n" + "=" * 50 + "\n\n"
    guide += pair.lead_preset.to_readable_guide()
    return guide


@router.post("/presets/{pair_id}/regenerate/{role}")
async def regenerate_preset(pair_id: str, role: str):
    """
    Regenera um dos presets do par com ajuste de intenção.
    Fase futura: aceitar parâmetros de ajuste (mais drive, menos reverb, etc.)
    """
    raise HTTPException(501, "Regeneração disponível na Fase 2")

@router.post('/compare-tone')
async def compare_tone(
    file: UploadFile = File(...),
    preset_json: str = Form(...),
    pair_id: str = Form(...),
    input_kind: str = Form('usb'),
    reference_file: Optional[UploadFile] = File(None),
    reference_start: float = Form(0),
    reference_kind: str = Form('mix'),
):
    """Compara gravação curta com trecho original ou perfil DSP salvo; não grava no pedal."""
    import json
    import math
    from ..services.audio_analysis.tone_comparison import measure, compare
    from ..core.recordings import archive_recording, finish_recording
    from ..services.device_catalog.loader import CatalogLoader
    if input_kind not in {'usb','microphone','file'} or reference_kind not in {'mix','isolated'}:
        raise HTTPException(400,'Tipo de captura/referência inválido.')
    if not math.isfinite(reference_start) or not 0<=reference_start<=7200:
        raise HTTPException(400,'Início do trecho deve estar entre 0 e 7200 segundos.')
    if len(preset_json)>100_000:raise HTTPException(400,'Preset muito grande.')
    try: preset=json.loads(preset_json)
    except ValueError:raise HTTPException(400,'Preset JSON inválido.')
    if not isinstance(preset,dict):raise HTTPException(400,'Preset inválido.')
    if not 1 <= len(pair_id) <= 200 or preset.get('role') not in {'rhythm', 'lead'}:
        raise HTTPException(400, 'Análise ou função do preset inválida.')
    work_dir=Path(tempfile.mkdtemp(prefix='tone_comparison_'))
    recording_id = None
    recorded = None
    reference = None
    def capture_error(status, detail):
        if recording_id is None:
            raise HTTPException(status, detail)
        try:
            finish_recording(recording_id, error=detail, measured=recorded)
        except Exception:
            logger.exception('Falha ao atualizar estado da gravação preservada')
        return JSONResponse(status_code=status, content={'detail': detail,
            'recording_id': recording_id, 'recording_saved': True})
    async def save_upload(upload, name, limit):
        suffix=Path(upload.filename or '').suffix.lower()
        if suffix not in ALLOWED_FORMATS:raise HTTPException(400,'Formato de áudio não suportado.')
        path=work_dir/(name+suffix)
        total=0
        with path.open('wb') as out:
            while chunk:=await upload.read(1024*1024):
                total+=len(chunk)
                if total>limit:raise HTTPException(413,'Arquivo acima do limite de upload.')
                out.write(chunk)
        if total==0:raise HTTPException(400,'Arquivo vazio.')
        return path
    try:
        recording_path=await save_upload(file,'recording',10*1024*1024)
        recording_id = archive_recording(recording_path, pair_id, preset, input_kind, file.filename)
        recorded=await asyncio.to_thread(measure,recording_path)
        if recorded['duration_seconds']>30.1:raise HTTPException(400,'A gravação deve ter entre 3 e 30 segundos.')
        if reference_file is not None:
            reference_path=await save_upload(reference_file,'reference',MAX_FILE_SIZE)
            reference=await asyncio.to_thread(measure,reference_path,reference_start,recorded['duration_seconds'])
            if reference['duration_seconds']+0.3<recorded['duration_seconds']:
                raise HTTPException(400,'O trecho original termina antes da gravação. Escolha outro início de trecho.')
            source='selected_excerpt'
        else:
            reference, reference_pair_id, source = _comparison_profile(pair_id, preset)
            reference_kind=reference.get('source_kind','mix')
        result=await asyncio.to_thread(compare,reference,recorded,preset,CatalogLoader(CATALOGS_DIR),input_kind,reference_kind)
        result['reference_source']=source
        if source != 'selected_excerpt':result['reference_pair_id']=reference_pair_id
        if source == 'selected_excerpt':
            import hashlib
            save_record('comparison_reference', json.dumps([pair_id, preset.get('role')]), {
                'profile': {**reference, 'source_kind': reference_kind},
                'original_file_name': reference_file.filename,
                'original_file_sha256': hashlib.sha256(reference_path.read_bytes()).hexdigest(),
                'start_seconds': reference_start, 'duration_seconds': recorded['duration_seconds']})
        if source=='saved_track_profile':result['limitations'].append('Comparação com o perfil geral da música, não com o mesmo trecho. Selecione o áudio original e o início do trecho para uma referência mais útil.')
        if source=='saved_excerpt_profile':result['limitations'].append('Comparação com o perfil do trecho original salvo para esta função. Toque a mesma passagem; selecione novamente o áudio original se mudar de trecho.')
        result['recording_id'] = recording_id
        result['recording_saved'] = True
        result['recording_audio_url'] = f'/api/v1/recordings/{recording_id}/audio'
        finish_recording(recording_id, result=result, measured=recorded, reference=reference)
        return result
    except HTTPException as error:return capture_error(error.status_code, error.detail)
    except (ValueError,KeyError,TypeError) as error:return capture_error(400,str(error))
    except Exception:
        logger.exception('Falha na comparação de timbre')
        return capture_error(422,'Não foi possível ler/comparar os áudios. Confira os arquivos e grave novamente.')
    finally:
        shutil.rmtree(work_dir,ignore_errors=True)
