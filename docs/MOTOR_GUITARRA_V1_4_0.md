# Motor de guitarra — Android/API 1.4.0

## Objetivo e arquitetura

A entrada continua sendo a música enviada pelo aplicativo. O novo fluxo não depende do nome da música, de um preset de fábrica importado nem de um LLM inventando controles. A IA executa a separação; DSP e regras produzem estimativas iniciais compatíveis com o catálogo. A qualidade sonora ainda precisa ser verificada na MK300.

Tecnologias preservadas: Flutter/Dart na interface, Kotlin/AudioRecord e MIDI USB no Android, FastAPI/Pydantic/SQLite em Python no backend, librosa/NumPy/SciPy/soundfile/FFmpeg para áudio. Demucs 4.0.1 roda em outro processo e ambiente virtual, sem instalar PyTorch na API.

Arquivos introduzidos em `backend/app/services/tone_engine/`:

- `preprocess.py`: decodificação FLOAT32 estéreo a 44,1 kHz, recorte antes da separação, sem normalização de volume.
- `separation.py`: interface de provider, Demucs dedicado à guitarra, limite de uma separação simultânea e cache persistente com SHA256.
- `separation_worker.py`: processo CPU de seis fontes, recuperando a escala de amplitude após o processamento interno do modelo.
- `features.py`: RMS, pico/clipping nativos, crest factor, faixa de RMS, ataque, centroide/rolloff/flatness/flux/contrast/ZCR/MFCC e oito bandas relativas entre 80 Hz e 12 kHz. Extração em canal representativo para evitar cancelamento de fase entre L/R.
- `descriptor.py`: representação intermediária independente do pedal.
- `engine.py`: classificação e tradução heurísticas, sem renderer calibrado.
- `validation.py`: validação por aparelho, modelo, nome, parâmetro, faixa e passo. Falta de informação necessária retorna `NEEDS_DEVICE_DATA`.
- `candidates.py`: até cinco alternativas de amplificador da mesma família catalogada, amostradas ao longo do catálogo. A ordem não é um ranking acústico e não há score de similaridade inventado.

`core/pipeline.py` e `api/routes.py` integram o motor como `engine_mode=guitar_v2`. Aplicativos anteriores que não enviam essa opção mantêm o pipeline anterior. O novo APK usa o motor v2. Catálogos existentes não foram reescritos; MK20 segue com catálogo parcial e transmissão bloqueada. Os testes de MK20 verificam compatibilidade com os dados catalogados, não confirmam escalas físicas que ainda precisam de investigação.

## Uso no aplicativo

1. Instalar `releases/ai-tone-studio-v1.4.0-develop.apk` por cima da versão atual, sem desinstalar.
2. Abrir **Nova análise**, selecionar a música original e marcar **Música com outros instrumentos**. Para uma trilha já isolada, selecionar **Somente guitarra, já isolada**, pulando a separação.
3. Para o piloto Infest, selecionar o trecho da base: início **50**, duração **20** segundos. Ativar outro trecho para o solo: início **160**, duração **20** segundos. Selecionar **MK300 para ambas as partes** durante o piloto.
4. Gerar: o app informa as etapas e continua consultando o job. Uma música completa também é aceita, mas a execução em CPU pode levar muito mais tempo que o áudio. Recomenda-se começar pelos trechos já aprovados.
5. Na tela de presets, **Exportar guitarra separada** permite compartilhar/salvar o WAV de cada referência. **Comparar alternativas de amplificador** troca o amplificador na mesma entrada da biblioteca, sem criar cinco itens adicionais. A escolha fica local, como a edição atual de presets; o backend preserva os candidatos originais.
6. Seguir pelo envio USB existente, com leitura do destino e backup. Depois gravar a mesma passagem pelo USB-AUDIO e comparar. Os perfis de guitarra de base e solo ficam associados à nova análise no backend; não é necessário selecionar o original novamente para essa comparação.

Os presets novos partem de Level AMP 40, CAB 60 e volume global do preset MK300 40. São níveis iniciais conservadores, não uma calibração de loudness e não uma correção comprovada para a captura USB. Ganho não é usado como controle de volume. A gravação saturada anterior não foi modificada nem recuperada artificialmente. O detector passa a medir pico/clipping antes da reamostragem.

## Separação: o que está efetivamente disponível

O provider utiliza `htdemucs_6s`: `guitar`, `vocals`, `drums`, `bass`, `piano` e `other`. O modelo é experimental, conforme a [documentação oficial do Demucs](https://github.com/facebookresearch/demucs). O stem guitar pode manter base e solo juntos. Trechos distintos selecionam partes da música, não equivalem a um modelo de separação entre guitarristas.

Falha, timeout ou indisponibilidade do provider interrompe a geração no modo v2. Não se apresenta um preset feito da mixagem como se a guitarra tivesse sido isolada. Vazamento e qualidade da separação são registrados como **não verificados**, sem números inventados.

No computador atual, reutiliza-se o ambiente já instalado em `repertorio/laboratorio/.venv` e os pesos em `repertorio/laboratorio/cache/torch`. Em outro computador configurar:

```bash
export TONE_DEMUCS_PYTHON=/caminho/ambiente-demucs/bin/python
export TORCH_HOME=/caminho/cache-torch
```

O ambiente deve conter Demucs 4.0.1, torch, NumPy e soundfile. O lock existente `repertorio/laboratorio/requirements.lock.txt` registra o ambiente do laboratório. FFmpeg precisa estar no PATH da API. Não copiar ambientes virtuais entre sistemas; recriá-los. Sem pesos em cache, o modelo poderá precisar de download no primeiro processamento.

## Persistência e API

Preservar todo `TONE_DATA_DIR` (padrão `backend/data`) em backups:

- `generation_inputs/<sha256>.<ext>`: bytes originais enviados em novas análises v2; uploads idênticos são reutilizados.
- `separations/<cache-id>/`: seis WAVs FLOAT32 e manifest com modelo, configuração, hash de entrada e hashes das saídas. Não há exclusão automática desse cache nesta versão.
- SQLite: pares, features, descriptor, diagnósticos, candidatos e referências por função.
- `recordings/`: capturas reais da guitarra preservadas desde 1.3.4.

Áudios, pesos, cache, banco e APK não entram no Git. O cache elimina nova inferência para o mesmo áudio decodificado/trecho e configuração; não deduplica novas análises solicitadas explicitamente na biblioteca.

Endpoints adicionais:

- `GET /api/v1/presets/{pair_id}/stems/{rhythm|lead}/{guitar|vocals|drums|bass|piano|other}`
- `GET /api/v1/presets/{pair_id}/candidates/{rhythm|lead}`

O download só atende instrumentos e funções permitidos, arquivos associados ao par e SHA256 correspondente. A disponibilidade dos instrumentos é mantida após reinício junto dos dados persistidos.

Exemplo de requisição com WAV real:

```bash
curl -F 'file=@/caminho/musica.wav' \
  -F engine_mode=guitar_v2 -F source_kind=mix \
  -F rhythm_device=MK300 -F lead_device=MK300 \
  -F excerpt_start=50 -F excerpt_duration=20 \
  -F lead_start=160 -F lead_duration=20 \
  http://localhost:8000/api/v1/analyze
```

Consultar `/api/v1/jobs/{job_id}` até concluir e então `/api/v1/presets/{pair_id}`. Para testar MK20, trocar o dispositivo; isso não habilita gravação no pedal MK20. O exemplo JSON de saída com o trecho real está em `docs/exemplos/motor-v2-infest-mk20.json`.

## Limites e próximas etapas

Esta entrega integra o núcleo da Sprint 1 e a separação/recortes da Sprint 2 do prompt. Não implementa todo o programa de cinco sprints.

- Features medidas não revelam os knobs nem o equipamento original. A distorção é um proxy combinando cruzamentos por zero, distribuição harmônica/espectral e dinâmica. Masterização, artefatos, guitarras sobrepostas e instrumento do usuário afetam a estimativa.
- Confiança permanece qualitativa/baixa; não mede proximidade ao original. Sem dados verdadeiros de stems, `bleed_estimate` é nulo. Sem forward model, `optimization_score` é nulo.
- LUFS/LRA, modelagem temporal confiável, separação base/solo simultâneos e perfil calibrado de captadores não estão implementados. RMS range não é apresentado como LRA. MOD/DLY/REV e compressor ficam desligados neste modo enquanto a evidência não é suficiente.
- Cortes de gabinete usam defaults registrados no catálogo do próprio aparelho. Não se converte rolloff em uma frequência física inventada: a curva dos controles ainda precisa ser calibrada. EQ residual fica para depois da caracterização de AMP/CAB.
- O catálogo valida existência e faixa conhecida; não demonstra a resposta sonora de um modelo nem confirma que os imports NAM/IR do usuário são iguais ao modelo de fábrica.
- Não existe renderer nem otimizador acústico nesta entrega. Primeiro validar as referências extraídas por audição, obter captura sem clipping e avaliar os candidatos na MK300. Depois coletar DI/saída com parâmetros registrados, treinar o forward model de features e otimizar escolhas discretas antes dos controles contínuos.
- Nenhuma escrita real no pedal foi executada pelos testes. Fidelidade sonora e efeito do volume global sobre o USB dependem do teste físico do usuário.

## Validação desta entrega

- 93 testes de backend e 62 testes Flutter passaram; `flutter analyze` sem problemas.
- Execução real do original Infest com base 50–70 s e solo 160–180 s, separação neural concluída e geração MK300 pela API. Downloads de guitarra por função e cinco alternativas por função conferidos. Executado em diretório de dados isolado, sem inserir análises de teste na biblioteca do usuário.
- Os dois caches de separação desses trechos reais foram disponibilizados em `backend/data/separations/`, permitindo reaproveitamento quando o mesmo arquivo/trechos forem enviados pelo app.
- Exemplo MK20 produzido com o mesmo trecho real, validado contra o catálogo e documentado em JSON. Sem transmissão física.
- APK release 1.4.0+14 gerado, mesmo applicationId e certificado debug das entregas anteriores. Hash em `releases/ai-tone-studio-v1.4.0-develop.apk.sha256`.
- Esses testes demonstram funcionamento do fluxo e compatibilidade com o catálogo. Não constituem aprovação da fidelidade sonora dos presets.
