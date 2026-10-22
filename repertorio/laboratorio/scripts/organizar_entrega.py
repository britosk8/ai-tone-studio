"""Organiza fichas, fila e página de revisão a partir dos arquivos efetivamente produzidos."""
from pathlib import Path
import json,csv,html,os,re
from urllib.parse import quote
import preparar_referencias as p
LAB=Path(__file__).resolve().parents[1];ROOT=LAB.parents[1];FASE=ROOT/'repertorio/fase_1';PHASE2=ROOT/'repertorio/fase_2'
def main():
 manifest=json.loads((LAB/'relatorios/referencias.json').read_text())
 for track in manifest['tracks']:
  approval_path=FASE/track['id']/'APROVACAO_REFERENCIAS.json'
  if not approval_path.exists():continue
  approval=json.loads(approval_path.read_text())
  decisions={x['candidate_id']:x for x in approval['decisions']}
  for candidate in track['candidates']:
   if candidate['id'] in decisions:
    decision=decisions[candidate['id']]
    if candidate['start_seconds']!=decision['start_seconds'] or candidate['end_seconds']!=decision['end_seconds']:raise ValueError('Tempos mudaram desde a aprovação')
    candidate.update(confirmed=True,review_status='approved_for_pilot',review_decision=decision['decision'],approved_on=approval['approved_on'],approved_by=approval['approved_by'],separation_review_status='pending')
 manifest['selection_status']='parcialmente_aprovado' if any(c.get('confirmed') for t in manifest['tracks'] for c in t['candidates']) else 'candidatos_pendentes_de_escuta' 
 queue=[];csvrows=[]
 for t in manifest['tracks']:
  artist,title=Path(t['filename']).stem.split(' - ',1);title=title.strip()
  ficha=FASE/t['id']/'FICHA.md';text=ficha.read_text()
  values={'Música':title,'Artista':artist,'Versão de referência (estúdio, ao vivo, outra)':'Gravação fornecida pelo usuário; versão a ser seguida pela banda. Estúdio/ao vivo não confirmado.','Nome do arquivo em `original/`':t['filename'],'Parte que vou tocar (base, solo, ambas)':'Ambas no piloto MK300. Pai: base; filho: solo.','Guitarra e captadores / posição utilizada':'Pai: Konig Stratocaster SSS; filho: Strinberg Les Paul HH. Posição do seletor e controles pendentes.','Pedaleira e firmware, se conhecido':'MK300 no piloto (base e solo); MK20 em etapa posterior. Firmware a confirmar.','Como vou ouvir (fones, mesa, caixa, amplificador)':'Saída de áudio da pedaleira → Depusheng MQ44 → notebook → monitores Tomate MTS 2043.'}
  for label,value in values.items():
   text=re.sub(r'^- '+re.escape(label)+r':\s*$',lambda _:f'- {label}: {value}',text,flags=re.M)
  section=['\n## Candidatos e referências\n','As funções musicais partiram da triagem CLAP. Consulte o status de aprovação de cada trecho; a qualidade dos stems é uma avaliação separada. Os arquivos desta tabela são recortes da mixagem.\n','| ID | Papel proposto | Início | Fim | Arquivo | Status |\n| --- | --- | --- | --- | --- | --- |']
  for c in t['candidates']:
   name=Path(c['file']).name
   section.append(f"| {c['id']} | {c['role']} | {p.fmt(c['start_seconds'])} | {p.fmt(c['end_seconds'])} | [ouvir](trechos/{quote(name)}) | {'Aprovado para piloto' if c.get('confirmed') else 'Pendente / alternativa'} |")
   queue.append({'candidate_id':c['id'],'track_id':t['id'],'proposed_role':c['role'],'priority':c['rank'],'input':c['file'],'sha256':c['sha256'],'start_seconds':c['start_seconds'],'end_seconds':c['end_seconds'],'review_status':c.get('review_status','pending'),'target_sources':['drums','bass','vocals','guitar','piano','other'],'guitar_parts_split':False})
   csvrows.append([t['id'],title,artist,c['id'],c['role'],p.fmt(c['start_seconds']),p.fmt(c['end_seconds']),c['file'],c.get('review_status','pendente')])
  section.append('\nStatus: trechos principais aprovados; faltam avaliação da separação, exportação dos presets atuais, capturas e reamp.\n' if any(c.get('confirmed') for c in t['candidates']) else '\nStatus: referências provisórias; faltam revisão auditiva, exportação dos presets atuais, capturas das guitarras e validação de reamp.\n')
  marker='\n## Candidatos automáticos preparados (não confirmados)'
  if marker in text:text=text[:text.index(marker)]
  if '\n## Candidatos e referências' in text:text=text[:text.index('\n## Candidatos e referências')]
  if any(c.get('confirmed') for c in t['candidates']):
   section.append('\nOs dois trechos principais foram aprovados pelo usuário em 22/10/2026, conforme APROVACAO_REFERENCIAS.json. As alternativas não foram selecionadas; a qualidade da guitarra extraída ainda precisa de avaliação.\n')
  ficha.write_text(text+'\n'.join(section))
 (PHASE2/'fila_separacao.json').write_text(json.dumps({'schema_version':1,'inputs_are_mixes':True,'review_required':True,'jobs':queue},ensure_ascii=False,indent=2))
 with (FASE/'REFERENCIAS.csv').open('w',newline='') as f:
  w=csv.writer(f);w.writerow(['pasta','musica','artista','id','papel_proposto','inicio','fim','arquivo','validacao']);w.writerows(csvrows)
 # Atualiza observações sem converter escores em probabilidades.
 for t in manifest['tracks']:
  for c in t['candidates']:
   scores=c['scores'];c['cautions']=[]
   if scores['voz']>scores[c['role']]:c['cautions'].append('Voz pode dominar a passagem; ouvir antes de aceitar.')
   if scores['bateria']>scores[c['role']]:c['cautions'].append('Bateria pode influenciar a triagem.')
   if scores['baixo']>scores[c['role']]:c['cautions'].append('Baixo pode dominar a passagem.')
   if not c.get('confirmed') and c['role']=='solo_destaque' and scores['base']>scores['solo_destaque']:c['cautions'].append('Não há confirmação de solo; pode ser apenas outra passagem de base.')
 (LAB/'relatorios/referencias.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
 p.create_review(manifest)
 # Amostras reais do piloto; disponibiliza apenas resultados já concluídos.
 results=[];sections=[]
 for result in sorted((PHASE2/'piloto_htdemucs_6s').glob('*/resultado.json')):
  d=json.loads(result.read_text());results.append(d)
  audios=[]
  for label,file in [('Mixagem de entrada',d['input'])]+[(x['source'],x['file']) for x in d['stems']]:
   url=quote(os.path.relpath(ROOT/file,PHASE2));audios.append(f'<p>{html.escape(label)}</p><audio controls preload="none" src="{url}"></audio>')
  sections.append(f"<section><h2>{html.escape(d['candidate_id'])}</h2><p>Original: {p.fmt(d['start_seconds'])}–{p.fmt(d['end_seconds'])}. Inferência: {d['inference_seconds']:.1f}s CPU. Qualidade pendente de audição.</p>{''.join(audios)}</section>")
 (PHASE2/'resultados_piloto.json').write_text(json.dumps({'schema_version':1,'results':results},ensure_ascii=False,indent=2))
 (PHASE2/'OUVIR_SEPARACAO.html').write_text('''<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Piloto de separação IA</title><style>body{background:#101820;color:#edf6f8;font:16px system-ui;max-width:900px;margin:auto;padding:24px}h1,h2{color:#80dec5}section{border-top:1px solid #577;padding:20px 0}audio{width:100%}</style><h1>Piloto real — Demucs htdemucs_6s</h1><p>Ouça primeiro a mixagem e depois guitar, vocals e demais fontes. A guitarra pode conter base e solo juntos. Não são stems de estúdio nem referências já aprovadas. Há possibilidade de vazamento e alteração do timbre. Volume não foi normalizado entre as fontes.</p>'''+''.join(sections)+'</html>')
 print(f'{len(csvrows)} referências, {len(results)} separações concluídas, fichas e páginas atualizadas.')
if __name__=='__main__':main()
