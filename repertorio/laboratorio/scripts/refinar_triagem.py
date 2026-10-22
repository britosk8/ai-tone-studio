"""Aplica filtro adicional aos candidatos de base já gerados, preservando a triagem inicial."""
from pathlib import Path
import json
import preparar_referencias as m
lab=Path(__file__).resolve().parents[1];p=lab/'relatorios/referencias.json';d=json.loads(p.read_text())
for t in d['tracks']:
 for c in t['candidates']:
  if c['role']!='base' or not(c['scores']['baixo']>c['scores']['base'] or c['scores']['bateria']>c['scores']['base']+.10):continue
  excluded=dict(c);excluded['exclusion_reason']='Baixo ou bateria predominante no escore CLAP; substituído por candidato menos ambíguo.'
  t.setdefault('excluded_candidates',[]).append(excluded)
  others=[x['start_seconds']+10 for x in t['candidates'] if x is not c]
  for w in sorted(t['windows'],key=lambda w:w['scores']['base']-.35*w['scores']['voz']-.15*w['scores']['solo_destaque'],reverse=True):
   if w['scores']['baixo']>w['scores']['base'] or w['scores']['bateria']>w['scores']['base']+.10:continue
   center=w['start']+5
   if any(abs(center-o)<25 for o in others):continue
   start=max(0,min(t['duration_seconds']-20,center-10));name=f'candidato_base_{c["rank"]:02d}_{int(start):04d}s.wav';out=m.FASE/t['id']/'trechos'/name
   m.clip(m.ROOT/t['original'],out,start,20)
   c.update(start_seconds=start,end_seconds=start+20,file=str(out.relative_to(m.ROOT)),sha256=m.sha(out),scores=w['scores'],cautions=[])
   print(t['id'],'base',c['rank'],'substituído',start,flush=True)
   break
  else:raise ValueError('Nenhuma alternativa para '+t['id'])
d['base_screening']='Exclui escore de baixo maior que base e bateria maior que base + 0.10; diversidade mínima de centros 25s.'
p.write_text(json.dumps(d,ensure_ascii=False,indent=2))
