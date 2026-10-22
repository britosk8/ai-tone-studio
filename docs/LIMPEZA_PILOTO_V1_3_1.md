# Limpeza e geração sem duplicatas — Android 1.3.1+10

Atualização em `develop`, solicitada após várias rodadas deixarem a biblioteca cheia. A `main` permanece no baseline.

## Limpeza solicitada

Ao abrir o app atualizado, a migração remove uma única vez os pares cuja base possui `generation_metadata.generator = mk300-infest-reference-candidates-v1`. Inclui os candidatos A/B/C e rodadas geradas a partir de candidatos da versão anterior. Não usa o nome do preset como critério: análises originais, R1 importado e outras músicas são preservados.

Antes de excluir, copia a lista completa serializada de `preset_pairs` para a chave local `mk300_pilot_before_cleanup_v1` em SharedPreferences. A marca `mk300_pilot_cleanup_v1_done` impede nova limpeza automática quando o app reabrir. Se salvar o backup falhar, a remoção não começa. Esses backups são internos, sem tela de restauração nesta versão. Não há limpeza remota do celular antes de instalar/abrir esta atualização.

## Geração idempotente

O piloto consulta a biblioteca persistida ao abrir a tela e ao gerar. Identifica cada candidato pela versão do gerador, ID da análise de origem e letra A/B/C. Reutiliza os IDs e edições existentes; não salva outra cópia da mesma combinação. Solicitações concorrentes de geração/limpeza são serializadas no store.

Com A/B/C completos, o botão fica desabilitado com texto **Candidatos já existentes**. Se um candidato tiver sido excluído, **Gerar somente candidatos faltantes** preenche a lacuna, mantendo os demais. Os candidatos gerados não aparecem como novas origens e o serviço também rejeita sua utilização como origem.

O botão **Limpar candidatos e recomeçar** remove todas as rodadas do piloto, preserva as origens e permite gerar novamente. Faz um snapshot prévio na chave `mk300_pilot_before_latest_cleanup`; a biblioteca volta ao estado anterior em memória se a persistência da remoção falhar. Não altera os slots da pedaleira nem seus backups de envio. As edições de candidatos são mantidas ao reutilizar, mas removidas quando a limpeza do piloto é solicitada.

## Testar

Instalar o APK sobre a V1.3.0 sem desinstalar. Abrir a biblioteca: as rodadas antigas do piloto devem desaparecer, mantendo as origens. Abrir o laboratório e gerar uma rodada. Sair/voltar ou reiniciar o app: devem continuar os mesmos três candidatos, com geração bloqueada. Para um novo teste do zero, usar o botão de limpeza e gerar novamente.

Testes automatizados cobrem migração única com backup, preservação da origem, repetição/concorrência, preservação de edição, exclusão parcial, reabertura da tela e limpeza pelo botão. A geração sonora e os parâmetros da rodada não mudaram nesta atualização.

Validação executada: 51 testes Flutter passaram, `flutter analyze` sem problemas e build release concluído. APK local `releases/ai-tone-studio-v1.3.1-develop.apk`; hash no arquivo adjacente. Pacote `com.aitone.studio`, versão 1.3.1/build 10; assinatura compatível com as versões anteriores. Não houve acesso ao armazenamento do celular nem mudança na pedaleira nesta sessão: a migração será executada ao abrir a atualização no aparelho.
