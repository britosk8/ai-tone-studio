# Revisão de Infest e encerramento dos pilotos — V1.5.6

## O preset foi enviado corretamente

O relatório real `90b3ea2b1d5724c04c092bee43e0bea806022312743c8341c01d76cdb2ed04b3`, capturado em 29/10/2026 às 22:32:39 UTC, confirmou o envio de `Base Infest` ao slot 150 da MK20: preflight, escrita `0xD21`, ACK, commit, ACK e retorno exato dos 412 bytes. O usuário confirmou leitura e envio funcionais, mas reprovou o timbre. A transmissão está validada nesse teste; isso não valida a qualidade acústica do gerador.

Comparação com o preset `PAPA INFEST` lido anteriormente do slot 76:

| Item | Preset gerado e enviado | Referência aprovada lida do pedal |
|---|---|---|
| Gate | AI Gate, Gate 35/Bias 50 | AI Gate, Gate 40/Bias 50 |
| DS | 2TS8, desligado | 22TS-9, ligado, Gain 10/Level 80 |
| AMP | 23DS1_J900 | 70OD2_meas |
| Gain/Level do AMP | 65/40 | 56/60 |
| Bass/Middle/Treble do AMP | 56/35/35 | 58/49/60 |
| Reso/Pres/Bright do AMP | 25/30/30 | 35/58/45 |
| CAB | 1BogUber412A | 54MbSOSS4t412 |
| CAB Level/Low Cut/High Cut | 60/80 Hz/7500 Hz | 80/80 Hz/7500 Hz |
| EQ | desligado | Guitar EQ 6, ligado |
| Volume do preset | 40 | 60 |

Nomes e IDs do preset enviado pertencem ao catálogo MK20 0.4.0; parâmetros e conversões estão dentro dos limites. A ausência de DS e EQ é uma escolha do gerador heurístico, não perda de blocos na transmissão. Um amp diferente não é por si só prova de erro, mas esse resultado não reproduz a cadeia que já foi aprovada na mesma guitarra e pedal. Sem captura acústica desse novo preset, não se atribui percentual de semelhança nem se declara um ajuste sonoro validado.

## Problema encontrado na referência

O preset foi calculado pelo estado `1bcea36337ba-ch0-0`, usando **9–21 s** da guitarra separada. Na análise de 12 s, RMS ≈ -44,46 dBFS, pico ≈ -28,34 dBFS, proxy de distorção 0,165; bandas de 800–1600, 1600–3200 e 3200–6400 Hz aproximadamente -31,67, -36,60 e -42,34 dB em relação à energia total. O estado original era limpo e foi corrigido para distorcido na interface (`classification_overridden=true`). O motor impôs Gain 65 por essa classificação, mas os descritores recortados em zero levaram Middle/Treble a 35. Não havia evidência documental aplicada na seleção de AMP/CAB (`evidence=[]`).

Os demais estados da mesma guitarra têm referências bem mais fortes: distorcido L em **141–153 s**, distorcido R em **192–204 s**. Canal L/R não identifica automaticamente base/solo. O trecho 9–21 s é uma referência fraca para gerar esse som; vazamento de outro instrumento é uma possibilidade, não um fato comprovado. Separação por IA não garante guitarra útil em todo instante da música.

A V1.5.6 acrescenta avaliação independente da classificação sonora. Em cada mapa/canal, um estado com RMS abaixo de -40 dBFS **e** mais de 18 dB abaixo do estado mais forte é sinalizado como referência fraca. Estados úteis aparecem primeiro; os fracos continuam visíveis com motivo e geração desabilitada. O backend verifica a mesma condição antes de reutilizar uma variante antiga ou gerar outra. Trocar o rótulo para distorcido não remove esse impedimento.

A avaliação usa as medições já salvas: não exige novo upload nem nova separação. Um master uniformemente baixo não é rejeitado apenas por volume; canais diferentes não são comparados entre si. Dados antigos sem medição continuam explicitamente não avaliados. Essa regra é uma proteção para a geração por estados, não um classificador treinado de vazamento/instrumentos nem uma recalibração acústica do motor.

## Limpeza autorizada da interface e biblioteca

O usuário escolheu **simplificar e arquivar os presets de teste**. Ao abrir o APK 1.5.6 pela primeira vez:

- A biblioteca ativa existente é copiada integralmente para `SharedPreferences`: `test_library_archive_v156_snapshot` e `archived_preset_pairs`. O arquivo é conferido antes de remover os registros da lista ativa. O marcador `test_library_archive_v156_done` impede repetir a limpeza em novas gerações.
- A retomada após interrupção usa apenas o snapshot inicial. Presets novos e edições posteriores com o mesmo ID são preservados; o arquivamento não sobrescreve essas edições.
- **Ajustes → Presets arquivados** permite restaurar um par de base/solo individualmente, com controles, nomes, metadados e análise. Restaurar não substitui uma versão ativa mais recente.
- Não se apagam registros do backend, áudios, instrumentos separados, gravações nem arquivos de backup. A tela de escolha da música continua consultando a biblioteca de referências do backend; o upload original não precisa ser repetido. Referências auxiliares dos pares arquivados também podem sincronizar ao backend, priorizando uma versão ativa com o mesmo ID.

A tela inicial fica com importação funcional e Ajustes, sem os atalhos de piloto Infest e teste MK20. A tela de envio usa USB/OTG e não oferece o BLE ainda não validado neste ciclo. Diagnóstico MK20 e recuperação dos backups antigos permanecem em **Ajustes → Diagnóstico e recuperação**. O acesso de produção ao teste antigo de nome funciona apenas para recuperar backups, sem preparar novos testes nem renomear slots. O botão genérico duplicado de comparação foi removido; permanecem os comandos específicos de comparar a base ou o solo, com o papel correto.

O envio USB validado não teve seu codec, perfil, comandos ou política de backup alterados. O destino MK20 continua no slot 150. Bibliotecas atuais são arquivadas localmente no primeiro início, não por executar o backend ou por este trabalho no notebook. Instalar sobre a versão existente, sem limpar dados do app.

## Próximo teste de som

Abrir uma música já separada, atualizar/reabrir os estados e gerar a base MK20 a partir de um estado distorcido com referência audível. Enviar pelo fluxo USB existente e gravar a guitarra no app para comparar a mesma passagem. O preset aprovado de Infest continua sendo uma referência auxiliar de calibração; não será copiado como solução universal nem substituirá a geração a partir da música.

## Validação de software

150 testes do backend e a regressão Flutter de 97 casos passaram. Os cinco casos de arquivamento passaram novamente após o ajuste de layout, incluindo um caso adicional em tela 360×640 com aviso de biblioteca arquivada. Verificados arquivo integral, retomada após interrupção, preservação de novos presets/edições, restauração individual e ausência dos atalhos antigos. `flutter analyze` sem problemas. O relatório físico original também foi revalidado pelo servidor: `send_confirmed`, slot 150, duas escritas (banco e commit), SHA-256 do destino `9f341f125629fa9a7caf54bdfb3ebdbd33cef3e2f7dc2934b04a3db69b94a18e`. Os testes não atribuem fidelidade acústica à próxima geração.
