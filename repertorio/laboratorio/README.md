# Laboratório isolado de referências e separação

## Evolução do motor — MK300 primeiro

O piloto operacional agora acontece pelo aplicativo, na branch `develop`: [Android V1.3.0](../../docs/PILOTO_AUTOMATICO_MK300_V1_3_0.md). A proposta anterior de configuração manual foi substituída. A `main` preserva o baseline V1.2.3; arquivos antigos de experiência permanecem como histórico.

O plano vigente está em [EVOLUCAO_MOTOR_MK300.md](../../docs/architecture/EVOLUCAO_MOTOR_MK300.md): baseline/captura → schema e busca sonora controlada → dataset/calibração → modelo de resposta → otimização → integração no app. R1 recebeu relato de distorções ruins e permanece preservado como baseline experimental.

Para inventariar capturas sem normalização ou escrita na pedaleira:

```bash
backend/.venv/bin/python repertorio/laboratorio/scripts/avaliar_capturas_mk300.py --output repertorio/laboratorio/relatorios/mk300_capturas_nova_rodada.json
```

A saída não pode existir. O relatório inicial é `relatorios/mk300_capturas_r1.json`; inclui métricas por canal, hashes e metadados pendentes, sem score de fidelidade. Não gera novos presets.

Este diretório é independente do aplicativo. O código Flutter, backend, catálogos, APKs e ambiente `backend/.venv` não foram modificados para instalar os modelos. Nenhuma música foi enviada a um serviço externo: apenas pacotes e pesos foram baixados, e o áudio foi processado localmente.

## Componentes

- `.venv/`: Python próprio, PyTorch 2.5.1 CPU, torchaudio 2.5.1 CPU, Transformers 4.46.3, librosa 0.10.2 e Demucs 4.0.1.
- `requirements.lock.txt`: versões efetivamente instaladas, incluindo dependências transitivas.
- `cache/`: pesos/tokenizador CLAP e checkpoint Demucs. Não é utilizado pelo app.
- `relatorios/estado_inicial.json`: hashes do código/configuração existentes e dos seis originais antes deste trabalho.
- `relatorios/referencias.json`: seleção, timestamps relativos a cada arquivo, hashes, escores por janela e advertências.
- `scripts/preparar_referencias.py`: triagem e recortes a partir dos M4A. Recusa sobrescrever arquivos existentes.
- `scripts/refinar_triagem.py`: registra a substituição dos candidatos de base ambíguos da triagem inicial; guarda o histórico no manifesto.
- `scripts/separar_referencias.py`: separação experimental de um candidato principal em seis fontes, em CPU.
- `scripts/organizar_entrega.py`: atualiza fichas, CSV, fila de separação e páginas locais a partir dos artefatos existentes. Preenche apenas campos de ficha vazios e sua seção gerada; preserva os demais campos editados.
- `scripts/validar_entrega.py`: verifica preservação do app e dos originais, WAVs, timestamps, duração, hashes, fila e referências das páginas HTML.

## Método da triagem

Modelo CLAP `laion/clap-htsat-unfused`, revisão `8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a`. Embeddings de janelas de 10 segundos da mixagem (passo 10 segundos) são comparados com descrições de base, solo/destaque, voz, baixo e bateria. Usa seed 0 e processamento local de áudio mono em 48 kHz apenas para ranking; não altera o original.

Ranking: similaridade do papel − 0,35 × similaridade de voz − 0,15 × similaridade do papel oposto. Os fatores são heurísticas desta triagem, sem calibração estatística. Cada papel possui dois textos; usa o maior escore entre eles. Escores não são probabilidades, percentuais de presença ou fidelidade.

Na etapa de refinamento (`refinar_triagem.py`), candidatos de base com escore de baixo maior que base, ou bateria maior que base + 0,10, são substituídos por alternativas da triagem. O manifesto preserva os candidatos anteriores. Mantém centros distantes pelo menos 25 segundos. Os quatro trechos ativos por música têm 20 segundos e são exportados da mixagem para WAV float32 estéreo 44,1 kHz, sem normalização/EQ. Esse formato preserva picos decodificados sem forçar clipping de conversão; não restaura informação perdida na compressão AAC. Os escores se referem à janela central de 10 segundos, não garantem predominância durante os 20 segundos do recorte.

Os candidatos de solo/destaque são especialmente incertos: o modelo não foi treinado/validado para identificar o arranjo destas seis músicas, e em vários casos o texto de base tem escore superior. A aprovação musical é obrigatória. A geração de quatro candidatos não implica que existam duas passagens de solo na música.

## Executar o piloto em um candidato ainda não processado

A partir da raiz do projeto:

```bash
repertorio/laboratorio/.venv/bin/python repertorio/laboratorio/scripts/separar_referencias.py --track 01 --role base
```

Se já houver saída, o comando recusa sobrescrever. `--role solo_destaque` seleciona o primeiro candidato dessa função proposta. Os scripts determinam caminhos relativos à própria localização, não dependem do diretório atual. Modelos ficam em cache local do laboratório.

Para gerar as páginas novamente após processar outros candidatos:

```bash
repertorio/laboratorio/.venv/bin/python repertorio/laboratorio/scripts/organizar_entrega.py
repertorio/laboratorio/.venv/bin/python repertorio/laboratorio/scripts/validar_entrega.py
```

## Recriar o ambiente em outro diretório

Use um novo venv, nunca o venv do backend. Primeiro instale PyTorch e torchaudio da distribuição CPU, depois as versões do lock:

```bash
python3 -m venv /caminho/novo-venv
/caminho/novo-venv/bin/pip install 'torch==2.5.1+cpu' 'torchaudio==2.5.1+cpu' --index-url https://download.pytorch.org/whl/cpu
/caminho/novo-venv/bin/pip install -r repertorio/laboratorio/requirements.lock.txt
```

Pré-requisito externo: FFmpeg/ffprobe. A regeneração da triagem em uma pasta já preenchida não é destrutiva: ela recusa sobrescrever recortes. Para nova rodada, use uma cópia de trabalho e uma nova localização de saída, preservando o manifesto anterior.

## Fontes e limites

- [CLAP oficial](https://github.com/LAION-AI/CLAP) e [modelo utilizado](https://huggingface.co/laion/clap-htsat-unfused): representação áudio/texto para triagem sem treino específico neste repertório.
- [Demucs oficial](https://github.com/facebookresearch/demucs): `htdemucs_6s` é uma referência experimental de seis fontes. Repositório original arquivado; esta instalação é um piloto com versões fixadas, não uma migração do backend.
- [Music AI — separação avançada](https://music.ai/modules/stem-separation/musical-stems-advanced/): candidato futuro para comparar separação dedicada de base/solo. Não houve chamada de API, upload de áudio ou contratação.

As bibliotecas e os pesos preservam suas licenças próprias; consulte as fontes antes de redistribuir ou integrar comercialmente. Esta entrega não treina um gerador de presets nem valida a fidelidade sonora de nenhum preset.

O `.dockerignore` na raiz exclui apenas `repertorio/` do contexto de build, evitando incluir áudios, venv e pesos na imagem do backend. Os caminhos copiados pelo Dockerfile existente permanecem disponíveis.

## Infest — referências aprovadas em 22/10/2026

O organizador preserva a aprovação dos dois trechos principais em `fase_1/01/APROVACAO_REFERENCIAS.json`, sem aprovar a qualidade dos stems. `comparar_infest.py` processou somente esses dois trechos com contexto extra e criou seis cópias de escuta com RMS equivalente. O script exige aprovação e não sobrescreve a pasta de saída. Veja `../fase_2/infest_comparacao/README.md`. Nenhum outro candidato recebeu nova inferência nesta rodada.

## Piloto R1 — geração e importação

`gerar_presets_infest.py` utiliza o ambiente do backend somente para importar e executar as classes existentes; não instala pacotes nele nem escreve no SQLite. Produz o par experimental, análises independentes e guia em `fase_1/01/presets/piloto_r1/`. A separação é neural, a geração de parâmetros permanece heurística.

Para carregá-lo no celular foi acrescentada importação JSON local no Android V1.2.3. O backend e os catálogos existentes permanecem V1.2.2/0.4.0. `relatorios/atualizacao_android_v1_2_3.json` registra exatamente as quatro mudanças em arquivos do baseline original; o validador conserva os hashes antigos e confere os novos hashes esperados dessa atualização, em vez de apagar o histórico. O protocolo de envio permanece o mesmo.
