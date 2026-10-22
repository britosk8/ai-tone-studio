"""Valida artefatos e isolamento. Não avalia qualidade musical nem pureza de stems."""
from pathlib import Path
import hashlib,json,subprocess
from html.parser import HTMLParser
from urllib.parse import unquote
import numpy as np
import soundfile as sf
LAB=Path(__file__).resolve().parents[1];ROOT=LAB.parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
class AudioLinks(HTMLParser):
 def __init__(self):super().__init__();self.sources=[];self.decisions=[]
 def handle_starttag(self,tag,attrs):
  attrs=dict(attrs)
  if tag=='audio':self.sources.append(attrs.get('src',''))
  if tag=='select' and attrs.get('class')=='decision':self.decisions.append(attrs['data-id'])
def main():
 baseline=json.loads((LAB/'relatorios/estado_inicial.json').read_text())
 update_file=LAB/'relatorios/atualizacao_android_v1_2_3.json'
 updates=json.loads(update_file.read_text())['changes'] if update_file.exists() else {}
 expected=dict(baseline)
 for rel,change in updates.items():
  assert baseline.get(rel)==change['before'], 'Baseline divergente'
  expected[rel]=change['after']
 changed=[rel for rel,digest in expected.items() if not(ROOT/rel).is_file() or sha(ROOT/rel)!=digest]
 if changed:raise AssertionError(f'Arquivos protegidos modificados: {changed}')
 m=json.loads((LAB/'relatorios/referencias.json').read_text());queue=json.loads((ROOT/'repertorio/fase_2/fila_separacao.json').read_text())
 assert len(m['tracks'])==6
 active={};trim_errors=[]
 for t in m['tracks']:
  source=ROOT/t['original'];assert sha(source)==t['original_sha256']
  decoded=np.frombuffer(subprocess.check_output(['ffmpeg','-nostdin','-v','error','-i',str(source),'-map','0:a:0','-f','f32le','-ar','44100','-ac','2','pipe:1']),dtype='<f4').reshape(-1,2)
  assert len(t['candidates'])==4
  for c in t['candidates']:
   assert c['id'] not in active
   active[c['id']]=c
   path=ROOT/c['file'];assert sha(path)==c['sha256'];audio,sr=sf.read(path,dtype='float32',always_2d=True)
   assert sr==44100 and audio.shape==(20*sr,2) and np.isfinite(audio).all()
   assert sf.info(path).subtype=='FLOAT'
   assert 0<=c['start_seconds']<c['end_seconds']<=t['duration_seconds']+.01
   begin=round(c['start_seconds']*sr);expected=decoded[begin:begin+len(audio)]
   err=float(np.max(np.abs(audio-expected)));trim_errors.append(err)
   assert err<1e-6,(c['id'],err)
 assert len(queue['jobs'])==24 and {j['candidate_id'] for j in queue['jobs']}==set(active)
 for j in queue['jobs']:assert j['sha256']==active[j['candidate_id']]['sha256']
 reports=list((ROOT/'repertorio/fase_2/piloto_htdemucs_6s').glob('*/resultado.json'));stems=0;rtfs=[]
 for path in reports:
  d=json.loads(path.read_text());c=active[d['candidate_id']]
  assert d['input_sha256']==c['sha256'];assert d['model']=='htdemucs_6s';assert set(d['model_sources'])=={'drums','bass','other','vocals','guitar','piano'}
  assert len(d['stems'])==6
  for s in d['stems']:
   file=ROOT/s['file'];assert sha(file)==s['sha256'];x,sr=sf.read(file,dtype='float32',always_2d=True)
   assert sr==44100 and x.shape==(20*sr,2) and np.isfinite(x).all();stems+=1
  rtfs.append(d['realtime_factor'])
 pages=[]
 for path in [ROOT/'repertorio/fase_1/REVISAO_REFERENCIAS.html',ROOT/'repertorio/fase_2/OUVIR_SEPARACAO.html']:
  parser=AudioLinks();parser.feed(path.read_text())
  for link in parser.sources:assert link and (path.parent/unquote(link)).is_file(),link
  if path.name.startswith('REVISAO'):assert set(parser.decisions)==set(active)
  else:assert len(parser.sources)==len(reports)*7, 'Página de separação desatualizada'
  pages.append({'file':str(path.relative_to(ROOT)),'audio_links':len(parser.sources)})
 backend=subprocess.check_output([str(ROOT/'backend/.venv/bin/python'),'-c',"import importlib.util,json; print(json.dumps({k:importlib.util.find_spec(k) is not None for k in ['demucs','torch','librosa']}))"],text=True)
 assert json.loads(backend)=={'demucs':False,'torch':False,'librosa':True}
 report={'protected_files_verified':len(baseline),'protected_files_unchanged':len(baseline)-len(updates),'versioned_changes_verified':len(updates),'originals_preserved':6,'active_clips':len(active),'max_sample_error_vs_original':max(trim_errors),'separated_clips':len(reports),'valid_stems':stems,'average_realtime_factor':float(np.mean(rtfs)) if rtfs else None,'html_pages':pages,'backend_environment_unchanged':json.loads(backend),'musical_validation':'pending','pedal_captures':'pending','reamp_test':'pending'}
 (LAB/'relatorios/validacao.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
