# Estados sonoros e pesquisa de equipamento — Android/API 1.5.0

## Usar no aplicativo

1. Abra a análise de Everlong e expanda **Timbres ao longo da música**. A análise já preparada no backend será recuperada. Para outras músicas já separadas, toque **Detectar timbres e pesquisar fontes**, sem importar o áudio novamente.
2. Confira artista, título e versão (estúdio, ao vivo, acústica ou desconhecida). Corrigir esses dados atualiza a pesquisa; não troca o arquivo da música.
3. Cada estado propõe um caráter (limpo, crunch ou distorcido), canal e trecho representativo. Escolha MK300 e **Gerar base deste timbre** ou **Gerar solo deste timbre**. Uma mesma função pode ter variantes limpas e distorcidas. A correção opcional do caráter não exige editar knobs.
4. A variante é salva na biblioteca e abre o envio com a parte correta. Leitura, backup e confirmação do slot continuam obrigatórios. Depois, grave pela USB em **Comparar meu timbre**: a referência de 3–12 segundos daquele estado já está vinculada, sem pedir o original novamente.

Novas análises pelo app também pedem detecção de estados e pesquisa após a separação. Clientes anteriores continuam aceitos. Falha nessa etapa adicional preserva os presets gerados e permite repetir a detecção na tela de resultados.

Os presets existentes permanecem intactos. Cada geração cria um par compatível com a biblioteca atual: a parte escolhida é nova e a outra é uma cópia preservada da análise de origem. Isso fica registrado no resumo. Repetir a mesma geração reutiliza a variante e preserva as edições locais; não duplica a entrada. A versão anterior do app continua disponível.

## 1. Detecção temporal

`segmentation.py` mede janelas de 6 s com avanço de 3 s, por canal, no stem `guitar` persistido. Usa bandas relativas, MFCC sem coeficiente de nível absoluto, dinâmica e proxy de distorção. Agrupamento KMeans determinístico, avaliação de separação e suavização temporal propõem de um a quatro grupos por canal; não são forçados quatro presets. Silêncio abaixo de −60 dBFS é ignorado. Canais praticamente idênticos são deduplicados; L/R diferentes são mantidos.

Cada grupo contém intervalos recorrentes e uma referência real de até 12 s próxima ao centro do grupo. O cache inclui versão do algoritmo, origem e deslocamento temporal. A integridade do stem é verificada antes da reutilização. Rotulagem limpo/crunch/distorcido usa limiares heurísticos do proxy, com confiança baixa e indicação de fronteira ambígua nos dados.

Isso detecta comportamentos diferentes; não demonstra que uma troca de amplificador ocorreu. Notas, execução, vazamento ou sobreposição também podem criar grupos. O separador continua sendo Demucs `htdemucs_6s`: há um stem de guitarra, não isolamento garantido de duas guitarras simultâneas. Canal L/R não significa base/solo. Não há classificador treinado de distorção nem reconhecimento garantido do solista.

## 2. Variantes de preset e comparação

`POST /api/v1/presets/{pair_id}/tone-states/{state_id}/generate` recebe função, dispositivo e caráter opcional. Recorta os stems existentes e analisa explicitamente o canal selecionado, sem nova inferência Demucs. A referência e os diagnósticos salvos passam a corresponder ao trecho, não ao perfil médio da música inteira.

A identidade inclui par de origem, versão, cache, estado, função, pedal, caráter e revisão da pesquisa. Seleções de pesquisa desatualizadas são rejeitadas. O original não é sobrescrito. MK20 continua com catálogo parcial e envio bloqueado; esta entrega não habilita escrita nesse dispositivo.

## 3. Pesquisa web com origem e contexto

`SongResearch` pesquisa artista/título via Bing RSS, consulta até quatro páginas de domínios de publicações/fabricantes permitidos e registra URL, título, contexto, data de consulta, hash da página e situação da leitura. Cache de sete dias; botão **Pesquisar novamente na web** força atualização. O provedor é substituível; `TONE_WEB_RESEARCH=0` desativa consultas externas. Apenas artista e título entram na busca, sem envio da música ou da gravação USB.

Há fichas primárias revisadas de Foo Fighters. Novas músicas usam descoberta automática; ausência de resultados úteis fica explícita. Menções automáticas só oferecem uma pista nominal muito fraca quando dois domínios citam artista, música e família. Isso não comprova a sessão ou a versão enviada. Conteúdo das páginas é tratado como dado, sem execução de instruções nem extração de knobs por LLM.

Fontes verificadas para o piloto em 28/10/2026:

- [Produce Like A Pro: entrevista com Bradley Cook sobre Everlong](https://producelikeapro.com/blog/foo-fighters-everlong-inside-the-song/). Fonte sobre a gravação; o texto não informa AMP/CAB. O vídeo não foi transcrito, portanto não foi usado para inventar modelos ou controles.
- [Premier Guitar: entrevista com os guitarristas de Foo Fighters (2024)](https://www.premierguitar.com/podcast/shred-with-shifty/foo-fighters-tones-like-these). História do equipamento ao vivo, incluindo Dual Rectifier e Tone Master; não confirma o rig da gravação de Everlong. A referência a 4x12 não foi atribuída a uma marca sem evidência.

No teste direto do backend, a página Premier Guitar respondeu, mas Produce Like A Pro não pôde ser relida; o app sinaliza essa indisponibilidade e mantém a ficha revisada. Consultas públicas podem falhar ou retornar resultados irrelevantes. Não há promessa de descobrir equipamento para qualquer música.

## 4. Escolha de AMP/CAB

`evidence_mapping.py` restringe candidatos aos modelos reais do catálogo do pedal e à família de saturação proposta. Pistas documentais desempatam/priorizam famílias; fonte ao vivo tem peso zero quando a referência é declarada estúdio ou acústica. Cada escolha registra alternativas, origem e limitação. Pontuação de prioridade não é percentual de fidelidade.

O motor refina EQ pelo descriptor medido e usa pontos iniciais de Gain 15/38/65 para limpo/crunch/distorcido, dentro das escalas catalogadas. O drive inicial vem do AMP; DS desligado não equivale a som limpo. São regras explícitas, sem renderer calibrado da pedaleira ou otimização acústica. O uso de IA na separação e agrupamento não transforma a geração de knobs em um modelo treinado. Confiança continua baixa, sem elevar rótulos artificialmente. A fidelidade exige escuta e captura real de cada variante para orientar a próxima calibração.

## API, dados e recuperação

- `GET /api/v1/presets/{pair_id}/tone-states`: último resultado salvo, ou 404 antes da detecção.
- `POST /api/v1/presets/{pair_id}/tone-states/analyze`: `version`, `refresh_research`, `artist`, `song_title` opcionais.
- Geração por estado: `role`, `device`, `character`, `research_id`, `research_revision`.
- Upload e geração salva aceitam `analyze_states` e `reference_version`; app atual solicita essa etapa, clientes antigos mantêm comportamento anterior.

Registros SQLite adicionais: `tone_states`, `pair_tone_states`, `song_research`. Variantes usam os registros existentes `pair` e `comparison_reference`, e recortes ficam em `separations/`. Fazer backup de todo `backend/data/`, ou de `TONE_DATA_DIR`; Git não armazena áudios, SQLite, pesos nem APK. Não há migração destrutiva. Ponto anterior: commit `e95ffae` em `develop`; `main` preserva `56fbfbf`.

## Validação

Teste real de Everlong com a guitarra já separada: cerca de 26 s para detectar dois comportamentos por canal. Propostas de menor saturação em **192–204 s** e distorcido em **117–129 s**. Esses são trechos representativos medidos, não validação humana do rótulo limpo. Resultado resumido em [exemplo de validação](exemplos/everlong-estados-v1.5.0.json).

Em snapshot isolado do SQLite, quatro variantes MK300 foram geradas: base/solo limpos (`1J120_CL`, Gain 15) e base/solo distorcidos (`4J900_HV`, Gain 65). A pesquisa foi configurada como estúdio, portanto pistas do rig ao vivo não participaram da escolha. Foi confirmada referência de 12 s por função, canal consistente, idempotência e preservação do par original. Demucs foi bloqueado no teste para comprovar reutilização. Não foram criadas gravações sintéticas ou variantes de teste no banco de uso do app, nem enviados comandos ao pedal.

Testes automatizados cobrem agrupamento sem forçar estados, mudanças apenas de volume, silêncio, fase estéreo, cache, contexto documental, fontes rejeitadas, modelos válidos MK300/MK20, referências, idempotência, preservação de edições e navegação para a função correta. A avaliação sonora física permanece com o usuário.

Validação automatizada final: **106 testes backend e 69 testes Flutter** passaram; `flutter analyze` sem problemas. Android **1.5.0+17**, com applicationId e certificado de assinatura preservados das entregas anteriores. APK local em `releases/ai-tone-studio-v1.5.0-develop.apk`; SHA256 no arquivo adjacente. A API local responde 1.5.0.
