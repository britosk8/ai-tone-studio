# Infest — presets iniciais MK300 / Piloto R1

Estes são os primeiros presets para aplicar na MK300, tocar e gravar. Não é preciso gravar um preset anterior para começar. Os presets anteriores continuam úteis como comparação opcional.

## Arquivos

- **Infest_MK300_Piloto_R1.json**: par de presets no formato de importação do AI Tone Studio. Não é um arquivo nativo do editor M-EFCS.
- **GUIA_PARAMETROS.txt**: parâmetros completos para conferência/configuração manual.
- **modelo_completo.json**: modelo de dados completo do backend, para rastreabilidade; não selecionar esse arquivo na importação.
- **proveniencia.json**: duas análises, fontes/hashes e alterações explícitas sobre a saída bruta do gerador.

## Origem e limites

- Base: guitarra extraída da referência aprovada 00:50–01:10, para o primeiro teste com a Konig SSS.
- Solo/destaque: guitarra extraída da referência aprovada 02:40–03:00, para o primeiro teste com a Strinberg HH.
- Fonte inicial: rodada htdemucs_6s com contexto, preservada em `fase_2/infest_comparacao/`. A qualidade dessa extração ainda não foi aprovada por escuta. Foi escolhida como hipótese de trabalho para permitir o primeiro teste; não se afirma que seja melhor que a inicial.
- A separação usa IA. A conversão para parâmetros usa o gerador heurístico atual, com análises independentes e escolhas conservadoras documentadas. Não foi treinado um modelo de matching da MK300.
- Nenhum ajuste foi validado na guitarra/pedal reais e não há percentual de fidelidade. Não houve otimização para a resposta dos captadores SSS/HH.

## Cadeia inicial

Gate, amp e cabinet ligados. Drive adicional, compressor, delay, reverb e modulação desligados. Isso permite ouvir o caráter principal antes de empilhar efeitos com evidência insuficiente. A presença estimada de reverb/compressão no stem não basta para habilitá-los automaticamente nesta rodada.

Ambos usam amp **2J900_OD**, selecionado pela classificação overdrive do gerador, e cabinet **2JVM_1960_57**, escolhido pela preferência 4x12 do catálogo. Esses nomes não identificam o equipamento usado no disco; ainda não há comparação sonora de todos os amps/cabs da MK300.

| Controle | Infest Base R1 | Infest Solo R1 |
| --- | ---: | ---: |
| Gate / Bias | 15 / 50 | 15 / 50 |
| Amp Gain | 33 | 32 |
| Amp Level | 50 | 50 |
| Bass | 75 | 60 |
| Middle | 58 | 67 |
| Treble | 40 | 50 |
| Reso | 0 | 0 |
| Pres | 50 | 67 |
| Bright | 0 | 0 |
| Cabinet Level | 80 | 80 |
| Cabinet Low Cut / High Cut | 0 / 200 raw | 0 / 200 raw |

Valores são controles do catálogo, não dB/Hz. Gate, Reso/Bright e cortes do cabinet são hipóteses explícitas, não medições precisas. Level reduzido é um ponto inicial, não garante ausência de clipping; calibre a saída e a MQ44 antes de gravar. Não há sync/BPM confiável inferido da guitarra sozinha; efeitos de tempo ficam desligados.

## Carregar e enviar

1. Instale o APK **V1.2.3** sobre a versão atual, sem desinstalar antes.
2. Copie `Infest_MK300_Piloto_R1.json` para o celular.
3. Na tela inicial, toque no ícone de arquivo ao lado de Ajustes: **Importar presets MK300 (JSON)**.
4. Selecione somente o JSON de importação citado acima. Revise os dois nomes e confirme **Importar como nova análise**.
5. A nova análise abre na biblioteca. Importação cria novos IDs, inclusive se importar o mesmo arquivo duas vezes; não sobrescreve análises ou edições anteriores. Importar não escreve no pedal.
6. Selecione **Infest Base R1**, conecte à MK300 e use o fluxo atual de envio. Escolha um slot que você aceita substituir, confira seu conteúdo, salve o backup e confirme a escrita. Repita com **Infest Solo R1** em outro slot escolhido por você.
7. Não assumimos que qualquer slot esteja vazio. Os nomes já cabem no limite de 19 caracteres do pedal e podem ser alterados na tela de envio.

A importação funciona sem backend. O envio USB mantém as verificações anteriores. O backend não foi alterado nesta entrega e continua compatível na V1.2.2.

## Testar e gravar depois de aplicar

Use os presets importados/aplicados e toque as passagens aprovadas. Grave duas tomadas da base com a Konig e duas do solo/destaque com a Strinberg pela MK300 → MQ44 → Gravador de Áudio do Windows. Deixe alguns segundos antes/depois e mantenha captador/volume/tone e níveis constantes entre repetições.

Salve em `fase_1/01/gravacoes_pedal/`, identificando `piloto_r1` e a tomada, por exemplo `01_base_Konig_mk300_piloto_r1_t01.wav`. Se o gravador produzir M4A, preserve a extensão e o arquivo reais; não renomeie para WAV. Registre configurações no CSV da música. O roteiro `../../CAPTURA_WINDOWS.md` traz os passos do gravador; onde disser preset atual, use este Piloto R1 nesta rodada.

Os pares importados são locais: se usar a comparação dentro do app, selecione o áudio original e o início de referência correto (50 s para base; 160 s para solo/destaque). Sem selecionar arquivo, o backend não possui perfil salvo associado ao novo ID local. Também é possível comparar as capturas no laboratório.

Depois das gravações avaliaremos se falta distorção, se há graves excessivos, se o ataque está adequado e se precisamos trocar amp/cabinet. Esses pontos não podem ser concluídos apenas por observar os números do preset.

## Validação da entrega

75 testes backend e 42 Flutter passaram. A importação foi testada com backend indisponível, cancelamento, arquivo inválido, persistência sem sobrescrever edições e geração de imagem MK300 em memória, sem transporte real. Os parâmetros dos dois presets cobrem todos os knobs dos modelos selecionados e estão dentro do catálogo. Há validação de nomes, hashes dos stems e equivalência entre o JSON entregue e a fixture testada.

O painel global de análise do app recebe o perfil da referência de base neste par; as análises completas e independentes de base e solo estão em proveniencia.json. Esse painel não deve ser interpretado como uma análise única dos dois trechos. Nenhum teste automatizado comprova o som final na guitarra/pedaleira.
