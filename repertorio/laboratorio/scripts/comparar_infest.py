"""Compara duas configurações do mesmo separador nos dois trechos aprovados, sem alterar o app."""
import os
from pathlib import Path
LAB=Path(__file__).resolve().parents[1];ROOT=LAB.parents[1]
os.environ.setdefault('TORCH_HOME',str(LAB/'cache/torch'))
import hashlib,json,random,subprocess,time,html
from urllib.parse import quote
import numpy as np
import soundfile as sf
import torch
from scipy.signal import welch
from demucs.pretrained import get_model
from demucs.apply import apply_model
OUT=ROOT/'repertorio/fase_2/infest_comparacao'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def db(x):return float(20*np.log10(max(float(x),1e-12)))
def stats(x,sr):
 rms=float(np.sqrt(np.mean(x.astype(float)**2)));peak=float(np.abs(x).max())
 f,s=welch(x,fs=sr,nperseg=4096,axis=0);s=s.mean(axis=1)
 bands={k:float(s[(f>=lo)&(f<hi)].sum()) for k,(lo,hi) in {'bass':(80,250),'middle':(250,2500),'treble':(2500,8000)}.items()};total=sum(bands.values())
 return {'rms_dbfs':db(rms),'sample_peak_dbfs':db(peak),'crest_db':db(peak/max(rms,1e-12)),'stereo_correlation':float(np.corrcoef(x.T)[0,1]),'relative_bands_db':{k:float(10*np.log10(max(v/max(total,1e-20),1e-12))) for k,v in bands.items()}}
def main():
 if OUT.exists():raise FileExistsError('Não sobrescrito: '+str(OUT))
 approval=json.loads((ROOT/'repertorio/fase_1/01/APROVACAO_REFERENCIAS.json').read_text());m=json.loads((LAB/'relatorios/referencias.json').read_text());track=next(t for t in m['tracks'] if t['id']=='01')
 decisions={d['candidate_id']:d for d in approval['decisions']};assert len(decisions)==2
 torch.set_num_threads(2);torch.manual_seed(0);random.seed(0);np.random.seed(0)
 model=get_model('htdemucs_6s').cpu().eval();segments=[float(x.segment) for x in model.models] if hasattr(model,'models') else [float(model.segment)]
 OUT.mkdir(parents=True)
 report={'schema_version':1,'track_id':'01','approval_file':'repertorio/fase_1/01/APROVACAO_REFERENCIAS.json','model':'htdemucs_6s','demucs_version':'4.0.1','torch_version':torch.__version__,'device':'cpu','threads':2,'context_seconds_each_side':8,'segment_seconds':min(segments),'shifts':1,'overlap':.25,'seed':0,'interpretation':'Comparação de estabilidade e escuta entre duas configurações; não mede fidelidade ou pureza da separação.','results':[]}
 for c in track['candidates']:
  if c['id'] not in decisions:continue
  decision=decisions[c['id']];assert decision['start_seconds']==c['start_seconds'] and decision['end_seconds']==c['end_seconds']
  assert c.get('confirmed') is True
  candidate_path=ROOT/c['file'];assert sha(candidate_path)==c['sha256']
  folder=OUT/c['id'];folder.mkdir()
  original=ROOT/track['original'];assert sha(original)==track['original_sha256']
  start=max(0,c['start_seconds']-8);end=min(track['duration_seconds'],c['end_seconds']+8)
  raw=subprocess.check_output(['ffmpeg','-nostdin','-v','error','-i',str(original),'-map','0:a:0','-af',f'atrim=start={start}:end={end},asetpts=PTS-STARTPTS','-ar','44100','-ac','2','-f','f32le','pipe:1'])
  x=np.frombuffer(raw,dtype='<f4').reshape(-1,2).copy();sr=44100
  begin=round((c['start_seconds']-start)*sr);frames=round((c['end_seconds']-c['start_seconds'])*sr)
  selected,_=sf.read(candidate_path,dtype='float32',always_2d=True)
  assert np.array_equal(selected,x[begin:begin+frames]),'Recorte contextual desalinhado'
  sf.write(folder/'entrada_contexto.wav',x,sr,subtype='FLOAT')
  mix=torch.from_numpy(x.T.copy());ref=mix.mean(0);mean=ref.mean();std=ref.std()
  if std<1e-6:raise ValueError('Referência silenciosa')
  torch.manual_seed(0);random.seed(0);np.random.seed(0);began=time.monotonic()
  with torch.inference_mode():
   stems=apply_model(model,((mix-mean)/std)[None],device='cpu',shifts=1,split=True,overlap=.25,segment=min(segments),num_workers=0,progress=True)[0]*std+mean
  elapsed=time.monotonic()-began
  stems=stems[:,:,begin:begin+frames]
  assert stems.shape[-1]==len(selected) and torch.isfinite(stems).all()
  context_stems=[]
  for name,audio in zip(model.sources,stems):
   path=folder/f'{name}.wav';sf.write(path,audio.numpy().T,sr,subtype='FLOAT');context_stems.append({'source':name,'file':str(path.relative_to(ROOT)),'sha256':sha(path)})
  guitar=stems[list(model.sources).index('guitar')].numpy().T
  old_result=json.loads((ROOT/'repertorio/fase_2/piloto_htdemucs_6s'/c['id']/'resultado.json').read_text());old_path=ROOT/next(s['file'] for s in old_result['stems'] if s['source']=='guitar')
  old,_=sf.read(old_path,dtype='float32',always_2d=True)
  assert old.shape==guitar.shape==selected.shape
  audios={'mixagem':selected,'guitarra_inicial':old,'guitarra_contexto':guitar}
  # Igualação somente por ganho constante. Alvo comum reduzido se qualquer pico exceder -1 dBFS.
  rms={k:float(np.sqrt(np.mean(v.astype(float)**2))) for k,v in audios.items()}
  peaks={k:float(np.abs(v).max()) for k,v in audios.items()}
  if min(rms.values())<1e-8:raise ValueError('Saída sem sinal para comparar')
  target_rms=min(10**(-24/20),min(10**(-1/20)*rms[k]/max(peaks[k],1e-12) for k in audios))
  previews=[]
  for key,audio in audios.items():
   gain=target_rms/rms[key];preview=audio*gain;assert np.abs(preview).max()<=10**(-1/20)+1e-6
   path=folder/f'escuta_{key}.wav';sf.write(path,preview,sr,subtype='PCM_24')
   previews.append({'label':key,'file':str(path.relative_to(ROOT)),'sha256':sha(path),'gain_db':db(gain),'sample_peak_dbfs':db(np.abs(preview).max()),'rms_dbfs':db(np.sqrt(np.mean(preview.astype(float)**2)))})
  row={'candidate_id':c['id'],'start_seconds':c['start_seconds'],'end_seconds':c['end_seconds'],'source_file':track['original'],'source_sha256':track['original_sha256'],'input_file':c['file'],'input_sha256':c['sha256'],'inference_seconds':elapsed,'processed_context_seconds':len(x)/sr,'original_context_start':start,'original_context_end':end,'trim_offset_samples':begin,'target_preview_rms_dbfs':db(target_rms),'previews':previews,'context_stems':context_stems,'raw_metrics':{k:stats(v,sr) for k,v in audios.items()},'stem_quality_status':'pending_human_review'}
  report['results'].append(row)
  (OUT/'comparacao.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
  print(c['id'],'concluído em',round(elapsed,1),'s',flush=True)
 create_page(report)

def create_page(report):
 sections=[]
 labels={'mixagem':'Mixagem — contexto musical','guitarra_inicial':'Guitarra — extração inicial','guitarra_contexto':'Guitarra — extração com contexto'}
 for row in report['results']:
  players=[]
  for sample in row['previews']:
   url=quote(os.path.relpath(ROOT/sample['file'],OUT));players.append(f'<h3>{html.escape(labels[sample["label"]])}</h3><audio controls preload="none" src="{url}"></audio>')
  sections.append(f'''<section><h2>{html.escape(row['candidate_id'])} — {int(row['start_seconds'])//60:02d}:{int(row['start_seconds'])%60:02d}–{int(row['end_seconds'])//60:02d}:{int(row['end_seconds'])%60:02d}</h2><p>Trecho aprovado. Qualidade da separação ainda em avaliação.</p>{''.join(players)}<label>Preferência de extração <select class="choice" data-id="{row['candidate_id']}"><option value="pendente">Ainda não avaliei</option><option value="inicial">Extração inicial</option><option value="contexto">Extração com contexto</option><option value="ambas_aceitaveis">Ambas aceitáveis</option><option value="nenhuma">Nenhuma está adequada</option></select></label><p><label>O que percebeu? <textarea class="notes" data-id="{row['candidate_id']}" placeholder="Voz/baixo/bateria vazando? Guitarra perde corpo ou harmônicos? Tremulação, cortes ou efeito aquático?"></textarea></label></p></section>''')
 text='''<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Infest — validar guitarra extraída</title><style>body{font:17px system-ui;background:#101820;color:#edf6f8;max-width:900px;margin:auto;padding:24px}h1,h2{color:#80dec5}section{border-top:1px solid #567;padding:20px 0}audio,select,textarea{width:100%;box-sizing:border-box}select,textarea,button{font:inherit;padding:10px}textarea{min-height:90px}button{background:#80dec5;border:0;border-radius:6px;cursor:pointer}.note{background:#273038;padding:15px;border-left:4px solid #ffc76c}a{color:#80dec5}</style><h1>Papa Roach — Infest</h1><p>Referências aprovadas: base 00:50–01:10 e solo/destaque 02:40–03:00.</p><p class="note">Agora avaliamos a qualidade da guitarra extraída. Aprovar os tempos não significa aprovar o som separado. As duas versões usam o mesmo Demucs de seis fontes; a nova usa mais contexto. Ela não é automaticamente melhor e não separa base de solo simultâneos.</p><p>Ouça a mixagem para se localizar e alterne as duas guitarras. As três cópias de escuta têm RMS equivalente por trecho e pico de amostra limitado por ganho constante; isso não garante volume percebido idêntico. Nenhum EQ, compressor ou limitador foi aplicado. Ajuste o volume de escuta com conforto e pause um player antes de iniciar outro.</p>'''+''.join(sections)+'''<button onclick="downloadReview()">Baixar avaliação da separação</button><p>As escolhas não são salvas automaticamente; exporte antes de fechar a página.</p><p><a href="../../fase_1/01/CAPTURA_WINDOWS.md">Próxima etapa: capturas da MK300 no Windows</a></p><script>function downloadReview(){const rows=[...document.querySelectorAll('.choice')].map(x=>({candidate_id:x.dataset.id,preference:x.value,notes:[...document.querySelectorAll('.notes')].find(n=>n.dataset.id===x.dataset.id).value}));const blob=new Blob([JSON.stringify({schema_version:1,track_id:'01',reviewed_at:new Date().toISOString(),separation_review:rows},null,2)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='infest_avaliacao_separacao.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)}</script></html>'''
 (OUT/'VALIDAR_GUITARRAS.html').write_text(text)
if __name__=='__main__':main()
