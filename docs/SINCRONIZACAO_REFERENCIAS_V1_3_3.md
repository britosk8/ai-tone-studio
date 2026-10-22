# Referências no backend e correção da comparação — V1.3.3

Android 1.3.3+12 e API 1.3.3 em `develop`. O fluxo principal continua sendo gerar a partir da música; o preset conhecido é uma referência auxiliar de configuração.

## Sincronização

Ao abrir o app com backend disponível, a tela inicial procura referências locais associadas às análises existentes e envia as de base/solo ao servidor. Isso inclui o Gohth importado na V1.3.2: não é necessário lê-lo novamente do pedal. Abrir a referência também tenta sincronizar. O botão **Sincronizar referência com o backend** permite repetir a tentativa e a tela informa se a referência foi salva no backend ou se a sincronização ficou pendente.

Importar do pedal continua sendo leitura USB. Primeiro salva no celular, fecha a conexão com a pedaleira e depois tenta o backend. Falha de rede não remove a cópia local nem altera os presets gerados. Ao verificar o backend novamente na tela inicial, reabrir o app ou a referência, ocorre nova tentativa. Não há serviço de sincronização permanente com o app fechado.

## Dados persistidos e consulta

SQLite existente, tabela `records`, kind `pedal_reference`, ID estável formado por análise/função. Repetir o PUT atualiza o registro sem duplicar. Uma tentativa com captura mais antiga não substitui uma importação mais recente.

O registro contém:

- `reference`: slot, conexão, data e imagem original de 448 bytes em base64;
- `decoded_reference`: nome, cadeia, modelos, estados, controles raw, volume, pan e BPM decodificados no servidor;
- `generated_preset`: snapshot do preset gerado que está sendo comparado, com nome da música/arquivo e metadados existentes;
- `comparison`: linhas de modelos, controles e estados, com os dois valores e indicação de diferença;
- `synced_at` e `comparison_kind = configuration_not_audio_similarity`.

O servidor valida formato, base64, tamanho, constantes, cadeia, modelos e estados da imagem. Reconstitui os controles diretamente dos bytes e não confia em uma descrição de hardware enviada pelo cliente. Os nomes são do catálogo de fábrica; não identificam o conteúdo de NAM/IRs de terceiros. O snapshot gerado é registro do estado do app, não nova análise de áudio nem autorização para gravar no hardware.

Endpoints:

```text
PUT /api/v1/presets/{pair_id}/pedal-reference/{role}
GET /api/v1/presets/{pair_id}/pedal-reference/{role}
GET /api/v1/pedal-references
```

`role`: `rhythm` ou `lead`. A listagem retorna até 100 registros; os endpoints por análise/função permitem consultar diretamente cada referência. Os dados ficam no backend configurado pelo usuário. Na execução local padrão, banco em `backend/data/tone-studio.sqlite3`; respeita `TONE_DATA_DIR` e o volume Docker existentes. Não há exportação automática desses dados para Git.

## Causa e tratamento do 404

Presets importados, candidatos gerados no celular e cópias com IDs novos podem não ter análise correspondente no backend. A comparação de áudio chamava `_ensure_pair(pair_id)` e retornava `404 Preset não encontrado`, apesar de a requisição já enviar o preset completo.

Agora a comparação recebe o preset enviado e procura, nesta ordem por ID explícito, um perfil do trecho salvo para aquela função ou um perfil real de análise da música; para candidatos, considera também `generation_metadata.source_pair_id`. Não procura por título/nome do arquivo para evitar comparar versões diferentes da música.

Se não houver perfil, responde `400` estruturado com `code = reference_required` e mensagem para selecionar o áudio original. O app abre o seletor, preserva a gravação de guitarra e pede para conferir o início do trecho e analisar novamente. Cancelar mantém a captura e a mensagem orientativa. Há compatibilidade com a mensagem 404 legada durante a atualização do servidor.

Ao comparar com um arquivo original selecionado, o backend salva somente o perfil DSP do trecho, início, duração, nome e hash do arquivo, separado por análise/base/solo (`comparison_reference`). Não guarda o áudio completo. A próxima comparação pode reutilizar esse perfil, inclusive após reiniciar o backend. A resposta identifica `saved_excerpt_profile` e orienta tocar a mesma passagem; ao mudar de trecho, selecionar novamente o original.

Salvar configurações do pedal **não** cria um perfil acústico da música. O backend não inventa um perfil para evitar o erro. Quando ainda não houver áudio de referência, será necessário selecionar a música uma vez. O mecanismo de sugestões continua DSP conservativo de EQ; esta entrega não acrescenta um modelo treinado de matching nem um percentual de fidelidade.

## Validação da entrega

79 testes backend e 60 Flutter passaram; `flutter analyze` sem problemas; APK release compilado. Testes novos cobrem sincronização idempotente/recuperação após reinício, decodificação no servidor de nome e EQ negativo, rejeição de dados inválidos sem substituir o registro, proteção contra retry antigo, presets locais sem 404, seleção/reutilização do perfil original, isolamento por função, resolução do ID explícito da origem, envio do snapshot pelo app, funcionamento offline e abertura do seletor sem perder a gravação.

APK local `releases/ai-tone-studio-v1.3.3-develop.apk`, SHA-256 adjacente; pacote `com.aitone.studio`, versão 1.3.3/build 12, assinatura igual às versões anteriores. Instalar por cima, sem desinstalar. Backend local com autoreload já verificado em `/api/v1/health` como 1.3.3 e `/api/v1/pedal-references` disponível. No momento da entrega ainda não havia referências recebidas: o Gohth só chegará quando o app atualizado sincronizar. Nenhum dado foi extraído diretamente do celular ou da pedaleira nesta sessão.

## Vínculo posterior do piloto Infest

Após a atualização, o backend recebeu a referência **Ghoth**, associada a **Infest Base R1**. A abertura da pasta ao comparar era a solicitação do áudio original, pois ainda não havia perfil DSP vinculado a esse ID local. A gravação USB não era o arquivo solicitado.

O original de Infest já disponível no projeto foi vinculado explicitamente à análise sincronizada, usando os trechos aprovados: base 50–70 s e solo/destaque 160–180 s. `repertorio/laboratorio/scripts/vincular_referencia_infest.py --pair-id <id>` exige uma referência sincronizada cujo snapshot gerado corresponda à cadeia e aos metadados do R1 versionado; confere o SHA-256 do original e a aprovação dos intervalos antes de salvar os perfis. Não procura outras músicas por nomes aproximados, não usa o som do Ghoth como original e não sobrescreve perfis já existentes.

Validação no backend em execução: requisições de comparação para as duas funções retornaram HTTP 200 / `saved_excerpt_profile`, enviando apenas áudio sintético de teste, sem arquivo original na requisição. Não são resultados musicais da guitarra do usuário. Reexecução do vínculo preservou os registros; ID sem vínculo foi rejeitado sem gravação. Nenhum áudio, preset ou slot da pedaleira foi alterado; os perfis ficaram no SQLite local, fora do Git. Não exige novo APK para essa análise; em outras análises sem perfil ainda será necessário fornecer a referência original.
