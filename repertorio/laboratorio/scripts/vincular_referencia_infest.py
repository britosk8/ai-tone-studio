"""Vincula trechos aprovados ao piloto R1 sincronizado; não escolhe por título.

Exige ID explícito e uma referência cujo preset gerado corresponda ao R1
versionado. Confere SHA-256 do original e aprovação dos trechos. Não sobrescreve
perfis já escolhidos pelo usuário e não envia nada à pedaleira.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'backend'))
from app.core.storage import load_record, save_record
from app.services.audio_analysis.tone_comparison import measure


def signature(preset):
    return [(b['effect_type'], str(b['model_id']), b['model_name'],
             b['enabled'], b['parameters']) for b in preset['effect_chain']]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pair-id', required=True)
    args = parser.parse_args()
    exported = json.loads((ROOT / 'repertorio/fase_1/01/presets/piloto_r1/Infest_MK300_Piloto_R1.json').read_text())
    anchor = None
    for role, field in [('rhythm', 'rhythm_preset'), ('lead', 'lead_preset')]:
        record = load_record('pedal_reference', json.dumps([args.pair_id, role]))
        if not record:
            continue
        actual, expected = record['generated_preset'], exported[field]
        if (signature(actual) == signature(expected) and all(actual.get(k) == expected.get(k)
                for k in ['artist', 'song_title', 'source_file_name', 'device', 'catalog_version'])):
            anchor = record
            break
    if anchor is None:
        raise ValueError('Análise sem referência sincronizada que corresponda ao R1 versionado; nenhum perfil salvo.')
    approval = json.loads((ROOT / 'repertorio/fase_1/01/APROVACAO_REFERENCIAS.json').read_text())
    decisions = {row['candidate_id']: row for row in approval['decisions']}
    comparison = json.loads((ROOT / 'repertorio/fase_2/infest_comparacao/comparacao.json').read_text())
    pending = []
    for role, candidate in [('rhythm', '01_base_01'), ('lead', '01_solo_destaque_01')]:
        key = json.dumps([args.pair_id, role])
        if load_record('comparison_reference', key) is not None:
            print(role, 'perfil existente preservado')
            continue
        row = next(r for r in comparison['results'] if r['candidate_id'] == candidate)
        decision = decisions[candidate]
        if (decision['start_seconds'], decision['end_seconds']) != (row['start_seconds'], row['end_seconds']):
            raise ValueError('Trecho divergente da aprovação')
        if decision['decision'] not in {'aceitar_base', 'aceitar_solo'}:
            raise ValueError('Trecho não aprovado')
        original = ROOT / row['source_file']
        digest = hashlib.sha256(original.read_bytes()).hexdigest()
        if digest != row['source_sha256']:
            raise ValueError('Original diferente da versão aprovada')
        start, duration = row['start_seconds'], row['end_seconds'] - row['start_seconds']
        profile = measure(original, start, duration)
        pending.append((key, {'profile': {**profile, 'source_kind': 'mix'},
            'original_file_name': original.name, 'original_file_sha256': digest,
            'start_seconds': start, 'duration_seconds': duration,
            'binding_method': 'explicit_pair_r1_signature_and_approved_original_sha256',
            'anchor_role': anchor['role'], 'candidate_id': candidate,
            'approval_file': 'repertorio/fase_1/01/APROVACAO_REFERENCIAS.json'}))
    # Todas as medições/validações terminam antes da primeira escrita.
    for key, record in pending:
        save_record('comparison_reference', key, record)
        print(key, record['start_seconds'], record['duration_seconds'], 'perfil vinculado')


if __name__ == '__main__':
    main()
