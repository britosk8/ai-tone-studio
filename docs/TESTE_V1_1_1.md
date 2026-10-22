# Biblioteca e envio — V1.1.1 (12/10/2026)

## Motivo do botão desabilitado nas capturas

A MK300 respondeu à leitura e à verificação do layout, mas o preset selecionado tinha catálogo antigo/sem metadados 0.4.0. Uma conexão verificada não torna os índices daquele preset compatíveis. A nova versão mantém essa proteção e oferece a ação para resolver o bloqueio.

A captura do usuário é evidência de leitura USB funcionando, com V75 informada na interface. Não é evidência de escrita validada ou identificação automática do firmware.

## Atualizar e testar

1. Instale `releases/ai-tone-studio-v1.1.1.apk` sobre a versão atual. O backend precisa estar na V1.1.0 ou superior para gerar catálogo MK300 0.4.0 e metadados completos.
2. Abra o menu de três pontos de uma música na biblioteca e escolha **Escolher preset e enviar**. Na transferência, o campo **Música / análise salva** permite selecionar qualquer análise salva. As opções Base/Solo mostram o nome e a pedaleira de cada preset.
3. Se o preset estiver antigo, toque em **Gerar preset atualizado**. Escolha novamente o áudio original e faça a análise. Não há atualização automática de IDs de presets antigos nem liberação artificial do envio.
4. No resultado da nova análise, abra Enviar para pedaleira, escolha o preset MK300, busque/conecte por USB/OTG e confirme a leitura. A biblioteca da transferência também oferece a nova análise entre as opções.
5. Com preset atual, conexão conferida, nome ASCII de 1–19 caracteres e slot 1–160, o botão **Ler destino e salvar backup** deve estar habilitado. Quando alguma condição faltar, o motivo aparece abaixo.
6. Faça/exporte o backup. O botão **Revisar e enviar preset** aparece depois dessa etapa. Confirme a substituição e aguarde a comparação por leitura.
7. Ao trocar de preset para a mesma MK300, a conexão verificada é mantida; o backup anterior é invalidado e deve ser feito novamente. Trocar de modelo encerra a conexão e exige nova confirmação.
8. Para excluir, use o menu da música ou a lixeira na tela de resultados. O diálogo informa que remove **a análise com base e solo do aplicativo**. Cancelar preserva tudo; confirmar deve remover a entrada mesmo após reabrir o app. Nenhum preset do pedal ou arquivo de backup é excluído. O resultado original no backend não é removido.

## Limites mantidos

MK20 permanece com gravação bloqueada; o perfil não foi capturado. BLE MK300 continua experimental. O roteiro e os detalhes do protocolo estão em `docs/CONECTIVIDADE_V1_1_0.md`. A seleção não converte presets MK20 para MK300: para outra pedaleira, gere uma nova análise escolhendo o modelo desejado.

## Validação

Há teste de interface com transporte USB simulado que reproduz o problema: leitura válida + preset antigo mantém o botão bloqueado; selecionar um preset recente de outra análise na mesma conexão habilita o backup. Outros testes conferem cancelar/confirmar exclusão, persistência e preenchimento da nova análise. Isso não substitui escrita física no pedal.

Resultado desta revisão: 21 testes Flutter passaram, incluindo o cenário de conexão válida/preset antigo e troca para preset atualizado na mesma sessão. Análise estática sem apontamentos. APK release gerado e assinatura verificada, versão 1.1.1, build 4. O backend não foi alterado nesta correção de interface. Os APKs anteriores permanecem preservados.
