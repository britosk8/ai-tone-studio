# Gravação da guitarra preservada no backend — V1.3.4

Android 1.3.4+13 e API 1.3.4, branch `develop`. O usuário pode gravar pelo USB-AUDIO da MK300 no aplicativo e tocar **Analisar e sugerir ajustes**. Essa ação já enviava o arquivo de guitarra para o backend; antes, ele era apagado ao terminar a comparação. Agora o arquivo original recebido permanece armazenado. Não é necessário gravar no Windows ou anexar a captura na conversa.

## Fluxo e limites

1. Atualizar o APK por cima do instalado.
2. Selecionar no app o preset que está tocando e gravar pela entrada USB/OTG da MK300.
3. Tocar **Analisar e sugerir ajustes**. O backend preserva o arquivo antes da medição/comparação.
4. O resultado confirma **Gravação da guitarra salva no backend**. O arquivo e o relatório podem ser consultados diretamente no servidor.

O upload acontece ao analisar, não imediatamente ao parar a gravação. Uma captura que ainda não foi enviada permanece apenas no celular. Sem conexão com o backend, o arquivo não pode ser salvo nele. Não há fila de upload em segundo plano nesta versão. Gravações antigas apagadas das requisições anteriores não são recuperadas retroativamente.

A mudança vale também para entradas de microfone e arquivos de guitarra importados, identificando a origem declarada em `input_kind`. O arquivo é preservado sem transcodificação, normalização, redução de ruído ou mudança de taxa/canais. O preset registrado é o selecionado no aplicativo; esta operação não consulta o preset ativo do hardware. A geração por música e as sugestões DSP não foram alteradas.

## Persistência e consulta

Os arquivos ficam em `TONE_DATA_DIR/recordings/`, por padrão `backend/data/recordings/`. O volume Docker `/app/data` existente já cobre essa pasta. Metadados e resultados ficam no SQLite em `records`, kind `guitar_recording`:

- ID, análise, função base/solo, origem declarada e snapshot completo do preset enviado;
- nome original, tamanho, SHA-256 e nome de arquivo interno;
- datas de criação/atualização e estado `received`, `needs_reference`, `failed` ou `completed`;
- medições, perfil da referência e último resultado bem-sucedido, quando disponíveis;
- último erro, inclusive quando a análise não pôde terminar.

O conteúdo enviado, o ID da análise, o preset, a origem e a extensão determinam uma identidade estável. Reenviar a mesma captura no mesmo contexto reutiliza o registro/arquivo; enviar outro áudio ou outro preset gera outro registro. A referência musical pode ser selecionada em uma nova tentativa sem duplicar a gravação já recebida. Se uma tentativa posterior falhar, o último relatório bem-sucedido continua preservado e o estado/erro atual identifica a falha.

```text
GET /api/v1/recordings?pair_id={id}&role=rhythm&limit=100
GET /api/v1/recordings/{recording_id}
GET /api/v1/recordings/{recording_id}/audio
```

Listagem com filtros opcionais por análise e função, ordenada por criação recente e limitada a 100 por requisição. Download confere caminho e hash antes de servir o original. Não há exclusão automática nesta versão; os dados permanecem no volume do backend, fora do Git.

## Falhas e integridade

Capturas recebidas são preservadas mesmo se houver silêncio, clipping ou falta de perfil original. Isso permite investigar problemas de rota/nível posteriormente. O estado do registro distingue áudio recebido de análise concluída; salvar não significa que a gravação seja válida ou que o preset tenha fidelidade aprovada.

Formatos não aceitos, arquivos vazios e uploads acima de 10 MB são rejeitados antes do arquivamento. Os limites de duração da comparação continuam em 3–30 segundos; uma captura recebida que falhe na medição pode ficar arquivada como diagnóstico. Música original enviada para referência continua temporária: somente seu perfil é persistido, não o arquivo completo.

A resposta bem-sucedida inclui `recording_saved`, `recording_id` e `recording_audio_url`. Erros após o arquivamento também informam `recording_saved`/`recording_id`, preservando o formato anterior de `detail`. O app distingue erro de comparação de perda do arquivo e informa quando a gravação está preservada. A limpeza da pasta temporária da requisição não remove o arquivo permanente.

## Backup

Copiar todo `TONE_DATA_DIR`, incluindo SQLite e `recordings/`. Git e APK não contêm as capturas e restaurar somente o banco não recupera os arquivos de áudio. O diretório padrão já está excluído pelo `.gitignore`.

## Validação da entrega

84 testes backend e 61 Flutter passaram; `flutter analyze` sem problemas; build release concluído. Os testes cobrem bytes/hash e download integral, recuperação sem caches, preset e contexto, falta de referência com arquivo preservado, retry sem duplicata, mudança de preset, silêncio/clipping, upload vazio/inválido/acima do limite, integridade/caminho do download e confirmação de salvamento no app.

APK `releases/ai-tone-studio-v1.3.4-develop.apk`, SHA-256 adjacente. Pacote `com.aitone.studio`, versão 1.3.4/build 13; assinatura compatível com a instalação anterior. Backend local já verificado em V1.3.4 e `/api/v1/recordings` disponível. Os testes usaram arquivos sintéticos e diretórios isolados; nenhuma gravação real do usuário foi recebida nesta sessão. As próximas capturas enviadas pelo app serão preservadas.
