#!/usr/bin/env python3
"""Build documentation artifacts only. Requires Markdown in the tool environment.

From repository root:
PYTHONPATH=/tmp/ai-tone-doc-tools backend/.venv/bin/python docs/architecture/revisao-v1.6.1/gerar_documentacao.py

The API is imported to inspect OpenAPI; no HTTP request, worker or database write.
PDF export is a separate browser print step documented in README.md.
"""
import ast
import hashlib
import html
import json
from pathlib import Path
import re
import sys
import textwrap
import xml.etree.ElementTree as ET
import markdown

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / 'backend'))
from app.main import app


def save_json(name, value):
    (HERE / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


schema = app.openapi()
save_json('openapi-v1.6.1.json', schema)
methods = {'get', 'post', 'put', 'patch', 'delete'}
operations = [
    {'method': method.upper(), 'path': path, 'summary': operation.get('summary'),
     'operation_id': operation.get('operationId'),
     'responses': sorted(operation.get('responses', {}))}
    for path, item in schema['paths'].items()
    for method, operation in item.items() if method in methods
]
save_json('inventario-api.json', {'version': schema['info']['version'], 'count': len(operations),
                                 'operations': operations})

catalogs = {}
for device in ['mk20', 'mk300']:
    path = ROOT / 'catalogs' / device / 'catalog.json'
    catalog = json.loads(path.read_text())
    asset = ROOT / 'android/assets' / f'{device}_catalog.json'
    catalogs[device] = {
        'path': str(path.relative_to(ROOT)), 'metadata': catalog.get('_meta', catalog.get('metadata', {})),
        'android_asset_json_equal': catalog == json.loads(asset.read_text()),
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'blocks': {name: {'model_count': len(block.get('models', block.get('selected_models', []))),
                          'block_id': block.get('block_id')}
                   for name, block in catalog.get('blocks', {}).items()},
    }
save_json('inventario-catalogos.json', catalogs)

sources = []
paths = sorted((ROOT / 'backend/app').rglob('*.py')) + sorted((ROOT / 'android/lib').rglob('*.dart'))
paths += sorted((ROOT / 'android/android/app/src/main/kotlin').rglob('*.kt'))
for path in paths:
    text = path.read_text()
    symbols = []
    if path.suffix == '.py':
        for node in ast.walk(ast.parse(text)):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                symbols.append({'name': node.name, 'line': node.lineno, 'kind': type(node).__name__})
    else:
        for line, value in enumerate(text.splitlines(), 1):
            match = re.search(r'\bclass\s+(\w+)', value)
            if match:
                symbols.append({'name': match.group(1), 'line': line, 'kind': 'class'})
    sources.append({'path': str(path.relative_to(ROOT)),
                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'symbols': symbols})
save_json('mapa-fontes.json', {'code_commit': 'b5f036568a965cfe791ff2272480ea98352efe88', 'files': sources})

# Shared model for SVG, Mermaid and diagrams.net: labels/edges stay consistent.
DIAGRAMS = [
 ('01-arquitetura', 'Arquitetura atual — execução local e dispositivo', [
  ('ui', 'Android / Flutter\nTelas, biblioteca e revisão', 30, 50, 'blue'),
  ('api', 'API FastAPI\nValidação, jobs e referências', 430, 50, 'blue'),
  ('engine', 'Motor no notebook\nDemucs + análise + regras', 830, 50, 'blue'),
  ('local', 'Armazenamento Android\nPreferências e backups', 30, 260, 'gray'),
  ('store', 'SQLite + arquivos\nOriginais, stems e gravações', 430, 260, 'gray'),
  ('catalog', 'Catálogos por aparelho\nIDs, categorias e limites', 830, 260, 'gray'),
  ('bridge', 'Kotlin nativo\nMIDI, captura e reprodução', 30, 470, 'green'),
  ('pedal', 'MK20 / MK300\nPreset e áudio processado', 430, 470, 'green'),
  ('research', 'Pesquisa documental\nFontes externas e fichas', 830, 470, 'orange'),
 ], [('ui','api','HTTP / áudio'),('api','engine','orquestra'),('ui','local','persiste'),
     ('api','store','lê / salva'),('engine','catalog','consulta'),('ui','bridge','channels'),
     ('bridge','pedal','USB / áudio'),('research','engine','pistas por estado')]),
 ('02-geracao', 'Geração atual — salvar referência e gerar são operações distintas', [
  ('music','Importar música\nTítulo, aparelho e região',30,50,'blue'),
  ('separate','Separar instrumentos\nStem guitar salvo',430,50,'blue'),
  ('features','Analisar a guitarra\nFeatures e descritores',830,50,'blue'),
  ('initial','Geração inicial\nCategorias + fórmulas',830,250,'orange'),
  ('seed','Preset persistido\nBase e solo',430,250,'green'),
  ('listen','Ouvir / escolher trecho\nReferência por papel',30,250,'blue'),
  ('save','Salvar referência\nNão altera o preset',30,450,'orange'),
  ('regenerate','Gerar do áudio salvo\nOu variante por estado',430,450,'blue'),
  ('result','Novo resultado / variante\nRevisar antes de enviar',830,450,'green'),
 ], [('music','separate','mixagem'),('separate','features','guitarra'),('features','initial','caráter'),
     ('initial','seed','salva par'),('seed','listen','reutiliza stem'),('listen','save','PUT referência'),
     ('save','regenerate','ação de geração'),('regenerate','result','reanalisa e mapeia')]),
 ('03-comparacao-envio', 'Comparação e envio — áudio, controles e transporte separados', [
  ('record','Gravar guitarra\nEntrada USB processada',30,50,'blue'),
  ('compare','Comparar referência\nBandas e dinâmica',430,50,'blue'),
  ('review','Revisar sugestões\nEQ conservador',830,50,'orange'),
  ('apply','Aplicar no preset local\nValidar valores anteriores',830,250,'blue'),
  ('prepare','Ler destino e salvar backup\nModelo, nome e slot',430,250,'blue'),
  ('confirm','Confirmar substituição\nOriginal + destino explícitos',30,250,'orange'),
  ('write','Banco + commit + ACKs\nSem repetir escrita',30,450,'blue'),
  ('read','Leitura completa\nComparar imagem gravada',430,450,'blue'),
  ('success','Envio confirmado\nNão comprova timbre fiel',830,450,'green'),
 ], [('record','compare','WAV + preset'),('compare','review','diferenças'),('review','apply','usuário revisa'),
     ('apply','prepare','abrir envio'),('prepare','confirm','backup válido'),('confirm','write','confirmação'),
     ('write','read','aguarda flash'),('read','success','bytes iguais')]),
]
COLORS = {'blue':('#eaf2ff','#3468ac'), 'green':('#e6f5ed','#267b50'),
          'orange':('#fff1db','#ac7425'), 'gray':('#f0f2f5','#626d7b')}
mxfile = ET.Element('mxfile', host='app.diagrams.net', version='24.7.17')
for filename, title, nodes, edges in DIAGRAMS:
    (HERE / 'diagramas' / (filename + '.mmd')).write_text(
        'flowchart TB\n' + '\n'.join(f'  {i}["{label.replace(chr(10), "<br/>")}"]' for i,label,*_ in nodes)
        + '\n' + '\n'.join(f'  {a} -->|"{label}"| {b}' for a,b,label in edges) + '\n')
    positions = {n[0]:(n[2],n[3]) for n in nodes}
    svg = ET.Element('svg', xmlns='http://www.w3.org/2000/svg', viewBox='0 0 1200 620', role='img')
    ET.SubElement(svg,'title').text = title
    defs = ET.SubElement(svg,'defs')
    marker = ET.SubElement(defs,'marker',id='arrow',markerWidth='10',markerHeight='10',refX='8',refY='3',orient='auto',markerUnits='strokeWidth')
    ET.SubElement(marker,'path',d='M0,0 L0,6 L9,3 z',fill='#748399')
    ET.SubElement(svg,'rect',width='1200',height='620',fill='#ffffff')
    ET.SubElement(svg,'text',x='30',y='25',fill='#21344a',style='font: bold 18px sans-serif').text=title
    page=ET.SubElement(mxfile,'diagram',name=filename,id=filename)
    model=ET.SubElement(page,'mxGraphModel',dx='1200',dy='620',grid='1',gridSize='10',page='1',pageWidth='1200',pageHeight='700')
    root=ET.SubElement(model,'root');ET.SubElement(root,'mxCell',id='0');ET.SubElement(root,'mxCell',id='1',parent='0')
    for index,(a,b,label) in enumerate(edges):
        ax,ay=positions[a];bx,by=positions[b]
        if ay==by:
            start=(ax+300,ay+45) if bx>ax else (ax,ay+45)
            end=(bx,by+45) if bx>ax else (bx+300,by+45)
        else:
            start=(ax+150,ay+90) if by>ay else (ax+150,ay)
            end=(bx+150,by) if by>ay else (bx+150,by+90)
        sx,sy=start;ex,ey=end
        lx=(sx+ex)/2;ly=(sy+ey)/2
        anchor='middle'
        route=None
        if filename=='01-arquitetura' and (a,b)==('ui','bridge'):
            route='M30,95 L12,95 L12,515 L30,515'
            lx,ly=67,405
        elif filename=='01-arquitetura' and (a,b)==('research','engine'):
            route='M1130,515 L1175,515 L1175,95 L1130,95'
            lx,ly=1070,410
        if route:
            ET.SubElement(svg,'path',d=route,fill='none',stroke='#748399',**{'stroke-width':'1.8','marker-end':'url(#arrow)'})
        else:
            ET.SubElement(svg,'line',x1=str(sx),y1=str(sy),x2=str(ex),y2=str(ey),stroke='#748399',**{'stroke-width':'1.8','marker-end':'url(#arrow)'})
            if sy==ey: ly-=12
            else: lx+=9;anchor='start'
        ET.SubElement(svg,'text',x=str(lx),y=str(ly+4),fill='#49566a',style='font: 12px sans-serif;paint-order:stroke;stroke:white;stroke-width:3px;stroke-linejoin:round',**{'text-anchor':anchor}).text=label
        edge=ET.SubElement(root,'mxCell',id='e'+str(index),value=label,edge='1',parent='1',source=a,target=b,
                           style='edgeStyle=orthogonalEdgeStyle;rounded=0;html=0;endArrow=block;strokeColor=#748399;')
        ET.SubElement(edge,'mxGeometry',relative='1',**{'as':'geometry'})
    for i,label,x,y,color in nodes:
        fill,border=COLORS[color]
        ET.SubElement(svg,'rect',x=str(x),y=str(y),width='300',height='90',rx='12',fill=fill,stroke=border,**{'stroke-width':'1.5'})
        for row,line in enumerate(label.splitlines()):
            ET.SubElement(svg,'text',x=str(x+150),y=str(y+35+row*23),fill='#21344a',style=f'font: {"bold " if row==0 else ""}16px sans-serif',**{'text-anchor':'middle'}).text=line
        cell=ET.SubElement(root,'mxCell',id=i,value=label,vertex='1',parent='1',style=f'rounded=1;whiteSpace=wrap;html=0;fillColor={fill};strokeColor={border};fontSize=15;')
        ET.SubElement(cell,'mxGeometry',x=str(x),y=str(y),width='300',height='90',**{'as':'geometry'})
    ET.ElementTree(svg).write(HERE/'diagramas'/f'{filename}.svg',encoding='unicode',xml_declaration=False)
ET.ElementTree(mxfile).write(HERE/'diagramas'/'arquitetura-e-fluxos.drawio',encoding='unicode',xml_declaration=True)

source = (HERE/'DOCUMENTACAO_TECNICA_E_LOGICA.md').read_text()
body=markdown.markdown(source,extensions=['tables','fenced_code','toc','sane_lists'])
# Inline vector images so the HTML remains a single offline artifact.
for filename,*_ in DIAGRAMS:
    pattern=r'<img alt="([^"]*)" src="diagramas/'+filename+r'\.svg"\s*/?>'
    svg=(HERE/'diagramas'/f'{filename}.svg').read_text()
    body=re.sub(pattern,lambda m:'<figure>'+svg+'<figcaption>'+html.escape(m.group(1))+'</figcaption></figure>',body)
style='''
@page {size:A4; margin:17mm 15mm 18mm;} * {box-sizing:border-box;}
body{font-family:Arial,sans-serif;color:#24334a;line-height:1.52;font-size:14px;max-width:1080px;margin:30px auto;padding:0 24px;background:#fff;}
h1{font-size:30px;line-height:1.2;color:#123757;border-bottom:4px solid #2f7d64;padding-bottom:16px;}
h2{font-size:22px;margin-top:36px;color:#123757;border-bottom:1px solid #cbd6e0;padding-bottom:6px;}
h3{font-size:17px;margin-top:23px;} h1,h2,h3{break-after:avoid;}
a{color:#205b8f;} code{font-size:.88em;background:#eef2f6;padding:2px 4px;border-radius:3px;overflow-wrap:anywhere;}
pre{white-space:pre-wrap;} table{border-collapse:collapse;width:100%;font-size:12.5px;margin:16px 0;table-layout:auto;}
th,td{text-align:left;vertical-align:top;padding:9px;border:1px solid #d5dfe8;overflow-wrap:anywhere;}
th{background:#eaf2f7;color:#163c55;} tr{break-inside:avoid;} thead{display:table-header-group;}
figure{margin:18px 0;break-inside:avoid;} figure svg{width:100%;height:auto;max-height:380px;}
figcaption{font-size:11px;color:#607085;text-align:center;} .toolbar{padding:14px;background:#e8f3ed;border-radius:8px;}
@media print {body{font-size:10pt;margin:0;padding:0;max-width:none;} h1{font-size:23pt;}h2{font-size:16pt;}h3{font-size:12pt;}
table{font-size:8.2pt;}th,td{padding:5px;} .toolbar{display:none;} a{text-decoration:none;color:inherit;} figure svg{max-height:290px;}}
'''
(HERE/'DOCUMENTACAO_TECNICA_E_LOGICA.html').write_text('<!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>AI Tone Studio — documentação técnica e lógica V1.6.1</title><style>'+style+'</style><body><aside class="toolbar">Revisão do código V1.6.1 · Documento offline com diagramas vetoriais · Use Imprimir para exportar.</aside>'+body+'</body></html>')
print(f'Documentação gerada: {len(operations)} operações HTTP, {len(sources)} arquivos de código, {len(DIAGRAMS)} diagramas.')
