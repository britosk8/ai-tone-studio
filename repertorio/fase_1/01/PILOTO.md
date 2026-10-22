# Piloto concentrado — música 01: Papa Roach / Infest

## Escopo acordado

Trabalhar primeiro somente nesta gravação. Validar referência, separação, captura e evolução dos presets de base e solo/destaque na MK300. As músicas 02–06 mantêm o material já preparado, mas ficam em espera para novos experimentos. MK20 permanece para uma etapa posterior. Este roteiro não muda o funcionamento do aplicativo.

## Trechos principais aprovados — etapa concluída

Os tempos abaixo são relativos ao M4A fornecido. Os dois trechos principais foram aprovados pelo usuário em 22/10/2026. As alternativas não foram selecionadas.

| Papel proposto | Principal | Alternativa |
| --- | --- | --- |
| Base | [00:50–01:10](trechos/candidato_base_01_0050s.wav) | [03:10–03:30](trechos/candidato_base_02_0190s.wav) |
| Solo/destaque | [02:40–03:00](trechos/candidato_solo_destaque_01_0160s.wav) | [01:30–01:50](trechos/candidato_solo_destaque_02_0090s.wav) |

A escolha dos tempos está concluída. Agora precisamos avaliar qual extração de guitarra preserva melhor o som dessas passagens; isso não foi aprovado apenas por confirmar os tempos.

A [página de revisão](../REVISAO_REFERENCIAS.html) começa pela música 01 e permite registrar decisões. Nesta rodada, avaliem somente o primeiro bloco, de Infest; os demais podem permanecer pendentes.

## Testes em sequência

1. **Referência musical:** confirmar uma passagem de base e, se aplicável, uma de solo/segunda guitarra. Registrar tempos e objetivo sonoro na FICHA.md.
2. **Separação:** comparar a mixagem com [guitarra do candidato de base](../../fase_2/piloto_htdemucs_6s/01_base_01/guitar.wav) e [guitarra do candidato de solo/destaque](../../fase_2/piloto_htdemucs_6s/01_solo_destaque_01/guitar.wav). Observar voz/baixo/bateria que vazaram, harmônicos perdidos e artefatos. “guitar” pode conter as duas guitarras. Se o trecho escolhido mudar, gerar a separação do novo trecho antes de usá-lo como referência.
3. **Som atual:** preservar os JSONs dos presets da MK300 e gravar as passagens usando a saída do pedal → MQ44 → notebook. Pai/Konig SSS para base e filho/Strinberg HH para solo inicialmente. Anotar seletor, volume/tone, níveis e firmware. Não misturar o acompanhamento na captura.
4. **Repetibilidade:** repetir a captura e verificar se níveis/execução permitem comparar. Validar separadamente se conseguimos reproduzir uma gravação limpa através da MK300; captura de saída não comprova reamp.
5. **Ajustes controlados:** comparar alternativas com volume de escuta equivalente, preservar o preset inicial e registrar o que mudou e por quê. Começar com amp/cabinet/ganho/EQ e depois avaliar efeitos conforme a qualidade da referência.
6. **Resultado na banda:** conferir o timbre isolado e junto da música, registrar limitações e repetir a validação em outra passagem de Infest que não tenha sido usada no ajuste.

## Quando avançar para a música 02

Avançar após registrar: referência aprovada, qualidade/limitações da separação, presets iniciais e finais, capturas reproduzíveis, comparação auditiva e procedimento documentado. Se alguma etapa não funcionar, ajustar o método em Infest primeiro. Não há percentual automático de perfeição como critério.

O escopo de planejamento está em `../../laboratorio/escopo_piloto.json`. Ele documenta o foco; não é um bloqueio programático dos scripts ou do aplicativo.

## Atualização de 22/10/2026

O usuário aprovou os dois trechos principais: base 00:50–01:10 e solo/destaque 02:40–03:00. Registro em [APROVACAO_REFERENCIAS.json](APROVACAO_REFERENCIAS.json). A escolha de tempos está concluída; a qualidade dos stems ainda não foi aprovada.

A próxima escuta é a [comparação das duas extrações de guitarra](../../fase_2/infest_comparacao/VALIDAR_GUITARRAS.html), com cópias igualadas em RMS. Também foi preparado o [roteiro de captura no Windows](CAPTURA_WINDOWS.md). Nenhum preset foi modificado ou escrito no pedal.

## Presets iniciais R1 gerados

Os dois presets foram gerados antes das capturas, usando análises independentes das referências aprovadas. Veja [carregamento e teste](presets/piloto_r1/README.md). APK V1.2.3 acrescenta importação local para carregá-los e seguir ao envio existente. O backend permanece V1.2.2. Nesta rodada, aplique os presets R1 e só depois grave as tomadas; capturar os presets antigos é opcional. A qualidade dos stems e a fidelidade dos presets permanecem sem aprovação auditiva.
