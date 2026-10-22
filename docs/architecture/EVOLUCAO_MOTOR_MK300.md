# Evolução do motor: qualidade sonora demonstrada na MK300

Decisão de 22/10/2026: adotar a arquitetura proposta pelo usuário, antecipando validação no equipamento e calibração em relação à otimização automática. Piloto restrito a Infest, trechos aprovados de base 50–70 s e solo/destaque 160–180 s. Outras músicas e escrita na MK20 permanecem fora desta etapa.

## Estado e limites

O app V1.2.3 continua operacional. O gerador atual é heurístico; separação neural não equivale a geração de timbre calibrada. O R1 foi testado pelo usuário, que relatou distorções ruins. Sua validade de catálogo e transporte não significa aprovação sonora. Preservar R1, APK, catálogos, originais e gravações para comparação.

O prompt é uma referência arquitetural, não evidência das escalas físicas dos aparelhos. Não adotar seus exemplos de frequências, pesos de loss ou scores como especificações verificadas.

O fluxo operacional vigente é automático pelo app em `develop`: [Piloto V1.3.0](../PILOTO_AUTOMATICO_MK300_V1_3_0.md). Nenhuma etapa exige que o usuário configure knobs manualmente; testes no equipamento usam geração e envio pelo aplicativo.

## Etapa A — baseline e validação da captura (iniciada)

Entregas: inventário com hashes e métricas por canal, registro das condições de execução e comparação auditiva dos presets. O script `repertorio/laboratorio/scripts/avaliar_capturas_mk300.py` apenas decodifica e mede; não altera áudio, presets ou equipamento. Seu relatório não atribui fidelidade.

Primeiro relatório: `repertorio/laboratorio/relatorios/mk300_capturas_r1.json`. Duas capturas AAC estéreo, com sinal concentrado no canal esquerdo. Base: 16,21 s, pico esquerdo −28,47 dBFS, RMS integral −41,42 dBFS. Solo: 20,74 s, pico esquerdo −33,64 dBFS, RMS integral −48,33 dBFS. Canal direito: RMS próximo de −93 dBFS em ambas. RMS inclui pausas. Não se demonstrou clipping analógico nem a causa da distorção ruim. Canal direito silencioso pode ser consequência normal da rota mono; confirmar antes de tratar como defeito.

Pendências: firmware, preset efetivamente aplicado e slot, captador/volume/tone, nível de saída MK300 e ganho/entrada MQ44; confirmar que as duas tomadas foram feitas na Konig, como sugerem os nomes. Os campos desconhecidos permanecem nulos. O CSV anterior não é prova da guitarra usada na tomada de solo.

Aceite: usuário confirma rota e condições; trecho útil e stem são revisados; diferenças de volume não favorecem um candidato. Recuperar, se disponível, o preset anteriormente considerado fiel como baseline adicional. Sua ausência não impede uma busca manual controlada na MK300.

## Etapa B — schema e busca sonora controlada

Construir `DeviceDefinition` separado por aparelho, aproveitando o catálogo existente através de adaptador. Cada parâmetro precisa distinguir valor de transporte, valor exibido e unidade física; escala desconhecida resulta em `NEEDS_DEVICE_DATA`. Registrar origem e nível de verificação por parâmetro. Valores aceitos pelo protocolo não provam resposta sonora conhecida.

Validar na MK300 firmware, modelos, cortes de gabinete, Bright/Reso, ativação e herança de blocos. Em seguida, selecionar poucos candidatos documentados de amp/cab, com ganho conservador e ajustável por escuta. Alterar uma família de controles por rodada: amp/cab → ganho/drive → EQ → ambiência. Não usar extremo de escala como suposto neutro. Fazer backup e usar o fluxo de envio já existente, com confirmação do slot.

Aceite: ao menos um candidato aprovado pelo usuário por papel; registrar preset exato, firmware, guitarra e captura. Comparação com volume semelhante e ordem alternada, repetindo tomadas para distinguir execução de mudança no preset. Sem percentual de proximidade inventado.

## Etapa C — dataset e calibração antes do otimizador

Validar possibilidade de reamp por uma rota física apropriada; não pressupor suporte USB de retorno nem ligar saída de linha diretamente à entrada de instrumento sem avaliar níveis/impedância. Quando houver rota validada, usar a mesma DI para comparar candidatos. Sem reamp, manter busca assistida com repetição humana e incerteza explícita, sem chamar tomadas independentes de pares causais DI/wet.

Cada exemplo: DI quando disponível, wet original sem perdas, parâmetros completos, firmware, guitarra/captador, níveis/rota, hashes, trecho e parecer auditivo. Separar sessões/execuções entre treino e validação para evitar vazamento. Capturas M4A atuais servem à triagem e escuta; convertê-las não recupera informação perdida. Amostrar modelos e controles prioritários em vez de todas as combinações.

Aceite: capturas repetíveis, metadados completos e dados suficientes no domínio que se pretende prever. Não há número universal de amostras que garanta sucesso.

## Etapa D — descritores e modelo de resposta

Interfaces previstas, inicialmente no laboratório:

`SeparationProvider → ReferenceSegment → FeatureExtractor → ToneDescriptor`

`DeviceDefinition + UserGuitarProfile + PresetCandidate → ForwardToneModel → PredictedToneDescriptor`

`ReferenceDescriptor + PredictedToneDescriptor → ToneLoss → CandidateSearch`

`UserReview + PedalCapture → CalibrationDataset`

Preservar estéreo, dinâmica e áudio bruto. Separação intercambiável com versão/hash e revisão de vazamento. Não assumir que L/R correspondem a guitarras distintas. Descritores incluem bandas de potência em dB, dinâmica, ataque, textura e indícios de efeitos com incerteza. Não converter brilho isoladamente em ganho. LUFS/dinâmica da referência masterizada não identificam compressor do pedal.

O modelo de resposta prevê descritores a partir de DI/condições e parâmetros. Pode começar simples; comparar com baseline antes de escolher arquitetura. Não comparar diretamente formas de onda de notas/execuções diferentes. Métricas devem ser robustas ao conteúdo ou usar trechos alinhados quando apropriado.

Aceite: o modelo prevê mudanças reais em capturas reservadas, dentro de uma cobertura declarada, e melhora a ordenação auditiva dos candidatos.

## Etapa E — otimização e alternativas

Implementar busca discreta de modelos e contínua/discreta de parâmetros somente sobre schema válido e modelo de resposta avaliado, ou sobre medições reais controladas. Pesos da loss serão experimentais até validação auditiva. Entregar poucas alternativas com diferenças explicadas e incertezas. Score interno não é percentual de fidelidade. O problema inverso admite múltiplos presets perceptivamente semelhantes.

Aceite: candidatos superam o gerador heurístico e o baseline por escuta, em execuções reservadas, com repetibilidade. Se isso falhar, revisar dados/modelo antes de ampliar o repertório.

## Etapa F — integração gradual no app

Somente após aceite sonoro, integrar o motor como opção versionada. Manter compatibilidade de importação e biblioteca, comparação antes/depois, escolha explícita do preset e transporte já testado. Registrar versão de gerador, schema, referência e calibração no resultado. Não apresentar confiança alta por mera existência de separação ou parâmetro válido.

Validar guitarra HH separadamente da SSS; depois expandir para as outras músicas. MK20 exige schema e calibração próprios, além da validação de protocolo necessária para escrita. Não transferir valores entre pedais supondo equivalência sonora.

## Próximo passo operacional

Completar os metadados das duas capturas e obter o preset anterior satisfatório, se disponível. Conferir parâmetros no equipamento e conduzir a primeira rodada A/B. Não gerar R2 automaticamente a partir do relatório técnico: não há evidência suficiente para atribuir a falha a um controle específico.
