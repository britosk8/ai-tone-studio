"""Geração experimental rastreável: duas análises independentes, sem modificar presets existentes."""
from pathlib import Path
import sys,json,hashlib
from uuid import uuid4
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'backend'))
from app.services.audio_analysis.analyzer import AudioAnalyzer
from app.services.device_catalog.loader import CatalogLoader
from app.services.preset_generation.compiler import PresetCompiler
from app.models.audio import ConfidenceLevel
from app.models.devices import DeviceModel,EffectType
from app.models.preset import ParameterValue,PresetPair
from app.api.routes import _serialize_preset
from app.transport.preset_builder import preset_to_struct
OUT=ROOT/'repertorio/fase_1/01/presets/piloto_r1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 if OUT.exists():raise FileExistsError('Não sobrescrito: '+str(OUT))
 approval=json.loads((ROOT/'repertorio/fase_1/01/APROVACAO_REFERENCIAS.json').read_text())
 decisions={x['candidate_id']:x for x in approval['decisions']}
 comparison=json.loads((ROOT/'repertorio/fase_2/infest_comparacao/comparacao.json').read_text())
 loader=CatalogLoader(ROOT/'catalogs');compiler=PresetCompiler(loader);cat=loader._catalogs[DeviceModel.MK300]
 presets=[];analyses=[];provenance=[]
 for role,candidate in [('rhythm','01_base_01'),('lead','01_solo_destaque_01')]:
  row=next(x for x in comparison['results'] if x['candidate_id']==candidate)
  assert decisions[candidate]['start_seconds']==row['start_seconds'] and decisions[candidate]['end_seconds']==row['end_seconds']
  source=next(x for x in row['context_stems'] if x['source']=='guitar');path=ROOT/source['file'];assert sha(path)==source['sha256']
  a=AudioAnalyzer(source_kind='mix').analyze(path)
  a.overall_confidence=ConfidenceLevel.LOW
  a.limitations=['Guitarra estimada por Demucs htdemucs_6s; trecho aprovado, qualidade do stem ainda não aprovada.','Geração por medições e regras, não por modelo treinado de reprodução da MK300.','Preset inicial experimental: precisa ser ouvido e ajustado na guitarra e pedaleira reais.']+a.limitations
  pair=compiler.compile_pair(a,DeviceModel.MK300,DeviceModel.MK300,artist='Papa Roach',song_title='Infest — Piloto R1')
  preset=pair.rhythm_preset if role=='rhythm' else pair.lead_preset
  preset.name='Infest Base R1' if role=='rhythm' else 'Infest Solo R1'
  preset.source_file_name='Papa Roach - Infest .m4a'
  preset.section=f"Trecho aprovado {row['start_seconds']}–{row['end_seconds']}s"
  # BPM da guitarra sozinha pode refletir subdivisão; efeitos de tempo não serão ativados.
  preset.bpm=None
  changes=[]
  for block in preset.effect_chain.blocks:
   original=block.model_dump(mode='json')
   block.enabled=block.effect_type in {EffectType.NOISE_GATE,EffectType.AMP,EffectType.CABINET}
   catalog_block=next(b for b in cat['blocks'].values() if any(str(m['id'])==block.model_id and m['name']==block.model_name for m in b['models']))
   model=next(m for m in catalog_block['models'] if str(m['id'])==block.model_id and m['name']==block.model_name)
   common=catalog_block.get('knob_ranges',catalog_block.get('common_knob_ranges',{}));specs={**common,**model.get('params',{})}
   values={p.name:p.raw_value for p in block.parameters}
   if 'Sync' in model['knobs']:values['Sync']=0
   if block.effect_type==EffectType.NOISE_GATE:values.update(Gate=15,Bias=50)
   if block.effect_type==EffectType.AMP:values.update(Level=50,Reso=0,Bright=0)
   if block.effect_type==EffectType.CABINET:values.update(Level=80,**{'Low Cut':0,'High Cut':200})
   params=[]
   for i,name in enumerate(model['knobs']):
    spec=specs[name];defaults=model.get('defaults',[])
    default=spec.get('default',common.get(name,{}).get('default'))
    if default is None and i<len(defaults):default=defaults[i]
    if name not in values and default is None:raise ValueError('Sem valor explícito/default para '+name+' em '+model['name'])
    value=float(values.get(name,default));lo=spec.get('min',0);hi=spec.get('max',100)
    assert lo<=value<=hi and value==round(value)
    params.append(ParameterValue(name=name,raw_value=value,display_value=f'{value:g}',min_value=lo,max_value=hi,step=spec.get('step',1),unit=spec.get('unit')))
   block.parameters=params
   block.generated_confidence=ConfidenceLevel.SPECULATIVE if block.effect_type==EffectType.NOISE_GATE else ConfidenceLevel.LOW
   block.generation_rationale+=' | Piloto R1: hipótese inicial, não equipamento original identificado.'
   if not block.enabled:block.generation_rationale+=' Desligado por evidência insuficiente; não empilhar drive/ambiência nesta primeira captura.'
   changes.append({'before':original,'after':block.model_dump(mode='json')})
  preset.generation_summary='Análise independente da guitarra extraída do trecho aprovado; gerador heurístico atual, com cadeia enxuta para o primeiro teste.'
  preset.limitations_noted+=['Level do amp 50 e CAB 80 são valores iniciais, não calibração de volume real.','Gate 15/Bias 50, Reso 0/Bright 0 e cortes do CAB são hipóteses explícitas dentro do catálogo; não foram estimados com precisão nem validados no equipamento.','Sem compensação específica para captadores SSS/HH; depende das capturas reais.']
  # Validação da conversão, sem gerar imagem de destino nem escrever em hardware.
  preset_to_struct(preset)
  presets.append(preset);analyses.append(a)
  provenance.append({'role':role,'candidate_id':candidate,'source':source,'start_seconds':row['start_seconds'],'end_seconds':row['end_seconds'],'analysis':a.model_dump(mode='json'),'compiler_adjustments':changes})
 pair=PresetPair(track_id=uuid4(),rhythm_preset=presets[0],lead_preset=presets[1],analysis_summary='Piloto R1: base e solo derivados de referências diferentes; presets experimentais gerados por regras, não treinamento de matching.')
 a=analyses[0]
 analysis={'gain_character':a.effect_estimates.gain_character.value,'confidence':'low','distortion_level':a.effect_estimates.distortion_level,'estimated_bpm':None,'spectral_profile':{'low':a.overall_spectral.bass_energy,'low_mid':a.overall_spectral.low_mid_energy,'mid':a.overall_spectral.mid_energy,'high_mid':a.overall_spectral.high_mid_energy,'high':a.overall_spectral.treble_energy,'brightness':a.overall_spectral.brightness},'effect_presence':{'reverb_probability':False,'delay_probability':False}}
 exported={'format':'ai-tone-studio','version':1,'id':str(pair.rhythm_preset.id),'rhythm_preset':_serialize_preset(pair.rhythm_preset),'lead_preset':_serialize_preset(pair.lead_preset),'analysis':analysis,'experimental_metadata':{'label':'Piloto R1 — não validado auditivamente','generator':'heuristico_catalogo_0.4.0','separation':'htdemucs_6s','independent_references':True}}
 OUT.mkdir(parents=True)
 (OUT/'Infest_MK300_Piloto_R1.json').write_text(json.dumps(exported,ensure_ascii=False,indent=2)+'\n')
 (OUT/'modelo_completo.json').write_text(pair.model_dump_json(indent=2))
 (OUT/'proveniencia.json').write_text(json.dumps({'schema_version':1,'inputs':provenance,'catalog_version':loader.get_catalog_version(DeviceModel.MK300),'catalog_file_sha256':sha(ROOT/'catalogs/mk300/catalog.json') if (ROOT/'catalogs/mk300/catalog.json').exists() else None,'compiled_on':'2026-10-22','pedal_write_performed':False},ensure_ascii=False,indent=2)+'\n')
 guide='PRESETS INICIAIS EXPERIMENTAIS — INFEST / MK300\n\nImportar o arquivo Infest_MK300_Piloto_R1.json no aplicativo com importação JSON.\nNão é um arquivo nativo do M-EFCS. Os dois presets usam referências distintas.\n\n'+pair.rhythm_preset.to_readable_guide()+'\n\n'+pair.lead_preset.to_readable_guide()
 (OUT/'GUIA_PARAMETROS.txt').write_text(guide)
 print('Gerados:',OUT)
 for p in presets:
  print(p.name,[(b.model_name,b.enabled,{x.name:x.raw_value for x in b.parameters}) for b in p.effect_chain.blocks])
if __name__=='__main__':main()
