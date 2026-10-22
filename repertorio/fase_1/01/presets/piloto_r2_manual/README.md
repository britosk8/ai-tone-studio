# Infest R2 — comparação manual na MK300

Rodada de base com Konig SSS, passagem 00:50–01:10. Primeiro encontrar um timbre aprovado para esta combinação; depois avaliar solo/destaque e guitarra HH. Não confundir estes candidatos com presets já aprovados. Não é necessário instalar outro APK.

## Candidatos

| Nome para salvar | AMP | CAB | Comparação |
|---|---|---|---|
| Infest R2 A | 98MES_CH2_AMP | 11MESA_412_57 | Primeiro candidato |
| Infest R2 B | 100MES_CH3_AM | 11MESA_412_57 | Mesmo CAB, troca apenas AMP em relação a A |
| Infest R2 C | 98MES_CH2_AMP | 12MESA_412_EC | Mesmo AMP, troca apenas CAB em relação a A |

Todos os nomes e IDs constam no catálogo MK300 0.4.0. Seleção por rótulos como hipótese para escuta, sem prova de que correspondam ao Triple Rectifier ou ao gabinete do MK20. Não interpretar sufixos AMP/AM como garantia de ausência de gabinete embutido. Não usar o tipo `crunch` do catálogo como classificação acústica validada desses modelos.

## Controles comuns — valores exibidos, configuração manual

Aplicar pelo pedal ou M-EFCS, conferindo cada bloco. Estes números preservam o ponto inicial aprovado no MK20, mas não garantem resposta idêntica na MK300.

| Bloco | Controles |
|---|---|
| AI Gate | Gate 40; Bias 50 |
| DS: 22TS-9 ligado | Gain 10; Level 80; Bass 42; Middle 58; Treble 52; Reso 0; Pres 50; Bright 60 |
| AMP do candidato ligado | Gain 56; Level 60; Bass 58; Middle 50; Treble 60; Reso 35; Pres 58; Bright 45 |
| CAB do candidato ligado | Level 80; Low Cut **80 Hz**; High Cut **7,5 kHz**, somente se disponíveis nessa escala exibida |
| Guitar EQ 6 ligado | 100 Hz +2 dB; 200 Hz 0 dB; 400 Hz −1,5 dB; 800 Hz +2 dB; 1,6 kHz +2,5 dB; 3,2 kHz +0,5 dB |
| VOL | 60, se o controle corresponder ao exibido; registrar o valor efetivo |
| Outros blocos | WAH, FX/compressor, MOD, DLY e REV desligados |

Cadeia de teste: AI Gate → DS → AMP → CAB → EQ → VOL. Manter ajustes globais iguais entre candidatos e registrar EQ global/roteamento de saída. Não alterar EQ global para favorecer um candidato.

Se o equipamento não permitir uma frequência ou fração indicada, anotar exatamente as opções exibidas. Não digitar 7500 nem 80 como valores raw no JSON. Antes de comparar, uniformizar os controles disponíveis nos três candidatos e registrar a alteração. Não arredondar silenciosamente.

## Por que ainda não há JSON importável

O catálogo usa Low Cut raw 0–100 e High Cut raw 0–200; não há tabela validada que traduza esses valores para 80 Hz/7,5 kHz. O envio em `backend/app/transport/preset_builder.py` também usa `int(param.raw_value)`, truncando as frações do EQ se tratadas diretamente como valores raw. Não foi alterado neste trabalho: é preciso capturar a representação real do equipamento antes de corrigir schema/transporte e testar uma conversão.

`candidatos.json` é um manifesto de experiência; não selecionar na importação do app. Ele não produz uma imagem de hardware e não escreve no pedal. A ausência de JSON é uma pendência específica de fidelidade dos controles, não falta da lista de modelos.

## Roteiro de teste

1. Preservar os presets existentes; salvar candidatos somente em slots escolhidos pelo usuário, com backup prévio. Não presumir slots vazios.
2. Configurar A, conferir os valores exibidos e registrar captador/volume/tone da Konig, firmware, saída e ganho MQ44.
3. Ajustar a captura antes da rodada. Os M4A R1 têm picos baixos (−28/−34 dBFS) e sinal útil à esquerda. Confirmar entrada/rota física; não tratar o canal direito silencioso como falha sem conferir a ligação mono. Aumentar somente o nível necessário, sem saturar etapas anteriores. Manter ganho da MQ44 fixo na comparação.
4. Tocar a passagem base duas vezes em cada candidato, com a mesma configuração da guitarra. Deixar alguns segundos antes/depois. Comparar A/B e A/C com volume de escuta semelhante. Registrar diferenças de volume; não escolher automaticamente o mais alto como melhor. Se ajustar volume entre candidatos, usar um controle após a distorção e documentar.
5. Salvar em `repertorio/fase_1/01/gravacoes_pedal/`, nomes `01_base_Konig_mk300_r2_A_t01.wav` e assim por diante. Preferir formato sem perdas quando disponível. Se o gravador só oferecer M4A, conservar o arquivo original, sem renomear a extensão.
6. Preencher `AVALIACAO.csv`: ganho, ataque, graves, agudos, ruído e preferência geral. Registrar separadamente artefatos da referência extraída. Não atribuir percentual de fidelidade.

Aceite: um candidato considerado musicalmente melhor pelo usuário e resultado consistente entre tomadas. Se nenhum melhorar, interromper expansão de modelos e investigar rota, valores exibidos, gabinete embutido e referência. Não produzir dezenas de variações aleatórias.

Após escolha: variar ganho/drive apenas no vencedor, depois EQ e gate; ambiência por último. Gate 40 pode cortar finais de notas: registrar antes de ajustar. O envio automatizado desta rodada depende da validação das escalas pendentes.
