# Contexto e captura da fase 1

## Informações confirmadas

- Repertório: as seis gravações M4A em `01` a `06`; são as versões que a banda pretende seguir.
- Pai: guitarra base, Konig Stratocaster com três captadores simples (SSS); pedaleira habitual MK20.
- Filho: guitarra solo, Strinberg Les Paul com dois captadores duplos (HH); pedaleira habitual MK300.
- Piloto: presets de base e solo na MK300; adaptação à MK20 em fase posterior.
- Caminho informado: saída de áudio da pedaleira → interface Depusheng MQ44 → notebook → monitores Tomate MTS 2043.
- Ainda desconhecidos: firmware atual, posição do seletor, volume/tone de cada guitarra, conexão elétrica exata à MQ44 e possibilidade de reamp pela USB da MK300.

## O que já está pronto

Os originais foram preservados. Há quatro recortes de 20 segundos por música: dois candidatos de base e dois de solo/destaque. A seleção usa CLAP com descrições de áudio, não um modelo validado especificamente para as partes deste repertório. Nenhum candidato está aprovado musicalmente. “Solo/destaque” não significa que a música necessariamente possua solo tradicional.

Abra `REVISAO_REFERENCIAS.html` no navegador do notebook. Ouça o original e os candidatos, marque as decisões e baixe o JSON de revisão. Guarde a cópia em `laboratorio/relatorios/` ou nos envie o arquivo. A página não salva decisões automaticamente. Quando necessário, anote outro início/fim na ficha da música. Há duas passagens da primeira triagem arquivadas como descartadas no manifesto; não integram as 24 referências ativas.

## Registro do som atual (pendente; exige os instrumentos)

1. Exporte pelo aplicativo os presets atuais da MK300 em JSON e salve em `NN/presets/`. Preserve a versão inicial; não sobrescreva com ajustes futuros.
2. Registre na ficha: guitarra, captador selecionado, volume/tone, firmware, preset, níveis da interface e frequência de amostragem da sessão.
3. Grave a guitarra sozinha pela cadeia já usada, sem a música misturada na captura, sem efeitos adicionais de software, normalização ou ganho automático. Escute a referência em fones se o acompanhamento puder vazar na gravação.
4. Ajuste os níveis antes da tomada para não saturar pedaleira, interface ou arquivo. Registre a configuração e mantenha-a constante entre as alternativas comparadas. Não reduza apenas o volume de reprodução para tentar corrigir clipping de captura.
5. Registre duas execuções de 20 segundos da mesma passagem. Comece pela Strinberg HH no solo e pela Konig SSS na base; depois faça os testes cruzados de base/solo na MK300 conforme o objetivo do piloto.
6. Salve em WAV na taxa nativa de captura da sessão (44,1 ou 48 kHz conforme suporte/configuração), preferencialmente 24 bits quando disponível. Não é necessário converter o original M4A para “melhorar qualidade”.
7. Sugestão de nome: `01_base_Konig_SSS_POSICAO_preset_atual_t01.wav` ou `01_solo_Strinberg_HH_POSICAO_preset_atual_t01.wav`. Substitua POSICAO pela realmente utilizada.

## Comparação A/B

Compare a referência de guitarra e a captura com volume de escuta equivalente. Avalie separadamente: distorção/textura, graves/médios/agudos, ataque/sustain, ambiência e presença no conjunto. Anote preferências e defeitos com palavras; não invente percentual de fidelidade.

A mixagem contém voz, baixo, bateria, outras guitarras e processamento de produção. Os stems do piloto de IA também podem conter vazamento/artefatos. Nenhuma dessas referências equivale automaticamente à pista de estúdio original.

## Reamp (a validar)

A interface capturar a saída do pedal não comprova que uma gravação limpa possa retornar ao pedal pela USB. Precisamos verificar esse caminho com o equipamento. Se ele não existir, a alternativa depende de interface/roteamento e adequação de nível/impedância. Não conectar saída de potência de amplificador à interface.

A fase 1 não fica encerrada apenas com os recortes: faltam aprovar referências, capturar o som atual e validar a repetibilidade. Esta preparação não cria nem instala novos presets no pedal.
