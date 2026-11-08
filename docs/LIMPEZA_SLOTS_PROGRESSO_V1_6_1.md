# V1.6.1 — nova biblioteca, destino MK20 e progresso da separação

Solicitação: apagar músicas e presets dos testes para gerar novamente, liberar o slot de destino e acompanhar o processamento dos instrumentos.

## Limpeza solicitada

O backend foi parado antes da limpeza para impedir que tarefas anteriores republicassem resultados. Foram apagados 13 pares de presets, 11 tarefas e os registros associados de referências, estados de timbre, pesquisa e gerações reaproveitadas. Os arquivos de músicas importadas e instrumentos separados em `backend/data/generation_inputs` e `backend/data/separations` foram removidos.

No primeiro início do Android 1.6.1, `LibraryReset.applyOnce` apaga a biblioteca local, os presets arquivados, snapshots de pilotos e vínculos de presets importados. A marca `library_reset_20261108_done` impede que a limpeza se repita e exclua novas gerações. A migração ocorre antes de carregar `PresetStore` e aposenta os arquivamentos antigos.

Preservados: gravações de guitarra, relatórios/backs de recuperação dos pedais, endereço do backend, catálogos, modelos de IA e músicas originais do repertório fora da biblioteca do app. A limpeza não altera os presets gravados fisicamente nos pedais.

Manutenção offline: parar `ai-tone-studio.service`, executar `backend/.venv/bin/python tools/reset_app_library.py --backend-stopped-and-delete` e iniciar novamente o serviço. Não é executada a cada inicialização do servidor. Essa exclusão de biblioteca não é revertida simplesmente instalando um APK antigo.

## Slot de destino

O campo agora permite escolher **1–150 na MK20**; a MK300 continua com **1–160**. O padrão MK20 ainda é 150, mas é editável. Trocar o campo invalida o envio preparado e exige ler o novo destino/salvar seu backup.

MK20 usa endereço `(slot - 1) × 412`, comando de banco próprio `0xD21`, imagem de 412 bytes e nome de até 16 caracteres ASCII. O slot fica registrado no nome do backup, conteúdo JSON, envio, relatório e restauração. A restauração mostra explicitamente o slot do backup, mesmo quando o campo de envio está em outro destino. O backend rejeita evidência de leitura/escrita em endereço diferente daquele backup.

Permanecem: confirmação explícita, cópia do original, conferência do conteúdo atual antes de sobrescrever, ACK de banco e commit, leitura completa após a gravação e nenhuma repetição automática de escrita. Backups anteriores do slot 150 continuam recuperáveis. O botão restaura o último backup completo, com seu destino identificado.

Os novos slots têm testes automatizados de endereço, fluxo e restauração. A evidência física anterior continua sendo do slot 150; o usuário ainda precisa conferir outro destino no pedal.

## Evolução real da separação

O worker mantém a mesma inferência Demucs, segmentos de quatro segundos, overlap 0,25, float32, seeds e identidade de cache anteriores. Apenas o iterador de progresso foi instrumentado. Um bloco só é contado após `future.result()` e a mistura do resultado pelo Demucs. Em ensembles a contagem inclui todos os membros.

Eventos JSON são transmitidos imediatamente do subprocesso para a API. O app consulta a tarefa a cada dois segundos e mostra `blocos concluídos/total`, percentual dessa etapa e tempo decorrido na tela. O percentual geral é ponderado por etapas, não uma estimativa exata de duração restante. Base e solo usam intervalos distintos para evitar que o segundo processamento fique escondido pelo máximo do primeiro. Carregamento do modelo, espera de CPU e salvamento têm mensagens próprias; o contador não avança por um temporizador fictício. Só há 100% geral quando toda a tarefa termina.

O timeout continua em uma hora, com encerramento do subprocesso e limpeza de arquivos incompletos. Erro não é convertido em sucesso nem aciona fallback silencioso para a mixagem. Atualizações de progresso são persistidas com limite de uma gravação por segundo; processamento interrompido ainda é reportado como falha após reinício.

## Verificação

- 172 testes do backend e 107 testes Flutter; `flutter analyze` sem problemas.
- Relatório produzido pela interface Flutter com pedal simulado no slot 76 também foi aceito pelo validador Python, com dois comandos de escrita e leitura completa. Não substitui teste físico.
- Backend reiniciado como serviço: health 1.6.1 e biblioteca HTTP `songs: []`. Assinatura e versão do APK conferidas.
- Teste real com Demucs em áudio estéreo de quatro segundos: eventos `loading`, 0/2, 1/2, 2/2 e `saving`; seis WAVs produzidos.
- Casos de endereço nos slots 1, 76, 149 e 150, compatibilidade com backup anterior e rejeição de slot divergente.
- Teste da interface altera o destino de 150 para 76 antes de preparar/enviar.
- Limpeza validada em armazenamento isolado, incluindo preservação de gravações/recuperação e execução única no celular.

APK: `releases/ai-tone-studio-v1.6.1-develop.apk`, versão 1.6.1+25, mesmo identificador e assinatura anteriores. Instalar a atualização e abrir o app para concluir a limpeza local; depois importar a música novamente.
