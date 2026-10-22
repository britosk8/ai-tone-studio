# Preparação das referências — 20/10/2026

## Atualização — 22/10/2026

O piloto está concentrado em Infest. O usuário aprovou base 00:50–01:10 e solo/destaque 02:40–03:00. Demais músicas ficam em espera. A avaliação da qualidade das extrações ainda está pendente; consulte [comparação da música 1](../fase_2/infest_comparacao/VALIDAR_GUITARRAS.html) e [captura no Windows](01/CAPTURA_WINDOWS.md). As observações de preparação abaixo registram o estado inicial de 20/10/2026.

As seis músicas foram analisadas localmente por CLAP, sem envio de áudio a serviços externos. Foram preparados 24 recortes ativos de 20 segundos, com duas alternativas para cada papel proposto. Os tempos são relativos aos M4A fornecidos, não a outras versões da internet.

**Pendente de aprovação musical.** Os papéis base e solo/destaque são propostas de triagem, não rótulos confirmados. Nem toda música contém solo tradicional; as referências podem precisar de troca após vocês ouvirem.

## Candidatos principais

| Pasta | Música | Base candidata | Solo/destaque candidato |
| --- | --- | --- | --- |
| 01 | Papa Roach - Infest | 00:50–01:10 | 02:40–03:00 |
| 02 | Hot Water Music - State Of Grace | 01:10–01:30 | 01:40–02:00 |
| 03 | Foo Fighters - Everlong | 00:50–01:10 | 04:00–04:20 |
| 04 | Alexisonfire - This Could Be Anywhere In The World | 02:40–03:00 | 01:00–01:20 |
| 05 | Matanza - Clube Dos Canalhas | 01:20–01:40 | 01:50–02:10 |
| 06 | Rage Against The Machine - Bombtrack | 02:50–03:10 | 03:20–03:40 |

Abra [REVISAO_REFERENCIAS.html](REVISAO_REFERENCIAS.html) para ouvir originais e candidatos, aceitar/trocar as classificações e baixar as decisões. As alternativas estão no [CSV](REFERENCIAS.csv) e nas fichas de cada pasta.

## Preparação real da fase 2

Os 12 candidatos principais foram processados com Demucs htdemucs_6s em CPU, gerando 72 WAVs: guitarra, vocais, baixo, bateria, piano e outros. Abra [OUVIR_SEPARACAO.html](../fase_2/OUVIR_SEPARACAO.html). A saída guitar pode conter base e solo juntos; não houve separação dedicada entre eles.

Fator de tempo médio medido: 1.38 vezes a duração do áudio, aproximadamente 27.5s de inferência por trecho de 20s neste notebook (sem incluir instalação/download e inicialização). Isso não prevê desempenho de outros modelos ou máquinas.

## Validações concluídas

- 6 originais e 81 arquivos protegidos de código/configuração/dados preservados por SHA-256.
- 24 WAVs ativos: 20 segundos exatos, 44,1 kHz, estéreo float32.
- Amostras dos recortes idênticas às respectivas regiões decodificadas dos originais (erro máximo medido 0).
- 72 stems finitos, com duração/formato e hashes conferidos.
- 114 vínculos de áudio nas duas páginas conferidos e sintaxe do JavaScript da revisão validada.
- 75 testes backend passaram; serviço permanece na V1.2.2.
- Venv do backend permanece sem torch e sem demucs; bibliotecas experimentais estão em venv próprio.
- O único arquivo novo de configuração na raiz é .dockerignore, excluindo repertorio/ do build Docker. Não houve alteração no código do aplicativo, catálogos, APKs ou configuração de execução.

## Pendências da fase 1

1. Vocês ouvirem e aprovarem os trechos; podem rejeitar todos e indicar outra passagem.
2. Exportar e preservar os presets atuais da MK300.
3. Capturar Konig SSS e Strinberg HH conforme [roteiro](CONTEXTO_E_CAPTURA.md), registrando seletor, volume/tone, níveis e firmware.
4. Verificar caminho de reamp para comparações repetíveis.

A fase 1 foi preparada, mas ainda não está encerrada. Este material não altera presets no aplicativo nem escreve no pedal.
