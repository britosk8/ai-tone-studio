# Etapa 2 MK20 — teste de nome, Android/API 1.5.3

A leitura USB foi confirmada nas coletas reais recebidas em 29/10/2026, incluindo a coleta da V1.5.2: buffer ativo e slot 150, 412 bytes com checksum válido. O próximo teste é a escrita do nome do slot 150 e sua restauração. Esta versão **ainda não envia os presets gerados da música à MK20**.

## Testar pelo aplicativo

1. Instale o APK `releases/ai-tone-studio-v1.5.3-develop.apk` sobre a versão atual. Conecte a MK20 por USB/OTG, feche o M-EFCS e mantenha o backend acessível.
2. Tela inicial → ícone USB → **Etapa 2: testar gravação do nome**.
3. Toque **Buscar MK20 por USB/OTG**, escolha o dispositivo e confirme que é a MK20.
4. Toque **Ler slot 150 e preparar backup**. O app confere o buffer e o slot, salva a imagem integral de 412 bytes e relê o arquivo. Nenhuma escrita ocorre nesta etapa. **Compartilhar backup original** permite guardar uma cópia externa.
5. Toque **Revisar e testar gravação do nome**. A confirmação mostra o nome lido e o novo nome **AI TONE MK20 TEST**. Confirmar permite somente essa alteração no slot 150.
6. Aguarde a leitura de retorno. Sucesso exige os 412 bytes iguais à imagem esperada, incluindo todos os bytes preservados. O resultado é arquivado no celular e enviado ao backend automaticamente. Falha de rede permite **Enviar resultado ao backend** posteriormente.
7. Após o sucesso, toque **Restaurar original do slot 150** e confirme. O app relê o slot e só restaura se corresponder ao teste ou se já for igual ao original. Aguarde a confirmação por leitura. Avise quando o teste e a restauração terminarem para conferirmos os relatórios.

O teste é restrito ao slot 150, sem escolher outro slot. Não altera AMP, CAB, ganho, EQ, estados, cadeia, volume, BPM, footswitches ou bytes desconhecidos. Não ativa o slot nem reinicia o pedal. A atualização do nome no visor pode depender da seleção do preset; o resultado do app usa a leitura do slot, não o texto em cache do visor. Nenhuma ativação automática foi implementada.

## Falhas e recuperação

Cada operação de escrita pode ser tentada uma vez por backup. A tentativa é persistida antes de enviar o primeiro comando, sobrevivendo ao fechamento do app. Uma falha de ACK não causa repetição de escrita; apenas consultas de leitura podem se repetir. ACKs sozinhos não significam sucesso.

Se o slot mudou desde a leitura do backup, o app cancela a operação. Se a leitura após gravação não coincidir, mostra resultado não confirmado e preserva os dados. Não prepare outro teste para contornar esse estado: use a conferência por leitura e o relatório para avaliar o que aconteceu.

O backup é recuperado ao reabrir o app. Se a restauração já foi tentada e ficou incerta, **Conferir restauração por leitura** não repete a escrita. Uma leitura igual ao original marca a restauração como verificada. Novo teste só é preparado após confirmar a recuperação do original. Não há reset, atualização de firmware, escrita em globais, NAM/IR ou restauração forçada de conteúdo diferente.

## Evidência do editor oficial

Foi feita análise estática do [M-EFCS distribuído pelo fabricante](https://resource.m-vave.com/software/app/M-EFCS.apk), sem executar o editor, usando [Blutter](https://github.com/worawit/blutter) em ambiente isolado em `/tmp`. Não foram adicionadas dependências de engenharia reversa ao aplicativo ou backend. O artefato contém Dart 3.11.4; hashes, versão da ferramenta e endereços das rotinas revisadas estão em [mk20-editor-evidence.json](device-protocols/mk20-editor-evidence.json). Binários e dumps completos não são redistribuídos.

A tela MK20 chama `ProductDataBase.savePresetToDevice`. Essa rotina calcula base + índice × tamanho da estrutura e usa `NativeStructBase.sendToDevice`/`DeviceConnection.writeData`, tipo 4. A estrutura MK20 tem 412 bytes. O pacote cru tem prefixo `00 59 22`, tamanho do payload + 8, tipo 4, endereço, tamanho de dados, payload e checksum. Após empacotamento MIDI, a escrita de 412 bytes resulta em classe `09`, comando `0xD21`, espaço 0 e offset 61388 para o slot 150. Usar a divisão inteira de 412/16 do helper MK300 perderia bits: não foi reaproveitado o bank-write MK300.

O editor em seguida chama `save` com endereço `0xF0000000` e payload vazio, equivalente ao commit do espaço 15. O app aguarda ACK para cada um, espera três segundos sem consultas e confere por leitura. A análise estática fundamenta o piloto, mas **a escrita MK20 ainda não foi comprovada fisicamente nesta entrega**. A confirmação virá do teste no pedal do usuário.

Também foi conferida no editor a ordem dos dez tipos: FX, NS, DS, AMP, CAB, EQ, MOD, DLY, REV e VOL. Isso não valida todos os índices de modelos e escalas do catálogo parcial atual. A etapa seguinte, após o teste físico de escrita, será concluir esse mapeamento e habilitar o envio dos presets gerados, com seus próprios limites e validação. A geração por música e o envio MK300 continuam preservados.

## Dados e endpoints

O diretório privado `mk20_name_pilot/` contém backup original, imagem com o nome do teste, marcadores de tentativa, relatórios de cada operação e ponteiros para o último backup/resultado. O original não é sobrescrito; os marcadores e o resultado da verificação são metadados. Fazer backup dos dados do celular e do backend; Git não recupera slots de hardware.

- `POST /api/v1/mk20/name-pilots` com `report`: valida backup, alteração somente do nome, slot 150, sequência de leitura/escrita, ACKs e imagem de retorno. Não executa comandos de hardware.
- `GET /api/v1/mk20/name-pilots`: resumos.
- `GET /api/v1/mk20/name-pilots/{id}`: relatório completo preservado.

Registros no SQLite: `mk20_name_pilot`, separados dos diagnósticos somente de leitura. O backend deriva `rename_confirmed`, `restore_confirmed`, `already_original`, `unconfirmed` ou `not_attempted` a partir do trace; não confia somente no status declarado pelo cliente. Relatórios idênticos são idempotentes. Capturas e backups do usuário permanecem fora do Git.

## Validação e rollback

Testes de software cobrem confirmação, backup, preservação dos bytes, nome e restauração, mudança externa do slot, adulteração do arquivo, ACK perdido, leitura divergente, tentativa única e recuperação após reconectar. Um ACK de restauração perdido pode ser conferido sem nova escrita. Testes do backend rejeitam mudanças de controles, slots diferentes, comandos incorretos, ausência de leitura prévia, commit fora de ordem e repetição de gravação. A interface é testada em largura de celular.

Os testes usam imagens sintetizadas e pedais simulados; não criam relatórios fictícios no banco de uso do app. Nenhum comando foi enviado de ferramentas de desenvolvimento para o pedal. Hardware USB, ACK e persistência após commit MK20 dependem da execução do usuário.

Ponto anterior: `16b8e74` em `develop` (Android/API 1.5.2). `main` preservada em `56fbfbf`. Android **1.5.3+20**, API **1.5.3**; APK e SHA256 em `releases/`. Reverter código não restaura o slot; use o backup original do aplicativo e confirme por leitura.

Validação final: **130 testes backend e 83 Flutter aprovados**; `flutter analyze` sem problemas. O relatório produzido pelo serviço Android durante o teste de interface foi também validado diretamente pelo backend (`rename_confirmed`), sem inserir dados sintéticos no banco real. APK release gerado com a mesma assinatura e applicationId anteriores.
