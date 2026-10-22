"""Comparação DSP orientativa. Não identifica equipamentos nem calcula similaridade."""
import math
import numpy as np
import librosa
from pathlib import Path
from ...models.devices import DeviceModel
from ..device_catalog.loader import CatalogLoader

BANDS = {'bass': (80, 250), 'middle': (250, 2500), 'treble': (2500, 8000)}

def fingerprint(y, sr=22050):
    y=np.asarray(y,dtype=float)
    if len(y)<sr*3 or not np.isfinite(y).all():
        raise ValueError('Grave pelo menos 3 segundos de áudio válido.')
    peak=float(np.max(np.abs(y)))
    rms=float(np.sqrt(np.mean(y*y)))
    if rms<0.001:
        raise ValueError('Gravação muito baixa ou silenciosa. Confira a saída USB processada e grave novamente.')
    clipped=float(np.mean(np.abs(y)>=0.99))
    signal=y/(rms+1e-12)
    spectrum=np.abs(librosa.stft(signal))**2
    frequencies=librosa.fft_frequencies(sr=sr)
    energies={key:float(spectrum[(frequencies>=low)&(frequencies<high)].sum()) for key,(low,high) in BANDS.items()}
    total=sum(energies.values())+1e-12
    return {'version':1,'duration_seconds':len(y)/sr,'bands_db':{k:10*math.log10(max(v/total,1e-9)) for k,v in energies.items()},
            'crest_db':20*math.log10(max(peak/rms,1)),'peak_dbfs':20*math.log10(max(peak,1e-9)),
            'clipped_fraction':clipped,'flatness':float(librosa.feature.spectral_flatness(S=spectrum,power=1.0).mean()),
            'zcr':float(librosa.feature.zero_crossing_rate(signal).mean())}

def measure(path:Path, start=0, seconds=31):
    y,sr=librosa.load(str(path),sr=22050,mono=True,offset=start,duration=seconds)
    result = fingerprint(y,sr)
    native, native_sr = librosa.load(str(path),sr=None,mono=False,offset=start,duration=seconds)
    result['clipped_fraction'] = float(np.mean(np.abs(native)>=0.9999))
    result['peak_dbfs'] = 20*math.log10(max(float(np.max(np.abs(native))),1e-9))
    return result

def compare(reference, recorded, preset, catalog:CatalogLoader, input_kind='usb', reference_kind='mix'):
    if reference.get('version')!=1 or set(reference.get('bands_db',{}))!=set(BANDS):
        raise ValueError('Perfil de referência indisponível. Selecione o arquivo original para comparar.')
    try:device=DeviceModel(preset['device'])
    except (KeyError,ValueError):raise ValueError('Dispositivo do preset inválido.')
    if not catalog.is_supported(device) or preset.get('catalog_version')!=catalog.get_catalog_version(device):
        raise ValueError('Gere novamente este preset com o catálogo atual antes de sugerir ajustes.')
    chain=preset.get('effect_chain',[])
    amp=next((b for b in chain if b.get('effect_type')=='amp' and b.get('enabled',True)),None)
    if amp is None:raise ValueError('O preset precisa ter um amplificador ligado para sugerir ajustes.')
    data=catalog._catalogs[device]
    models=data.get('blocks',{}).get('AMP',{}).get('models',[]) or data.get('amp_models',{}).get('models',[])
    model=next((m for m in models if str(m['id'])==str(amp.get('model_id')) and m['name']==amp.get('model_name')),None)
    if model is None:raise ValueError('Amplificador/ID não corresponde ao catálogo do dispositivo.')
    specs={**catalog._get_amp_params(data),**model.get('params',{})}
    limitations=['Comparação DSP heurística, sem modelo treinado de timbre e sem percentual de similaridade validado.',
        'Toque a mesma passagem da referência. Guitarra, captadores, execução e cadeia de gravação alteram o resultado.']
    if reference_kind=='separated_guitar':limitations.append('Referência extraída por IA; vazamentos, artefatos e guitarras sobrepostas ainda podem influenciar a comparação.')
    if reference_kind=='mix':limitations.append('A referência é uma mixagem: baixo, bateria, voz e masterização influenciam as medições. As sugestões são conservadoras.')
    if input_kind=='microphone':limitations.append('Microfone, ambiente e caixa acústica influenciam o espectro. Prefira a saída USB processada.')
    differences={k:round(recorded['bands_db'][k]-reference['bands_db'][k],2) for k in BANDS}
    suggestions=[]
    observations=[]
    if recorded['clipped_fraction']>=0.005:
        return {'confidence':'low','quality':'clipped','summary':'A gravação tem clipping. Reduza o nível de entrada e grave novamente antes de ajustar o preset.',
            'differences_db':differences,'suggestions':[],'limitations':limitations,'recording':recorded,'reference':reference}
    labels={'bass':'graves','middle':'médios','treble':'agudos'}
    knobs={'bass':'Bass','middle':'Middle','treble':'Treble'}
    for band,delta in differences.items():
        if abs(delta)<3:continue
        observations.append(f'{labels[band].capitalize()}: energia relativa {abs(delta):.1f} dB {"acima" if delta>0 else "abaixo"} da referência.')
        knob=knobs[band]
        if knob not in amp.get('parameters',{}) or knob not in specs:continue
        value=float(amp['parameters'][knob]);spec=specs[knob]
        minimum=float(spec.get('min',0));maximum=float(spec.get('max',100));step=float(spec.get('step',1))
        if not np.isfinite(value) or not minimum<=value<=maximum:raise ValueError(f'Parâmetro {knob} inválido.')
        change=max(step,round((maximum-minimum)*0.03))
        proposed=max(minimum,min(maximum,round((value+(-change if delta>0 else change)-minimum)/step)*step+minimum))
        if proposed!=value:suggestions.append({'slot':str(amp['slot']),'effect_type':'amp','model_id':str(amp['model_id']),
            'parameter':knob,'before':value,'after':proposed,'min':minimum,'max':maximum,
            'reason':f'{"Reduzir" if delta>0 else "Aumentar"} {knob} em um passo conservador; {labels[band]} diferem da referência.'})
    crest_delta=recorded['crest_db']-reference['crest_db']
    if abs(crest_delta)>=4:observations.append('A dinâmica difere da referência; execução e compressão da mixagem também podem explicar essa diferença.')
    # Saturação, delay e reverb não são identificados de forma confiável nesta comparação.
    summary=' '.join(observations) if observations else 'Não foi detectada diferença espectral suficiente para sugerir ajustes conservadores. Isso não comprova timbre idêntico.'
    return {'confidence':'low','quality':'ok','summary':summary,'differences_db':differences,'suggestions':suggestions,
            'limitations':limitations,'recording':recorded,'reference':reference,'method':'relative-band-power-v1'}
