# Infest — primeira captura com o Gravador de Áudio do Windows

Você confirmou que já grava pela MQ44 usando o Gravador de Áudio padrão do Windows. Vamos aproveitar esse programa para registrar o som atual, sem alterar o aplicativo nem instalar outra DAW.

## Antes de gravar

- Preserve os presets atuais da MK300. Se já estiverem na biblioteca do AI Tone Studio, exporte os JSONs de base e solo para `presets/`, com nomes como `01_base_mk300_atual.json` e `01_solo_mk300_atual.json`.
- Se o preset estiver apenas no pedal, anote nome/slot e os controles; não trate um JSON diferente do app como se fosse a cópia do pedal. O backup do slot, se disponível no fluxo de envio, também deve ser preservado antes de substituições.
- Registre modelo de guitarra, captador selecionado, volume e tone, nome/slot do preset e os níveis da MQ44. O firmware pode ser anotado depois se ainda não souber.

## Escolher a entrada correta

1. Mantenha a ligação já usada: saída de áudio da MK300 → entrada da MQ44 → notebook.
2. No Windows, abra **Configurações → Sistema → Som → Entrada** e identifique a entrada correspondente à MQ44. O nome exibido pode ser genérico; não presuma que será “MQ44”.
3. No Gravador de Áudio, selecione essa entrada se a versão mostrar um seletor. Caso não mostre, use a entrada padrão escolhida no Windows.
4. Faça um teste de alguns segundos tocando a guitarra e depois parando. Confira que o arquivo contém a guitarra ligada à interface, não apenas o microfone do notebook.
5. Se a MQ44 também encaminha a reprodução do computador à gravação, pause a música antes da tomada ou ajuste o roteamento para não misturar o acompanhamento. Usar fones não impede um loopback interno da interface.

## Formato

Nas versões que oferecem configurações de gravação, procure **Configurações / formato / qualidade**. Se houver **WAV**, prefira-o; FLAC também é uma opção sem perdas se disponível. Use a maior qualidade apropriada oferecida pelo dispositivo/programa, sem forçar uma taxa diferente da sessão só para aumentar o número.

Se sua versão salvar apenas **M4A**, pode entregar o M4A original para o teste inicial de rota/nível. Não converta para WAV esperando recuperar qualidade. Registraremos que houve compressão e decidiremos uma captura sem perdas antes de usar esses dados para caracterização definitiva da pedaleira.

A aparência e os formatos disponíveis variam com a versão do Windows e do aplicativo; ainda não verificamos a sua tela. A documentação Microsoft orienta selecionar/testar a entrada em Som e, nas versões atuais do gravador, acessar Settings para formato/qualidade.

## Quatro tomadas iniciais

Grave a guitarra sozinha, com o preset aplicado. Comece a gravação, deixe cerca de 2 segundos de silêncio/ruído de fundo, toque a passagem por aproximadamente 20 segundos e deixe 2 segundos ao final. Não precisa cortar o arquivo: vamos marcar a região útil depois.

| Arquivo sugerido | Guitarra | O que tocar |
| --- | --- | --- |
| `01_base_Konig_SSS_mk300_atual_t01.wav` | Konig Stratocaster SSS | Parte da referência 00:50–01:10 |
| `01_base_Konig_SSS_mk300_atual_t02.wav` | Mesma guitarra/configuração | Repetir a passagem anterior |
| `01_solo_Strinberg_HH_mk300_atual_t01.wav` | Strinberg Les Paul HH | Parte da referência 02:40–03:00 |
| `01_solo_Strinberg_HH_mk300_atual_t02.wav` | Mesma guitarra/configuração | Repetir a passagem anterior |

A extensão deve ser a real do arquivo, como `.m4a` se for o formato utilizado. Não basta renomear a extensão para WAV. Nesta rodada, as duas partes serão capturadas na MK300, inclusive a base da Konig. A MK20 continua para uma etapa posterior.

Mantenha a afinação e a execução consistentes, mas não tente corrigir o som mudando o preset entre as duas tomadas. Não acrescente normalização, EQ, redução de ruído ou efeitos de voz no arquivo. Se houver “aprimoramentos” automáticos de áudio, anote a configuração e desative-os para este teste quando possível. Evite saturar o pedal, a interface e a entrada digital; diminuir somente o volume de reprodução não corrige clipping gravado.

## Onde salvar

Copie os arquivos para:

`/home/adrianobn/ai-tone-studio/repertorio/fase_1/01/gravacoes_pedal/`

Esse é o destino no projeto Ubuntu. No Windows, primeiro grave/salve normalmente e depois transfira para essa pasta. Não é um caminho para digitar diretamente no aplicativo de gravação do Windows.

Preencha `REGISTRO_CAPTURAS.csv` com o nome real e as configurações. Os campos ainda estão em branco porque nenhuma captura do pedal foi entregue nesta etapa.

## O que será validado ao receber

Formato e duração reais, sinal útil, nível, indícios de clipping, canal(es), silêncio inicial e se o acompanhamento contaminou a captura. Depois avaliaremos a consistência entre tomadas e a comparação auditiva com a guitarra extraída escolhida. Não será atribuída fidelidade sonora por um simples percentual de EQ.

O teste de reproduzir uma gravação limpa pela pedaleira (reamp) permanece separado. Conseguir gravar a saída não prova que a USB aceite esse retorno.

Fontes: [Microsoft — selecionar e testar entrada de áudio](https://support.microsoft.com/pt-br/windows/hardware/drivers/how-to-set-up-and-test-microphones-in-windows), [Microsoft — configurações de formato/qualidade do gravador](https://www.microsoft.com/en-us/surface/do-more-with-surface/how-to-record-a-podcast).
