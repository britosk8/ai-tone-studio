"""Piloto isolado Demucs 6 fontes. Guitarra não equivale a separação base/solo."""
import os
from pathlib import Path
LAB=Path(__file__).resolve().parents[1]
os.environ.setdefault('TORCH_HOME',str(LAB/'cache'/'torch'))
import argparse,hashlib,json,time
import numpy as np
import soundfile as sf
import torch
from demucs.pretrained import get_model
from demucs.apply import apply_model
ROOT=LAB.parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--track',default='01');p.add_argument('--role',choices=['base','solo_destaque'],default='base');p.add_argument('--threads',type=int,default=2);args=p.parse_args()
 manifest=json.loads((LAB/'relatorios'/'referencias.json').read_text())
 track=next(t for t in manifest['tracks'] if t['id']==args.track)
 candidate=next(c for c in track['candidates'] if c['role']==args.role and c['rank']==1)
 path=ROOT/candidate['file'];target=ROOT/'repertorio'/'fase_2'/'piloto_htdemucs_6s'/candidate['id']
 if target.exists():raise FileExistsError(f'Não sobrescrito: {target}')
 if hashlib.sha256(path.read_bytes()).hexdigest()!=candidate['sha256']:raise ValueError('O recorte mudou desde a triagem')
 torch.set_num_threads(args.threads);torch.manual_seed(0)
 began=time.monotonic();model=get_model('htdemucs_6s').cpu().eval()
 if 'guitar' not in model.sources:raise ValueError('Modelo sem saída dedicada guitar')
 data,sr=sf.read(path,dtype='float32',always_2d=True)
 if sr!=model.samplerate or data.shape[1]!=model.audio_channels:raise ValueError('Formato inesperado para este modelo')
 mix=torch.from_numpy(data.T.copy());ref=mix.mean(0);mean=ref.mean();std=ref.std()
 if std<1e-6:raise ValueError('Trecho silencioso')
 load_seconds=time.monotonic()-began;started=time.monotonic()
 with torch.inference_mode():
  output=apply_model(model,((mix-mean)/std)[None],device='cpu',shifts=0,split=True,overlap=.25,segment=4,num_workers=0,progress=True)[0]
  output=output*std+mean
 seconds=time.monotonic()-started
 if not torch.isfinite(output).all():raise ValueError('Saída inválida')
 target.mkdir(parents=True)
 stems=[]
 for name,samples in zip(model.sources,output):
  dest=target/f'{name}.wav';array=samples.numpy().T
  sf.write(dest,array,sr,subtype='FLOAT')
  stems.append({'source':name,'file':str(dest.relative_to(ROOT)),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'peak':float(np.abs(array).max()),'rms':float(np.sqrt(np.mean(array.astype(float)**2)))})
 residual=(output.sum(0)-mix).numpy()
 report={'schema_version':1,'candidate_id':candidate['id'],'input':candidate['file'],'input_sha256':candidate['sha256'],'source_original':track['original'],'start_seconds':candidate['start_seconds'],'end_seconds':candidate['end_seconds'],'model':'htdemucs_6s','demucs_version':'4.0.1','model_sources':list(model.sources),'seed':0,'shifts':0,'segment_seconds':4,'overlap':.25,'threads':args.threads,'device':'cpu','sample_rate':sr,'load_seconds':load_seconds,'inference_seconds':seconds,'realtime_factor':seconds/(len(data)/sr),'reconstruction_error_relative_rms':float(np.sqrt(np.mean(residual.astype(float)**2))/max(np.sqrt(np.mean(data.astype(float)**2)),1e-12)),'stems':stems,'review_status':'pendente_de_escuta','limitations':['Guitar inclui quaisquer guitarras presentes; não separa base de solo.','Não há stems verdadeiros para medir SDR ou fidelidade da separação.','Erro de reconstrução não comprova pureza nem preservação do timbre.','Vazamento e artefatos precisam ser avaliados por audição.','Modelo experimental de referência; sem integração ao app.']}
 (target/'resultado.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
 cached=list((LAB/'cache'/'torch'/'hub'/'checkpoints').glob('*.th'))
 report['model_checkpoints']=[{'name':c.name,'sha256':hashlib.sha256(c.read_bytes()).hexdigest()} for c in cached]
 (target/'resultado.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
 print(json.dumps({'candidate':candidate['id'],'seconds':round(seconds,2),'rtf':round(report['realtime_factor'],2),'stems':list(model.sources),'output':str(target)},ensure_ascii=False),flush=True)
if __name__=='__main__':main()
