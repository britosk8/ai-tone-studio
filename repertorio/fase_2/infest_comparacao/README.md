# Infest — comparação das extrações

Tempos aprovados pelo usuário em 22/10/2026: base 00:50–01:10 e solo/destaque 02:40–03:00. A qualidade da separação ainda não foi aprovada. Nenhuma outra música recebeu novo processamento nesta rodada.

Abra [VALIDAR_GUITARRAS.html](VALIDAR_GUITARRAS.html) para ouvir três versões por trecho: mixagem para contexto, guitarra da extração inicial e guitarra da nova rodada. Pause um player antes de iniciar outro.

| Configuração | Inicial | Nova rodada |
| --- | --- | --- |
| Modelo | htdemucs_6s | Mesmo modelo/checkpoint |
| Entrada processada | 20 segundos | 8 segundos antes e depois do trecho |
| Região entregue | 20 segundos | Os mesmos 20 segundos, alinhados |
| Segmento interno | 4 segundos | 7.8 segundos |
| Shifts | 0 | 1, com seeds fixas |
| Overlap | 0,25 | 0,25 |
| Dispositivo | CPU | CPU, 2 threads |

A nova configuração não é automaticamente melhor. Mudamos contexto, segmento e shift juntos nesta exploração; isso não isola a contribuição individual de cada fator. Caso necessário, faremos um teste controlado de cada variável depois da escuta.

As seis saídas raw de cada trecho foram preservadas sem normalização. As cópias `escuta_*.wav` foram igualadas por ganho constante em RMS dentro de cada grupo. Alvo: -24 dBFS RMS, reduzido se necessário para manter o pico de amostra abaixo de -1 dBFS. Não há EQ, compressor ou limitador. RMS equivalente não garante volume percebido idêntico. Cópias de escuta são PCM24 e saídas raw float32, ambas estéreo 44,1 kHz.

## Avaliação

Compare preservação de corpo, ataque, textura de distorção e caudas, vazamento de outros instrumentos, cortes e ruído aquático. Pode escolher a extração inicial, a nova, ambas ou rejeitar as duas. A saída guitar pode conter base e solo juntos. As métricas em comparacao.json descrevem diferenças; não medem pureza, SDR ou fidelidade.

Exporte as decisões pela página como `infest_avaliacao_separacao.json`. A aprovação dos tempos está em `../../fase_1/01/APROVACAO_REFERENCIAS.json` e permanece independente dessa avaliação.

## Captura e validação

Use o [roteiro do Gravador de Áudio do Windows](../../fase_1/01/CAPTURA_WINDOWS.md). A versão exata do programa e suas opções ainda não foram vistas; WAV/FLAC são preferidos quando disponíveis, mas o arquivo M4A original pode servir ao primeiro teste de rota/nível.

Verificamos 12 novos stems raw, seis cópias de escuta de 20 s, hashes, canais, taxa, valores finitos e picos. Maior diferença RMS medida entre cópias do mesmo grupo após leitura: 0.00000050 dB. Os 20 s de entrada coincidem amostra a amostra com as referências aprovadas. A aprovação permanece ao regenerar ficha, CSV, fila e manifesto.

81 arquivos protegidos e seis originais permanecem íntegros. Backend continua na V1.2.2, com ambiente separado do laboratório. Nenhum preset foi alterado ou enviado ao pedal. Capturas da MK300, repetibilidade, reamp e avaliação auditiva continuam pendentes.
