# Repertório — fase 1

Espaço de trabalho para avaliar as seis músicas da banda e comparar os presets atuais. Esta pasta não é lida automaticamente pelo aplicativo ou pelo backend.

## Onde colocar as músicas

Copie cada M4A completo para uma pasta `original/`, mantendo o nome original do arquivo:

- `01/original/` — primeira música
- `02/original/` — segunda música
- `03/original/` — terceira música
- `04/original/` — quarta música
- `05/original/` — quinta música
- `06/original/` — sexta música

A ordem é livre. Não é necessário converter, recortar ou renomear os M4A. Coloque uma música por pasta, usando cópias para preservar seus arquivos de origem.

## Organização de cada música

| Local | Conteúdo |
| --- | --- |
| `original/` | M4A completo usado como referência; preservar sem edição. |
| `trechos/` | Cópias recortadas e futuras referências isoladas de base e solo, quando produzidas. |
| `presets/` | Exportações dos presets atuais e das versões avaliadas; evitar sobrescrever a referência inicial. |
| `gravacoes_pedal/` | Capturas da pedaleira para comparação, identificando preset e tentativa. |
| `FICHA.md` | Música, artista, versão, equipamento, trechos e observações da avaliação. |

Exemplos de nomes futuros: `base_01m15s_01m35s.wav`, `solo_preset_atual_tentativa_01.wav`, `solo_preset_atual.json`. Os nomes são apenas uma convenção; não há processamento automático associado a eles.

## Próximo passo

Depois de copiar os seis arquivos, informe que as músicas estão disponíveis. Preencha as fichas se já souber as informações; os tempos dos trechos podem ficar em branco para identificarmos juntos. A primeira avaliação usará os presets atuais como referência, sem modificar o aplicativo.

Os diretórios de áudio, capturas e presets exportados estão ignorados pelo `.gitignore` de `repertorio/`, caso o projeto passe a usar Git. Isso não é um backup: mantenha uma cópia dos originais em outro local.

## Referências preparadas em 20/10/2026

- [Plano e resultados da preparação](PLANO_REFERENCIAS.md).
- [Abrir revisão com áudio](REVISAO_REFERENCIAS.html): quatro candidatos de 20 segundos por música, ainda pendentes de escuta e confirmação.
- [Índice dos recortes](REFERENCIAS.csv): IDs, tempos, papel proposto e caminhos.
- [Contexto e roteiro de captura](CONTEXTO_E_CAPTURA.md): equipamento confirmado, o que gravar e os critérios A/B.
- [Preparação da separação por IA](../fase_2/README.md) e [ouvir piloto](../fase_2/OUVIR_SEPARACAO.html).
- Manifesto técnico, versões e validações: `../laboratorio/`.

Os recortes ativos são mixagens, não guitarras já isoladas. Os tempos e papéis são candidatos automáticos; confirme ouvindo. Duas passagens ambíguas da primeira triagem foram arquivadas em `trechos/triagem_inicial_descartada/` e não integram o índice ativo. A fase 1 ainda depende das gravações reais da pedaleira e do teste de repetibilidade/reamp.
