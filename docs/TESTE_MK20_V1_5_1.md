# Primeiro teste MK20 pelo app — Android/API 1.5.1

## O que esta versão permite

Há uma tela própria **Testar MK20 por USB**, acessível pelo ícone USB na tela inicial, sem precisar gerar um preset. O mesmo atalho aparece no envio quando o preset selecionado é MK20.

O teste consulta o preset ativo e um slot de flash escolhido, preserva as imagens completas, os pedidos e as respostas, e salva o diagnóstico no celular e no backend. Não seleciona outro preset nem envia escrita, commit, reset, firmware, NAM ou IR. O envio de presets gerados para MK20 **continua indisponível**: esta é a coleta inicial de evidência física, não a conclusão do suporte de transferência.

A MK300 conserva o fluxo de leitura, backup, envio e comparação já utilizado. Os presets, gravações e análises existentes não são apagados ou convertidos.

## Testar na MK20

1. Instale o APK `releases/ai-tone-studio-v1.5.1-develop.apk` sobre a versão anterior. Mantenha o backend disponível na URL já configurada.
2. Ligue a MK20, conecte por cabo USB de dados e adaptador OTG ao celular, e feche o M-EFCS.
3. Na tela inicial, toque no ícone USB (**Testar MK20 por USB**).
4. Toque **Buscar MK20 por USB/OTG** e escolha a porta encontrada. O nome da porta não confirma automaticamente o modelo; confira que conectou a MK20.
5. Informe o firmware, se souber. **Não sei** é uma opção válida; não é preciso atualizar firmware para executar esta leitura. V085 é uma versão listada pelo fabricante, não detectada pelo app.
6. Mantenha o slot 150, ou escolha outro entre 1 e 150. O conteúdo será somente lido. Marque a confirmação do equipamento e toque **Ler MK20 e salvar diagnóstico**.
7. Aguarde as duas tentativas. O resultado mostra os nomes lidos ou o erro de cada leitura. Uma leitura parcial/timeout não aparece como sucesso completo.
8. Se aparecer **Diagnóstico salvo no backend**, avise que terminou: o relatório poderá ser consultado diretamente, sem exportar arquivos pelo Windows. Se o servidor estiver indisponível, o relatório permanece no celular; use **Enviar diagnóstico ao backend** quando a conexão voltar. **Compartilhar cópia do diagnóstico** é uma alternativa, não um requisito do fluxo.

Esta entrega prioriza USB/OTG. O teste específico MK20 ainda não oferece BLE, envio de presets ou importação dos modelos para o catálogo. A escolha de MK20 para geração continua usando seu catálogo parcial, separado do catálogo MK300.

## Evidência disponível e o que falta

O [fabricante lista a MK20, seus downloads e firmware](https://www.m-vave.com/download); a [página do produto](https://www.sincoaudio.com/product?id=mk-20) descreve 150 presets e conectividade. A referência pública [jpfaria/mvave](https://github.com/jpfaria/mvave) continua oferecendo somente o perfil MK300 no diretório de dispositivos consultado em 29/10/2026. O formato comum dos frames M-EFCS está documentado, mas não fornece por si só o perfil de gravação da MK20.

O artefato oficial M-EFCS já examinado, [APK do fabricante](https://resource.m-vave.com/software/app/M-EFCS.apk), contém `assets/flutter_assets/lib/resources/bin/mk20/mk20_am4_preset.bin`:

- SHA256 `b13828a92e7046ca8433fac3a47a83aa89ff77113ca9c2d59cf52a0656384f02`.
- 61.808 bytes = 150 registros de 412 bytes + `PSET0002`.
- Todos os 150 registros têm a constante `FF 90 1E 00` no offset 20, uma permutação de 0–9 nos bytes 30–39 e estados binários nos bytes 40–49.
- Nome nos primeiros 20 bytes; valores brutos em 24/26 e índices brutos em 50–59 são preservados. O relatório não inventa correspondências de blocos, modelos ou knobs com a MK300.

Esse arquivo não é redistribuído. A verificação estrutural foi feita nos registros do artefato oficial local; os testes versionados usam dados sintetizados, identificados como tais.

As consultas de teste usam frames de leitura do protocolo comum: classe `0D`, comando `41`, comprimento 412, espaço 1/offset 0 para buffer e espaço 0/offset `(slot−1)×412` para flash. A correspondência desses espaços na MK20 ainda depende do teste físico. O codec existente é reutilizado apenas para codificar/decodificar o envelope M-EFCS; não há chamada à escrita MK300. Respostas de dump `41` e leitura em bloco `01 02` são aceitas quando checksum, espaço, offset, comprimento e estrutura correspondem.

Uma resposta compatível confirma a leitura e fornece dados para o próximo passo. Não prova os comandos de gravação, ordem semântica dos blocos, índices e escalas do catálogo. Esses pontos precisam ser conferidos antes de implementar a escrita MK20 com backup e leitura de retorno. Não se habilita gravação apenas trocando 448 por 412 no código da MK300.

## Persistência e consulta

O celular salva arquivos completos no diretório privado `mk20_diagnostics/`, com cópia `latest.json` recuperada ao reabrir. Isso inclui as imagens integrais lidas de 412 bytes, caso válidas. Uma falha também gera relatório com erros e bytes recebidos; sucesso de sincronização não significa sucesso da leitura.

A coleta limita a 96 eventos e 32 KiB de dados binários; preserva notificações USB brutas e frames reconstituídos, inclusive respostas não reconhecidas. Não há repetição automática dos comandos. Uma falha na tentativa do buffer não impede a tentativa do slot.

- `POST /api/v1/mk20/diagnostics` com `{"report": ...}`: valida formato, limites, data, slot, pedidos somente de leitura, checksum e correspondência entre imagem e resposta. Salva o registro `mk20_diagnostic` no SQLite; repetir o mesmo relatório reutiliza seu hash.
- `GET /api/v1/mk20/diagnostics`: lista resumos.
- `GET /api/v1/mk20/diagnostics/{id}`: relatório completo.

Os estados são `read_layout_confirmed` (duas respostas estruturalmente compatíveis) e `read_incomplete` (leitura parcial ou falha). `write_enabled` permanece falso em ambos. Arquivos/base64 e SQLite não entram no Git. Incluir o diretório de dados do backend no backup; o backup do aplicativo continua independente.

## Validação e recuperação

Testes cobrem slots 1/150, rejeição de 151–160 e imagens de 448 bytes, duas leituras sem escrita, timeout, checksum inválido, desconexão, resposta em bloco, trace, imagens incompatíveis, persistência idempotente, falha de rede e reenvio do arquivo local. Os testes de regressão continuam incluindo a transferência MK300.

Nenhuma MK20 foi conectada ao ambiente de desenvolvimento, e nenhum comando foi enviado a um pedal nesta entrega. O primeiro teste físico será feito pelo usuário. Não foram inseridos diagnósticos sintéticos no banco usado pelo aplicativo.

Versão Android **1.5.1+18** e API **1.5.1**. Ponto anterior em `develop`: `8b9fb5d` (V1.5.0). `main` permanece em `56fbfbf`. APK e hash na pasta `releases/`; assinatura e applicationId preservados para atualização sobre o app existente.

Resultado automatizado: **117 testes backend e 75 testes Flutter aprovados**, com análise estática sem problemas. O teste de interface usa largura de celular e exercita também a sincronização após falha de rede.

## Resposta física recebida e correção V1.5.2 — 29/10/2026

A coleta USB/OTG do usuário recebeu duas respostas completas: edit buffer (espaço 1/offset 0) e slot 150 (espaço 0/offset 61388), ambas de 412 bytes, com checksum válido, nome `USER PRESET 150` e imagens idênticas. Os dez estados de bloco estavam desligados. O teste foi somente de leitura; não houve envio de preset ou alteração do pedal. O firmware foi informado como desconhecido e continua sem identificação automática.

O app 1.5.1 marcou timeout porque aceitava comandos de resposta `41` e `01 02`, enquanto a MK20 retornou `21 1A 00 00` (inteiro base-128 `0xD21`, equivalente a `0x41 + 8 × 412`). Os bytes já estavam preservados pelo diagnóstico. A versão 1.5.2 aceita também essa resposta, mantendo as conferências de classe, offset, espaço, tamanho, checksum e estrutura. O comando de consulta não mudou e nenhum código de escrita foi habilitado.

O backend reinterpreta os relatórios salvos com o leitor atualizado, sem alterar a captura original. A consulta completa distingue `capture_status` histórico de `summary.status` atual e identifica `decoder_version=mk20-read-v2`. Essa coleta passou de `read_incomplete` histórico a `read_layout_confirmed` na interpretação atual. Reenviar um relatório existente preserva o registro original; a resposta da API informa a validação atual. O app mostra a confirmação do backend ao sincronizar, inclusive quando recupera uma captura anterior.

A captura física completa fica somente no armazenamento local do projeto, fora do Git. Os testes versionados reproduzem o código de resposta observado usando imagens sintetizadas, não divulgam o conteúdo do preset do usuário. Também rejeitam códigos desconhecidos e verificam reinterpretação de um timeout antigo sem modificar os dados originais.

Android **1.5.2+19**, API **1.5.2**; APK `releases/ai-tone-studio-v1.5.2-develop.apk`. Ponto anterior: `74373a0` em `develop`. A leitura física foi confirmada nesta coleta; mapeamento de modelos e escrita MK20 continuam pendentes.

Validação da V1.5.2: 120 testes backend e 76 Flutter aprovados; análise estática sem problemas. Após o ajuste da mensagem de sincronização e da preservação do registro original, os 14 testes específicos backend e os 7 testes específicos Flutter da MK20 também passaram. Duas coletas reais recebidas foram reinterpretadas com ambas as leituras confirmadas; a análise dessas capturas foi somente de dados já salvos.
