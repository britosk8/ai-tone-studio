# Conectividade V1.1.0 — investigação e teste (12/10/2026)

## Resultado e limites

| Modelo/transporte | Implementação | Verificação física nesta entrega |
|---|---|---|
| MK300 USB/OTG | MIDI Android, SysEx, backup, escrita de slot e leitura de retorno | Não executada: nenhum dispositivo conectado por ADB |
| MK300 BLE | GATT AE40/AE41/AE42, conversão crua M-EFCS, respostas fragmentadas, MTU e fluxo de envio | Experimental; exige validação no equipamento |
| MK20 USB/BLE | Busca e conexão do transporte | Gravação bloqueada: perfil específico sem captura de comandos |
| Renomeação | Nome antes de enviar + salvar nome na biblioteca | Testes de software; nome do áudio independente |
| Nome do áudio | Nome original do upload preservado, título derivado sem a extensão se vazio | Teste integrado da API |

Esta entrega implementa os adaptadores; não declara a transferência direta fisicamente concluída. Testes simulados não substituem um pedal. Uma conexão GATT/USB aberta não comprova compatibilidade, e o firmware informado na tela não é detectado automaticamente.

## Fontes examinadas

1. [Downloads oficiais](https://www.m-vave.com/download): em 12/10/2026 lista MK300 V75 e MK20 V085. O app não baixa/aplica firmware e não executa reset.
2. [M-EFCS Android oficial](https://resource.m-vave.com/software/app/M-EFCS.apk): inspeção estática do ZIP e strings, sem executar o APK. Bibliotecas contêm AE40/AE41/AE42. A presença das strings confirma a implementação desses serviços no editor, mas não prova o funcionamento BLE em cada pedal.
3. [jpfaria/mvave](https://github.com/jpfaria/mvave), commit `7363c896202508c57218fa68fb941d943fa40cd1`: licença MIT; captura MK300 firmware V73, documentação USB, 359 modelos, nomes e posições dos knobs e alguns defaults. Não fornece perfil MK20 nem teste Android/BLE. Protocolo e vetores foram reaproveitados com licença em `third_party/mvave/` e dentro do APK.
4. [Protocolo capturado MK300](https://github.com/jpfaria/mvave/blob/main/docs/protocol.md): formato de 448 bytes, checksum, bank-write, commit e leitura. Cópia local em `docs/references/mk300-usb-protocol.md`.
5. [BLE BlackBox](https://github.com/jvsobrinho/mvave-blackbox-ble/blob/main/docs/ble_protocol.md): referência de túnel cru AE40. Seu preset de 92 bytes e seus endereços não foram aplicados à MK20/MK300. A conversão BLE implementada usa os frames MK300 conhecidos e valida as respostas, não os comandos de memória BlackBox.
6. Android: [MidiManager](https://developer.android.com/reference/android/media/midi/MidiManager), [MidiDevice](https://developer.android.com/reference/android/media/midi/MidiDevice), [permissões Bluetooth](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions).

## Evidência dos arquivos oficiais

Arquivos extraídos do ZIP M-EFCS apenas para análise local:

- MK300 `mk300_am4_preset.bin`: 71.688 bytes = 160 × 448 + `PATCHEND`. SHA256 `548441dd8e3e6912da01837a966841c1f40584d13168ecae25d00198e4cacb2b`.
- MK20 `mk20_am4_preset.bin`: 61.808 bytes = 150 × 412 + `PSET0002`. SHA256 `b13828a92e7046ca8433fac3a47a83aa89ff77113ca9c2d59cf52a0656384f02`.

Os bins oficiais não são redistribuídos no projeto. O tamanho MK20 comprova a diferença de layout, mas não autoriza escrever em seus endereços usando o perfil MK300. A captura leitura/escrita do editor para MK20 ainda é necessária.

## Correções necessárias antes de enviar

O codec anterior eliminava bits altos em vez de empacotar o fluxo, e calculava o checksum com os dígitos errados. Agora Python e Dart reproduzem os vetores capturados: empacotamento 8→7 bits, checksum sobre os bytes u32 especificados, ACK exato e validação de checksum nas respostas.

O catálogo anterior usava aliases e índices não equivalentes aos capturados. A MK300 0.4.0 inclui 120 AMPs, 40 DS, 100 CABs e os demais módulos, totalizando 359. O compilador escolhe Compress do FX pela identidade, não Wah-Wah como compressor; parâmetros seguem os knobs daquele modelo. Parâmetros não presentes, como Pre Delay no Room capturado, não são enviados.

Nomes/índices/knobs foram conferidos com a fonte; limites genéricos de controles e a classificação musical não equivalem a medição física em V75. Os slots de AMP/CAB/DS podem conter modelos importados que substituem os de fábrica. A confirmação de envio lembra dessa condição; o app não lê nem altera NAM/IR.

## Fluxo de transferência

1. Android abre USB MIDI ou GATT AE40 e assina respostas AE42. USB recebe SysEx; BLE recebe o pacote cru equivalente.
2. Para MK300, lê o edit buffer e um registro de flash; exige checksum válido, 448 bytes, constantes, cadeia única de 11 blocos e índices dentro do catálogo.
3. O usuário seleciona base/solo, escolhe slot 1–160 e informa o nome de hardware (ASCII, 1–19 caracteres, sem truncamento durante envio).
4. Lê o destino sem ativá-lo e constrói a imagem a partir dele. Preserva bytes não documentados, footswitches, pan e volume do destino; altera nome, cadeia, estados, modelos e parâmetros conhecidos. Defaults capturados são usados quando um modelo muda; campos sem defaults exigem parâmetros explícitos, salvo AMP/DS/CAB que conservam knobs por modelo na referência.
5. Salva e relê um backup JSON com a imagem original integral em base64, slot e conexão. Caminho: diretório privado do app `pedal_backups/`. O botão Compartilhar permite exportá-lo.
6. Exige confirmação explícita de sobrescrita. Relê o slot e aborta se mudou desde o backup.
7. Envia bank-write (slot zero-based × 448), espera ACK, envia commit, espera ACK e aguarda o processamento de flash. Nunca repete automaticamente uma escrita.
8. Relê até comparar todos os 448 bytes. Divergência/timeout não é mostrada como sucesso. O slot é gravado, mas não é ativado automaticamente; selecione-o no pedal.

Não são emitidos comandos de firmware, reset, uploads NAM/IR nem gravação de globais. Nome/chain/params são limitados ao preset conhecido. Se a conexão cair, o resultado pode ser incerto: preserve o backup, confira por leitura e não trate o timeout como prova de que nada mudou.

BLE exige MTU ≥ 466 para enviar de uma vez o pacote cru de 463 bytes. Não foi inventado um esquema de fragmentação proprietária. MTU menor impede o envio e orienta USB. Reconstituição de notificações fragmentadas é testada, mas o comportamento do serviço BLE MK300 precisa de teste físico. O UUID MIDI padrão anteriormente registrado não é usado para o túnel proprietário.

## Testar no telefone

1. Instale a V1.1.0 sobre a versão atual; mantenha os dados do app.
2. Mantenha o backend atualizado, versão 1.1.0. Reanalise a música para obter catálogo MK300 0.4.0. Os presets antigos permanecem na biblioteca, mas ficam bloqueados para transferência.
3. Confira que o campo Música vem preenchido com o nome do arquivo e que esse título permanece após salvar/reabrir.
4. Conecte a MK300 por cabo de dados USB/OTG e feche M-EFCS/outros editores. Primeiro teste USB, para o qual existe captura direta da referência.
5. Abra Enviar para pedaleira, selecione o preset MK300 (solo ou base, conforme a seleção original), busque USB e confirme o modelo conectado. Se usar V75, selecione V75 como versão informada; o teste deve registrar essa versão.
6. Toque Conectar e conferir leitura. Se falhar, não grave; registre a mensagem e o nome USB apresentado.
7. Escolha um slot de teste, renomeie e toque Ler destino e salvar backup. Exporte o backup antes de confirmar.
8. Confirme o envio. Aguarde a comparação por leitura. Registre nome anterior, nome novo, slot, firmware, transporte e resultado. Selecione o slot no pedal para ouvir.
9. A captura V73 relata visor com nome em cache até reiniciar o equipamento; uma mensagem de sucesso no app exige leitura do nome novo, não alteração imediata do visor. Não há reinício automático.
10. Após USB funcionar, teste BLE com Bluetooth do pedal ligado e permissões do Android concedidas. Registre nome BLE, MTU, leitura e resultado. Se o MTU for insuficiente ou o serviço não responder, use USB e envie a mensagem para análise.

Para MK20, teste descoberta/conexão e renomeação local, mantendo envio manual. Para liberar gravação, precisamos de captura específica do M-EFCS na MK20 V085 e teste com seu hardware. O próximo passo pode usar a conexão do pedal ao computador/telefone para coletar essa evidência; isso não foi executado nesta entrega.

## Validação automatizada e artefato

- Backend: 60 testes passaram; inclui nome original do upload, análise MP3, persistência e vetores capturados SysEx.
- Flutter: 18 testes passaram; inclui USB/BLE fragmentados, checksum, bloqueio de catálogo antigo/MK20, confirmação, backup corrompido/slot alterado, comparação de retorno e presets gerados pelo compilador.
- Flutter analyze: sem apontamentos.
- Build release Kotlin/Flutter: concluído, versão 1.1.0 / código 3; assinatura verificada e mantida em relação à V1 anterior.
- APK: `releases/ai-tone-studio-v1.1.0.apk`, com SHA256 no arquivo ao lado.
- Testes de hardware MK300 V73/V75 e MK20 V085: não executados; aguardam o roteiro do usuário. BLE não é apresentado como comprovado no pedal.

Para registrar o teste físico: anote telefone/Android, firmware real, modelo, transporte, nome encontrado, MTU (BLE), slot, backup exportado, resultado da leitura inicial e leitura após envio. Não substitua esses resultados por testes simulados.
