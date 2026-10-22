# Evolução em develop — piloto automático MK300

Android **1.3.2+11**: [importar um preset da MK300 por USB e comparar com o preset gerado pela música](docs/REFERENCIA_PEDAL_V1_3_2.md). Referência auxiliar, sem escrita no pedal e sem substituir a geração a partir do áudio.

Android **1.3.1+10**: [limpeza das rodadas antigas e geração sem duplicatas](docs/LIMPEZA_PILOTO_V1_3_1.md). A limpeza solicitada acontece uma vez ao abrir a atualização; análises de origem são preservadas.

Android **1.3.0+9**: geração de candidatos de Infest pelo app, com envio pelo fluxo existente e preservação da biblioteca. A `main` permanece no baseline V1.2.3. Consulte [fluxo, limites e validação](docs/PILOTO_AUTOMATICO_MK300_V1_3_0.md). A documentação anterior abaixo registra as versões de origem.

# AI Tone Studio — Android V1.2.3 / API V1.2.2

Aplicativo Flutter para Android com backend Python/FastAPI. Importa áudio, mede características da gravação e sugere presets independentes de base e solo para M-VAVE MK20/MK300. Inclui envio de presets MK300 por USB MIDI e comparação orientativa de timbre.

## Importação local na V1.2.3

O ícone de arquivo na tela inicial importa pares MK300 em JSON do AI Tone Studio, com confirmação e novos IDs para preservar a biblioteca. Funciona offline e valida modelos/valores contra catálogo local. Não envia nada ao pedal até você seguir o fluxo existente de transferência.

[Instruções da importação](docs/IMPORTACAO_PRESETS_V1_2_3.md). O [Piloto R1 de Infest](repertorio/fase_1/01/presets/piloto_r1/README.md) fornece os primeiros presets de base e solo derivados de análises independentes das guitarras extraídas. Separação por IA; geração de parâmetros ainda heurística e sem fidelidade sonora validada.

## Resultado e atualização na V1.2.2

Após comparar a gravação USB, abre automaticamente **Resultado e ajustes**. Mostra avaliação clara (ajustes, EQ sem mudanças recomendadas ou captura saturada), diferenças medidas e valores antes/depois. **Atualizar preset e seguir para envio** salva as mudanças aceitas no mesmo preset da biblioteca e abre a transferência da guitarra selecionada. Clipping exige nova gravação, com motivo e orientação no topo, sem aplicar sugestões sobre a captura saturada.

[Roteiro da V1.2.2](docs/RESULTADO_AJUSTES_V1_2_2.md). Captura USB de 10 segundos na MK300 relatada pelo usuário; proximidade sonora segue sem validação auditiva automática.

## Referência e confiança na V1.2.1

- Mantém importação da música completa como padrão; opção **Analisar apenas um trecho** permite escolher início e duração de 3–120 segundos. Base e solo partem desse mesmo trecho.
- Referência declarada como guitarra isolada pode receber confiança geral/de ganho média quando tem pelo menos 10 segundos, sinal audível e sem clipping significativo. Mixagem e stem Demucs `other` continuam com confiança baixa.
- Confiança é qualitativa sobre a estimativa, não fidelidade ao original. Toque no selo para ver a justificativa; não há aumento artificial dos níveis nem identificação do equipamento.
- Solo deixa de forçar amp/cabinet de lead e drive em referência limpa. Chorus não é identificado pela mudança das notas. Sugestões de modulação sem evidência suficiente permanecem desligadas. Noise gate passa a ser explicitamente uma sugestão de controle de ruído.
- Reanalise os áudios para obter a nova geração; presets existentes não são sobrescritos.

[Como testar a V1.2.1](docs/REFERENCIA_CONFIANCA_V1_2_1.md).

## Novidades da V1.2.0

- Sucesso após leitura de retorno: **Preset <nome enviado> enviado com sucesso**, com retorno à tela inicial. Falhas mostram o erro e mantêm a tela de envio.
- Na tela dos presets, **Gravar e comparar meu timbre** captura 3–30 segundos de guitarra, priorizando USB/OTG da pedaleira. Microfone e importação de gravação também disponíveis.
- Comparação com trecho escolhido do áudio original ou perfil geral salvo de uma análise recente. Sugere pequenos ajustes de Bass/Middle/Treble dentro do catálogo, com salvamento opcional na biblioteca e posterior reenvio.
- A análise usa DSP heurístico, com confiança baixa; não é um modelo treinado nem mede uma porcentagem validada de semelhança. Captura USB requer teste no celular/pedal.

Veja [instruções e limitações da V1.2.0](docs/GRAVACAO_COMPARACAO_V1_2_0.md). APK e backend devem estar na V1.2.0 para a comparação.

## Biblioteca e envio na V1.1.1

- Seleção de qualquer música/análise salva na tela de transferência; base e solo aparecem com seus nomes completos e modelo de pedaleira.
- Presets MK300 são selecionados inicialmente quando disponíveis, evitando iniciar pelo preset MK20 em uma sessão de envio MK300.
- Escolher outro preset para a mesma pedaleira preserva a conexão verificada, mas exige novo backup/confirmacão para o novo preset.
- Preset antigo tem bloqueio explícito e botão **Gerar preset atualizado**, que abre a importação com título/artista e dispositivos preenchidos. Selecione novamente o arquivo: o áudio temporário não fica armazenado.
- Menu de ações na biblioteca: abrir, escolher preset e enviar, excluir análise. A exclusão é confirmada e remove os dois presets da análise (base e solo) apenas do aplicativo; pedal e backups não mudam.
- O botão de backup informa o motivo de estar desabilitado: versão de catálogo, modelo, conexão, nome, slot ou MTU.

A leitura USB da MK300 foi relatada pelo usuário em 12/10/2026, com V75 informada na interface; o envio foi posteriormente confirmado pelo usuário como funcionando. O bloqueio mostrado nas capturas vinha do preset antigo, não de uma falha da leitura. Veja o [roteiro da V1.1.1](docs/TESTE_V1_1_1.md).

## Conectividade da V1.1.0

- USB MIDI Android e Bluetooth GATT M-EFCS implementados em Kotlin, sem transporte simulado no aplicativo.
- MK300: fluxo de leitura, validação de layout, seleção de slot 1–160, renomeação, backup, confirmação de sobrescrita, envio e comparação de 448 bytes por leitura de retorno. Envio USB relatado como funcionando pelo usuário; BLE é experimental e exige serviço AE40/AE41/AE42 e MTU ≥ 466.
- MK20: descoberta/conexão de transporte e renomeação local disponíveis; gravação bloqueada porque falta captura comprovada de seu protocolo/perfil. Seu preset oficial tem 412 bytes, diferente da MK300.
- Nome original do arquivo preservado nos metadados e usado como título quando nenhum título é informado. Nomes completos permanecem no app; o nome enviado à MK300 aceita 1–19 caracteres ASCII.
- Catálogo MK300 0.4.0: 359 modelos e posições de knobs conferidos na referência comunitária. Presets antigos continuam consultáveis, mas devem ser reanalisados antes de transferir.

A fonte USB foi capturada em MK300 V73. O site oficial lista MK300 V75 e MK20 V085 em 12/10/2026. Não foi executada atualização de firmware; V75 não é apresentada como fisicamente validada. Leia a [investigação e o roteiro de conectividade](docs/CONECTIVIDADE_V1_1_0.md).

## O que está implementado

- Importação de MP3, WAV, FLAC, OGG, M4A e MP4 (limite padrão de 50 MB).
- Escolha independente de pedaleira para base e solo, inclusive a mesma para ambos.
- Upload, consulta do processamento, resultado e mensagens de falha em português.
- Análise real com librosa: espectro, dinâmica, BPM e estimativas heurísticas de distorção/ambiência.
- Compilação de presets usando os modelos cadastrados separadamente para cada dispositivo.
- Editor com ligar/desligar e controles com mínimo, máximo e passo enviados pelo catálogo.
- Salvamento dos presets e das edições no Android. Biblioteca, guia e JSON funcionam sem o backend após salvar.
- Compartilhamento de JSON e texto do guia com os valores atuais, incluindo edições.
- Recuperação da URL configurada ao reabrir o aplicativo.
- SQLite no backend para preservar resultados concluídos após reinício. Os áudios temporários são removidos ao concluir/falhar.

## Correções da V1.0.1

IDs dos pares de presets foram alinhados entre API e aplicativo. Presets antigos com ID vazio recuperam o ID do preset de base, quando presente. O editor agora devolve alterações à biblioteca e as persiste; exportar usa essa versão local. Progresso e erros usam os campos da API, e o polling evita requisições sobrepostas.

O gerador reconhece aliases de parâmetros (`volume` → `Level`, `presence` → `Pres`, `drive` → `Gain`, conforme o modelo). A MK20 usa o módulo `NS` do seu próprio catálogo, com controles `Gate` e `Bias` para AI Gate. Modelos de delay/reverb da MK300 usam a lista cadastrada, em vez de nomes genéricos. Não foram adicionados modelos ou escalas sem fonte.

O processamento DSP ocorre em thread para não bloquear as consultas de status. A autocorrelação do delay usa FFT. Áudios silenciosos ou com menos de um segundo recebem erro legível. Uploads são lidos em blocos e interrompidos ao ultrapassar o limite.

## Limitações e pendências

- As estimativas de áudio são heurísticas, sem métrica calibrada de precisão ou similaridade. Não identificam o equipamento original nem reproduzem o timbre exatamente.
- Base e solo derivam da mesma análise com regras distintas; não há isolamento independente de duas guitarras, segmentação de música ou seleção de trecho.
- Reprodução do arquivo dentro do aplicativo ainda não foi implementada.
- Demucs é opcional e desabilitado nas dependências padrão. O adaptador usa `htdemucs` e o stem `other`, que pode conter guitarra e outros instrumentos. GPU não é requisito do MVP; não foi validada a execução do Demucs nesta revisão.
- Os catálogos estão marcados como `COMMUNITY`; a MK20 é parcial e a MK300 tem os 359 modelos enumerados da referência V73. Limitar valores ao catálogo não comprova que nomes, IDs e escalas correspondem ao firmware físico. Veja [catálogos](catalogs/README.md).
- Presets antigos sem metadados de escala são exibidos, mas seus parâmetros ficam sem controle de edição. Gere novamente para obter as escalas. Presets já perdidos/sobrescritos por versões anteriores não podem ser recuperados.
- BLE/USB e backup/leitura de retorno foram implementados para testar com MK300. Gravação MK20 e identificação automática de firmware não estão disponíveis. A seleção de firmware é informada pelo usuário.
- Existe código de struct/SysEx MK300 baseado na referência comunitária `jpfaria/mvave`; os testes locais verificam software, não comunicação física. Nenhum comando foi enviado a uma pedaleira nesta revisão.
- Regeneração assistida, troca de modelo de efeito, histórico de versões, comparação de gravações e implantação AWS permanecem pendentes.
- Backend destinado ao desenvolvimento local, sem autenticação. Os jobs usam BackgroundTasks, sem fila durável ou retomada. Use um único worker; jobs interrompidos exigem reenvio. Não exponha esta configuração diretamente à internet.

## Executar o backend

Pré-requisitos: Python 3.11/3.12, FFmpeg e libsndfile. No Ubuntu, instale as bibliotecas com:

```bash
sudo apt install ffmpeg libsndfile1
```

```bash
cd /home/adrianobn/ai-tone-studio/backend
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Documentação da API: `http://localhost:8000/docs`. Para desenvolvimento com recarga, acrescente `--reload`; editar arquivos pode interromper análises em andamento.

Configurações opcionais:

| Variável | Padrão | Uso |
|---|---|---|
| `CATALOGS_DIR` | pasta `catalogs` na raiz | Caminho dos catálogos |
| `MAX_UPLOAD_MB` | `50` | Limite de upload |
| `TONE_DATA_DIR` | `backend/data` | Pasta do SQLite |

Resultados da API anteriores a esta atualização, que existiam apenas na memória do processo, não são migrados. Os presets salvos no aplicativo continuam locais.

## Executar o aplicativo e gerar APK

A revisão foi preparada com Flutter 3.24.3 / Dart 3.5.3, Android SDK 35 e Java compatível com o projeto Gradle existente.

```bash
cd /home/adrianobn/ai-tone-studio/android
flutter pub get
flutter run
```

Em **Ajustes**, configure o endereço do computador que executa o backend e toque em **Testar conexão**. O telefone precisa alcançar esse endereço na rede. Para emulador Android, use `http://10.0.2.2:8000`; para telefone, use o IP do computador. O valor inicial mantido no app é `http://192.168.15.8:8000`.

```bash
flutter build apk --release
```

Saída padrão: `android/build/app/outputs/flutter-apk/app-release.apk`. A versão Android é `1.2.3`, build `8` (API permanece `1.2.2`), applicationId `com.aitone.studio`. O APK de teste mantém a assinatura debug usada na V1 anterior. Instale por cima para preservar os dados; não desinstale o aplicativo antes de atualizar.

O app permite HTTP para o backend local. TLS, assinatura de distribuição e publicação em loja não fazem parte desta entrega.

## Docker Compose

Na raiz do projeto:

```bash
docker compose up --build
```

O contexto do Dockerfile foi corrigido para incluir backend e catálogos. O volume `tone-data` preserva o SQLite. Docker não está disponível nesta máquina; o build do contêiner não foi executado nesta revisão.

## Testes

```bash
cd /home/adrianobn/ai-tone-studio/backend
.venv/bin/python -m pytest -q
```

```bash
cd /home/adrianobn/ai-tone-studio/android
flutter analyze
flutter test
```

Os testes de integração do backend codificam um sinal de teste em MP3 com FFmpeg e exercitam upload, análise real, compilação, exportação, erros e recuperação no SQLite. Isso verifica o funcionamento técnico, não a fidelidade musical. Os testes Flutter cobrem modelos, configuração, migração da biblioteca e o fluxo de edição/salvamento com exportação local.

## Estrutura

```text
android/lib/         Telas, modelos, API, armazenamento e tema Flutter
android/test/        Testes de modelos e fluxo de edição
backend/app/api/    Endpoints de upload, jobs, resultados e exportação
backend/app/core/   Pipeline e armazenamento SQLite
backend/app/services/  Análise, carregamento de catálogo e compilação
backend/app/transport/ Struct e frames SysEx MK300 (sem transporte Android)
backend/tests/      Catálogos, presets, protocolo e integração com áudio
catalogs/           Catálogos separados MK20 e MK300
docs/               Notas de entrega e roteiro de teste
```

## API principal

| Método | Rota | Resultado |
|---|---|---|
| GET | `/api/v1/health` | Status e versão |
| GET | `/api/v1/devices` | Catálogos disponíveis |
| POST | `/api/v1/analyze` | `job_id` para consultar |
| GET | `/api/v1/jobs/{job_id}` | Status, etapa, erro e `pair_id` |
| GET | `/api/v1/presets/{pair_id}` | Par, análise e escalas dos parâmetros |
| GET | `/api/v1/presets/{pair_id}/export/json` | Configuração original do backend |
| GET | `/api/v1/presets/{pair_id}/export/guide` | Guia original do backend |

Edições do aplicativo ficam no Android. As exportações feitas pelo aplicativo incluem as edições; os endpoints do backend retornam a versão original gerada. O JSON exportado pelo app é um formato próprio, não um arquivo nativo importável no M-EFCS.

Entrega atual: [APK V1.2.3](releases/ai-tone-studio-v1.2.3.apk), com [resultado e atualização](docs/RESULTADO_AJUSTES_V1_2_2.md), com [roteiro de referência/confiança](docs/REFERENCIA_CONFIANCA_V1_2_1.md) e [gravação/comparação](docs/GRAVACAO_COMPARACAO_V1_2_0.md). Veja o [roteiro de conectividade](docs/CONECTIVIDADE_V1_1_0.md). A [V1.0.1](releases/ai-tone-studio-v1.0.1.apk) e seu [roteiro](docs/TESTE_V1_0_1.md) continuam preservados.
