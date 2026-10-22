# Referências por parte e nível USB — Android/API 1.4.2

## Fluxo sem reenviar a música

Na comparação, o preset determina a parte: **Base** ou **Solo**. A tela consulta o backend e mostra a música e o intervalo salvos. Para presets do motor v2, não há seletor do áudio original nessa tela. Gravar a mesma passagem pela USB e analisar continua preservando a captura original no backend.

Em **Nova análise**, ativar **Usar música já separada** e escolher a música na biblioteca do backend. Os trechos de base e solo são preenchidos com as referências salvas. Alterar o pedal de cada parte continua possível. O backend usa os stems existentes e recorta os intervalos; não executa Demucs novamente nem pede arquivo no celular. O original arquivado é lido no servidor para manter sua identidade e metadados.

A biblioteca agrupa pelo SHA256 do original, preserva a fonte com maior cobertura disponível e não confunde músicas com o mesmo título. Presets antigos, sem instrumentos persistidos, continuam podendo exigir o original uma vez. A biblioteca não importa automaticamente separações avulsas do laboratório.

Pedidos repetidos de geração salva, com a mesma origem, configuração e intervalos, reutilizam o job concluído/em andamento. O aplicativo preserva o preset já existente e suas edições locais, sem sobrescrevê-lo com a versão original do servidor nem adicionar outra entrada. O banco mantém as versões geradas anteriormente.

## Seleção de guitarra base e solo

O modelo de separação retorna um stem **guitar**, que pode incluir guitarras simultâneas. Base e solo são referências de trechos distintos, não dois stems neurais independentes nem uma detecção garantida do solista.

Se só estiver salva a música inteira, escolher **Ajustar trecho da guitarra salva**, informar início/duração e salvar uma vez. O backend mede a guitarra separada e associa o perfil à função, preservando o original e os stems. As próximas comparações e gerações preenchem esse intervalo automaticamente. O backend bloqueia comparação de uma referência v2 com mais de 120 segundos sem seleção da parte, em vez de apresentar a música inteira como um solo isolado.

Para Infest, a aprovação humana existente já define base **50–70 s** e solo **160–180 s**. O script `repertorio/laboratorio/scripts/vincular_trechos_aprovados_v2.py` confere SHA256 do original, aprovação, intervalos e integridade do cache antes de associá-los. Foi aplicado ao par `e9cb44b0-f142-452c-bf21-49515ef715ac`, preservando presets e capturas. Esse registro aprova o momento da música; não certifica pureza da separação ou fidelidade sonora.

## Saturação e ajuste pelo aplicativo

A captura real mais recente analisada nesta entrega contém aproximadamente **3,43%** de amostras no limite digital, mesmo com volume global declarado do preset em **40**. O arquivo original e seu resultado histórico foram preservados. Esse diagnóstico não identifica em qual estágio do equipamento/Android ocorreu a saturação.

A captura nativa passa a informar pico em dBFS, tempo gravado e proporção cumulativa de amostras no limite. O app mostra medidor de nível durante a gravação e alerta de saturação. Isso mede o sinal recebido; não aplica redução ou normalização aos bytes do WAV. Os efeitos de captura e a seleção USB já existentes continuam preservados.

No resultado saturado de um preset MK300 com volume global conhecido, usar **Reduzir volume 40 → 30 e seguir para envio**. O aplicativo:

1. Reduz somente o volume global do preset para 75% do valor atual, com mínimo 1. Esses são valores do controle, não uma redução em dB calibrada.
2. Preserva Gain, modelos, EQ e todos os demais blocos, nome e identidade do preset.
3. Salva a alteração na mesma entrada da biblioteca e abre o envio USB existente, com leitura, backup e confirmação.
4. Exige nova gravação para verificar se a saída USB responde a esse controle.

Não há escrita automática no pedal nem reparação de áudio já saturado. Presets sem volume conhecido não recebem um valor inventado. Se a captura continuar saturando após o envio, será necessário investigar o nível USB independente ou a entrada do equipamento; o controle global do preset não foi comprovado fisicamente como controle da captura USB.

## API e persistência

- `GET /api/v1/reference-library`: músicas com stems de guitarra persistidos, funções e intervalos.
- `GET /api/v1/presets/{pair_id}/reference/{rhythm|lead}`: contexto da referência automática.
- `PUT /api/v1/presets/{pair_id}/reference/{rhythm|lead}` com `start_seconds` e `duration_seconds`: seleciona intervalo dentro do cache existente, de 3 a 120 s.
- `POST /api/v1/analyze-saved` com `pair_id`, `rhythm_device`, `lead_device` e, opcionalmente, `rhythm_region`/`lead_region`: gera a partir dos instrumentos existentes. Não é um upload multipart.

Os registros `comparison_reference` preservam o perfil por par/função; `song_reference` guarda a seleção explícita por SHA256/função para reutilização. `saved_generation` registra a identidade da geração para evitar duplicatas. Os recortes dos stems possuem manifest e hashes próprios dentro de `backend/data/separations/`. Fazer backup de todo `TONE_DATA_DIR`.

## Verificação e limites

Testes cobrem seleção por função, referências persistidas, geração sem chamar Demucs, reutilização de job, integridade e limites dos recortes, navegação para o solo correto, ausência de seletor de arquivo no v2, preenchimento da biblioteca, redução somente do volume e preservação das edições locais.

Foi executado o fluxo completo com o arquivo real Infest em diretório de dados de teste: reutilização do stem completo, recortes 50–70/160–180 s, geração MK300, download de ambas as referências e repetição idempotente do pedido. O provider Demucs foi substituído por uma função que falharia se chamado; o fluxo concluiu sem nova inferência. Não foram criadas capturas sintéticas no banco real.

A qualidade sonora do preset, o medidor em uma MK300 real e o efeito da redução global sobre a USB ainda precisam do teste físico do usuário. A comparação continua DSP heurística e não apresenta percentual de fidelidade. Como próxima evolução, uma escuta A/B com volume de reprodução equiparado ajudará a revisar as referências e comparar o som sem confundir diferença de volume com diferença de timbre; ela não faz parte desta entrega.

Validação final: **97 testes backend e 67 testes Flutter** passaram; `flutter analyze` sem problemas. APK release Android **1.4.2+16** compilado com o mesmo applicationId/certificado debug das entregas anteriores. Hash em `releases/ai-tone-studio-v1.4.2-develop.apk.sha256`. API local `/health` responde 1.4.2.
