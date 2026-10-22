"""Regressões de referência, confiança e solo limpo."""
import io
import numpy as np
import pytest
import soundfile as sf
from app.models.audio import ConfidenceLevel, GainCharacter
from app.models.devices import DeviceModel
from app.services.audio_analysis.analyzer import AudioAnalyzer
from tests.test_preset_generation import compiler, make_analysis
from tests.test_v1_flow import client


def test_clean_reference_does_not_force_distorted_lead(compiler):
    analysis = make_analysis(gain_char=GainCharacter.CLEAN, distortion=0.05)
    pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
    for preset in [pair.rhythm_preset, pair.lead_preset]:
        drives = [b for b in preset.effect_chain.blocks if b.effect_type.value == 'drive']
        assert all(not drive.enabled for drive in drives)
        amp = next(b for b in preset.effect_chain.blocks if b.effect_type.value == 'amp')
        assert amp.model_name == compiler.catalog.get_amp_model(DeviceModel.MK300, GainCharacter.CLEAN)['name']
        gate = next(b for b in preset.effect_chain.blocks if b.effect_type.value == 'noise_gate')
        assert gate.generated_confidence == ConfidenceLevel.SPECULATIVE
        assert 'não identificado' in gate.generation_rationale


def test_unreliable_chorus_suggestion_is_not_enabled(compiler):
    analysis = make_analysis()
    analysis.effect_estimates.chorus_present = True
    analysis.effect_estimates.chorus_confidence = ConfidenceLevel.LOW
    pair = compiler.compile_pair(analysis, DeviceModel.MK300, DeviceModel.MK300)
    modulation = next(b for b in pair.lead_preset.effect_chain.blocks if b.effect_type.value == 'modulation')
    assert not modulation.enabled


def test_changing_notes_do_not_prove_chorus():
    sr = 22050
    t = np.arange(sr * 4) / sr
    assert not AudioAnalyzer()._estimate_chorus(.2*np.sin(2*np.pi*(110*t+15*t**2)), sr)


@pytest.mark.parametrize('kind,seconds,clipped,expected', [
    ('mix', 12, False, 'low'), ('isolated', 12, False, 'medium'),
    ('isolated', 4, False, 'low'), ('isolated', 12, True, 'low'),
    ('separated_other', 12, False, 'low'),
])
def test_source_quality_does_not_claim_equipment_fidelity(tmp_path, kind, seconds, clipped, expected):
    sr = 22050
    t = np.arange(sr * seconds) / sr
    signal = .2 * np.sin(2*np.pi*110*t)
    if clipped:
        signal = np.clip(signal * 20, -1, 1)
    path = tmp_path / 'reference.wav'
    sf.write(path, signal, sr)
    result = AudioAnalyzer(source_separated_audio=signal if kind == 'separated_other' else None,
                           source_kind='mix' if kind == 'separated_other' else kind).analyze(path)
    assert result.overall_confidence.value == expected
    assert result.effect_estimates.reverb_confidence == ConfidenceLevel.LOW
    assert result.reference_profile['source_kind'] == ('isolated' if kind == 'isolated' else 'mix')
    assert any('não um percentual' in text for text in result.limitations)
    if kind == 'separated_other':
        assert any("'other'" in text for text in result.limitations)


def test_api_analyzes_selected_excerpt_preserving_original_name(client):
    sr = 22050
    t = np.arange(sr * 4) / sr
    audio = io.BytesIO()
    sf.write(audio, np.concatenate([.2*np.sin(2*np.pi*110*t), .2*np.sin(2*np.pi*3000*t)]), sr, format='WAV')
    response = client.post('/api/v1/analyze', files={'file': ('Minha referência.wav', audio.getvalue())},
                           data={'excerpt_start': '4', 'excerpt_duration': '4', 'source_kind': 'mix'})
    assert response.status_code == 200
    job = client.get('/api/v1/jobs/' + response.json()['job_id']).json()
    assert job['status'] == 'completed', job
    pair = client.get('/api/v1/presets/' + job['pair_id']).json()
    assert pair['lead_preset']['source_file_name'] == 'Minha referência.wav'
    assert pair['analysis']['spectral_profile']['brightness'] > .5
    assert any('trecho de 4s a 8s' in text for text in job['limitations'])
    assert pair['analysis']['confidence'] == 'low'


def test_api_rejects_invalid_excerpt_metadata(client):
    for data in [{'source_kind': 'unknown'}, {'excerpt_duration': 'nan'}, {'excerpt_start': 'inf'},
                 {'excerpt_duration': '2'}, {'excerpt_duration': '121'}, {'excerpt_start': '5'}]:
        assert client.post('/api/v1/analyze', files={'file': ('a.wav', b'x')}, data=data).status_code == 400
