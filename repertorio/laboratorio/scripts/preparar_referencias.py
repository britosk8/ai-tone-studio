"""Triagem local com CLAP; gera candidatos auditáveis, nunca rótulos musicais confirmados."""
import os
from pathlib import Path
LAB=Path(__file__).resolve().parents[1]
os.environ.setdefault('HF_HOME',str(LAB/'cache'/'huggingface'))
os.environ.setdefault('TORCH_HOME',str(LAB/'cache'/'torch'))
os.environ.setdefault('TOKENIZERS_PARALLELISM','false')
import argparse,hashlib,json,subprocess,time,html
import numpy as np
import torch
from transformers import ClapModel,ClapProcessor
from urllib.parse import quote
ROOT=LAB.parents[1]
FASE=ROOT/'repertorio'/'fase_1'
MODEL='laion/clap-htsat-unfused'
REV='8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a'
TEXTS={
 'base':['The sound of distorted electric rhythm guitar playing repeated chords and heavy riffs.', 'The sound of clean electric rhythm guitar playing arpeggios and chord accompaniment.'],
 'solo_destaque':['The sound of an electric lead guitar solo playing a melody with bends and sustained notes.', 'The sound of a prominent electric guitar playing a melodic instrumental lead passage.'],
 'voz':['The sound of a singer singing with rock band accompaniment.', 'The sound of a person speaking over music.'],
 'baixo':['The sound of a prominent bass guitar playing a bass riff.'],
 'bateria':['The sound of a drum solo with drums and cymbals.'],
}
def run(*args):
 return subprocess.check_output(list(args),stderr=subprocess.PIPE)
def probe(path):
 return json.loads(run('ffprobe','-v','error','-show_format','-show_streams','-of','json',str(path)))
def fmt(t):
 return f'{int(t)//60:02d}:{int(t)%60:02d}'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def clip(path,dest,start,duration):
 if dest.exists(): raise FileExistsError(dest)
 subprocess.run(['ffmpeg','-nostdin','-v','error','-i',str(path),'-af',f'atrim=start={start}:duration={duration},asetpts=PTS-STARTPTS','-map','0:a:0','-ar','44100','-ac','2','-c:a','pcm_f32le',str(dest)],check=True)
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--threads',type=int,default=2);args=parser.parse_args()
 torch.set_num_threads(args.threads);torch.manual_seed(0)
 processor=ClapProcessor.from_pretrained(MODEL,revision=REV)
 model=ClapModel.from_pretrained(MODEL,revision=REV,weights_only=True).eval()
 prompts=[s for v in TEXTS.values() for s in v]
 with torch.inference_mode():
  features=model.get_text_features(**processor(text=prompts,return_tensors='pt',padding=True))
  features=torch.nn.functional.normalize(features,dim=-1)
 indices={};offset=0
 for key,values in TEXTS.items():indices[key]=slice(offset,offset+len(values));offset+=len(values)
 manifest={'schema_version':1,'model':MODEL,'revision':REV,'sample_rate_ranking':48000,'window_seconds':10,'stride_seconds':10,'clip_seconds':20,'selection_status':'candidatos_pendentes_de_escuta','prompts':TEXTS,'tracks':[]}
 for n in range(1,7):
  folder=FASE/f'{n:02d}'; originals=list((folder/'original').glob('*.m4a'))
  if len(originals)!=1:raise ValueError(f'Esperado um M4A em {folder}')
  path=originals[0];info=probe(path);duration=float(info['format']['duration'])
  mono=np.frombuffer(run('ffmpeg','-nostdin','-v','error','-i',str(path),'-map','0:a:0','-f','f32le','-ar','48000','-ac','1','pipe:1'),dtype='<f4')
  starts=list(range(5,int(duration)-15,10));windows=[]
  for at in range(0,len(starts),2):
   batch=starts[at:at+2]; samples=[mono[s*48000:(s+10)*48000].copy() for s in batch]
   with torch.inference_mode():
    inputs=processor(audios=samples,sampling_rate=48000,return_tensors='pt')
    emb=model.get_audio_features(**inputs);emb=torch.nn.functional.normalize(emb,dim=-1)
    similarity=(emb@features.T).cpu().numpy()
   for start,y,sim in zip(batch,samples,similarity):
    scores={key:float(np.max(sim[idx])) for key,idx in indices.items()}
    rms=float(np.sqrt(np.mean(y.astype(float)**2)))
    windows.append({'start':start,'end':start+10,'rms_dbfs':float(20*np.log10(max(rms,1e-12))),'scores':scores})
  chosen=[]; selected_centers=[]
  for role,opposite in [('base','solo_destaque'),('solo_destaque','base')]:
   ranked=sorted(windows,key=lambda w:w['scores'][role]-.35*w['scores']['voz']-.15*w['scores'][opposite],reverse=True)
   for w in ranked:
    center=w['start']+5
    if w['rms_dbfs']<-45 or any(abs(center-c)<25 for c in selected_centers):continue
    start=max(0,min(duration-20,center-10));rank=len([c for c in chosen if c['role']==role])+1
    filename=f'candidato_{role}_{rank:02d}_{int(start):04d}s.wav';dest=folder/'trechos'/filename
    clip(path,dest,start,20)
    chosen.append({'id':f'{n:02d}_{role}_{rank:02d}','role':role,'rank':rank,'start_seconds':start,'end_seconds':start+20,'file':str(dest.relative_to(ROOT)),'sha256':sha(dest),'scores':w['scores'],'confirmed':False,'rationale':'Ranking CLAP por descrições textuais, com penalidade de voz e contraste entre papéis. Não detecta solo/base com garantia.'})
    selected_centers.append(center)
    if rank==2:break
  peaks=[]
  for segment in np.array_split(mono,500):peaks.append(round(float(np.max(np.abs(segment))),4))
  track={'id':f'{n:02d}','original':str(path.relative_to(ROOT)),'original_sha256':sha(path),'filename':path.name,'duration_seconds':duration,'codec':next(s['codec_name'] for s in info['streams'] if s['codec_type']=='audio'),'sample_rate':44100,'channels':2,'windows':windows,'candidates':chosen,'waveform_peaks':peaks}
  manifest['tracks'].append(track)
  (LAB/'relatorios'/'referencias.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
  print(f'{n:02d}: {len(windows)} janelas, {len(chosen)} candidatos. {path.name}',flush=True)
  for c in chosen:print(' ',c['id'],fmt(c['start_seconds']),fmt(c['end_seconds']),flush=True)
 create_review(manifest)

def create_review(manifest):
 esc=html.escape
 blocks=[]
 for t in manifest['tracks']:
  items=[]
  for c in t['candidates']:
   src=quote(os.path.relpath(ROOT/c['file'],FASE))
   label=f"{c['id']} — {fmt(c['start_seconds'])} a {fmt(c['end_seconds'])}"
   items.append(f'''<article><h3>{esc(label)}</h3><audio controls preload="none" src="{src}"></audio><p>Papel: {esc(c['role'])}. {'Trecho aprovado pelo usuário; qualidade da separação pendente.' if c.get('confirmed') else 'Pendente de escuta.'}</p><p>{esc(' '.join(c.get('cautions',[])))}</p><label>Decisão <select data-id="{esc(c['id'])}" class="decision"><option value="pendente">Pendente</option><option value="aceitar_base" {'selected' if c.get('review_decision')=='aceitar_base' else ''}>Aceitar como base</option><option value="aceitar_solo" {'selected' if c.get('review_decision')=='aceitar_solo' else ''}>Aceitar como solo</option><option value="aceitar_destaque">Aceitar como destaque / segunda guitarra</option><option value="rejeitar">Rejeitar</option><option value="sem_solo">Não representa solo nesta música</option></select></label><p><label>Observação <input data-id="{esc(c['id'])}" class="note" placeholder="Voz, bateria, outra guitarra, timbre..." /></label></p></article>''')
  original=quote(os.path.relpath(ROOT/t['original'],FASE))
  # Envoltória apenas para localizar as passagens: não é evidência de guitarra.
  bars=''.join(f'<line x1="{i*2}" x2="{i*2}" y1="{45-min(v,1)*40}" y2="{45+min(v,1)*40}" stroke="#69a7bd"/>' for i,v in enumerate(t['waveform_peaks']))
  marks=''.join(f'<rect x="{c["start_seconds"]/t["duration_seconds"]*1000}" y="0" width="{20/t["duration_seconds"]*1000}" height="90" fill="{("#008867" if c["role"]=="base" else "#b07400")}" opacity=".35" />' for c in t['candidates'])
  blocks.append(f'''<section><h2>{esc(t['id']+' — '+t['filename'])}</h2><p>Original: {fmt(t['duration_seconds'])} · AAC estéreo 44,1 kHz · hash registrado no manifesto.</p><audio controls preload="none" src="{original}"></audio><svg viewBox="0 0 1000 90" role="img" aria-label="Envoltória e localização dos candidatos">{bars}{marks}</svg><div class="grid">{''.join(items)}</div></section>''')
 page='''<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Repertório — revisão das referências</title><style>body{background:#101820;color:#edf6f8;font:16px system-ui;max-width:1150px;margin:auto;padding:24px}h1,h2{color:#80dec5}section{border-top:1px solid #577;padding:20px 0}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px}article{background:#20313b;padding:16px;border-radius:12px}audio,input,select{max-width:100%;width:100%}input,select,button{font:inherit;padding:8px;box-sizing:border-box}svg{width:100%;max-height:90px;margin:16px 0}button{background:#80dec5;border:0;border-radius:6px;cursor:pointer}.alert{border-left:5px solid #ffc76c;padding:12px;background:#273038}a{color:#80dec5}</style><h1>Fase 1 — revisão das seis referências</h1><p class="alert">Triagem por IA CLAP, não validação musical. Os WAVs são recortes da mixagem original, não guitarras isoladas. “Solo/destaque” é um candidato: algumas músicas podem não conter solo tradicional. Ouçam e classifiquem antes de usar como referência definitiva.</p><p>Ouçam o original e os quatro candidatos de cada música com volume confortável. Não há normalização de volume nem porcentagem de fidelidade. Os arquivos preservam o nível decodificado do M4A em WAV float32. A comparação com a pedaleira exigirá ajuste de volume de escuta.</p><button onclick="exportReview()">Baixar decisões da revisão (JSON)</button><p>As decisões ficam nesta página enquanto ela estiver aberta. O botão exporta um arquivo; não altera o projeto.</p>'''+''.join(blocks)+'''<script>function exportReview(){const decisions=[...document.querySelectorAll('.decision')].map(x=>({id:x.dataset.id,decision:x.value,note:[...document.querySelectorAll('.note')].find(n=>n.dataset.id===x.dataset.id).value}));const blob=new Blob([JSON.stringify({schema_version:1,reviewed_at:new Date().toISOString(),decisions},null,2)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='revisao_referencias.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)}</script></html>'''
 (FASE/'REVISAO_REFERENCIAS.html').write_text(page)

if __name__=='__main__':main()
