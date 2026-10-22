# Preparação da fase 2 — separação das guitarras por IA

## Piloto local

Foram preparados dois candidatos principais por música (base e solo/destaque), com metadados rastreáveis e separação experimental por Demucs `htdemucs_6s`. Consulte `resultados_piloto.json` para a quantidade efetivamente concluída, tempo de CPU e hashes de cada arquivo. Abra **OUVIR_SEPARACAO.html** para ouvir o original recortado e as seis saídas.

Cada diretório em `piloto_htdemucs_6s/` contém:

- `guitar.wav`: guitarras estimadas, podendo conter base, solo e camadas juntas.
- `vocals.wav`: voz estimada.
- `bass.wav`: baixo estimado.
- `drums.wav`: bateria estimada.
- `piano.wav`: piano estimado; pode conter vazamentos mesmo onde não houver piano.
- `other.wav`: demais elementos estimados.
- `resultado.json`: modelo, parâmetros, tempos, hashes, origem e limitações.

Os stems são WAV float32 estéreo em 44,1 kHz, sem normalização automática de volume. Ouça em volume confortável: cada fonte pode ter nível diferente da mixagem.

## O que este piloto demonstra

O ambiente isolado consegue carregar um modelo de IA, processar os recortes reais do repertório e produzir uma saída dedicada de guitarra, além das outras cinco fontes. Isso é separação neural real, diferente da geração heurística de presets do aplicativo atual.

**Ainda não é separação específica de guitarra base e guitarra solo.** Os nomes dos diretórios indicam o papel PROPOSTO do trecho de entrada, não a identidade garantida do stem de saída. A separação pode remover harmônicos, misturar guitarras ou produzir artefatos. É necessário ouvir antes de adotar como referência de timbre.

`reconstruction_error_relative_rms` mede somente a diferença entre a soma das saídas e a entrada. Não é SDR, qualidade auditiva ou percentual de precisão. Não existem stems de estúdio verdadeiros destes arquivos para calcular uma referência objetiva de separação.

## Fila e comparação futura

`fila_separacao.json` contém as 24 entradas candidatas, com hash, origem, início/fim e prioridade. Os 12 candidatos principais são o piloto inicial; alternativas permanecem disponíveis para troca após revisão. Não processamos automaticamente as seis músicas completas para evitar custo antes de validar a qualidade dos trechos.

Para avaliar outro separador, preserve a mesma entrada e registre:

1. Fornecedor/modelo, versão ou revisão, configurações, dispositivo e tempo.
2. Hash do WAV de entrada e hash de cada saída.
3. Se a saída é guitarra geral ou base/solo especificamente.
4. Parecer auditivo: vazamento de voz/baixo/bateria, perda de harmônicos, caudas, modulação artificial e estabilidade ao longo do trecho.
5. Preferência A/B com volume de escuta equivalente; sem percentual de fidelidade inventado.

A Music AI documenta módulos com base/solo separados. Esse é um candidato de comparação, não uma dependência instalada: não houve contratação, envio de áudio ou chamada externa. Fonte: [Musical Stems Advanced](https://music.ai/modules/stem-separation/musical-stems-advanced/). Também é possível avaliar pesos abertos especializados, desde que a saída e as licenças sejam verificadas.

## Próximas decisões da fase 2

- Aprovar ou trocar os trechos com vocês, usando a revisão da fase 1.
- Avaliar as guitarras do piloto, sem assumir que a melhor voz separada implica melhor timbre de guitarra.
- Comparar a referência Demucs com uma solução que entregue base/solo explicitamente.
- Só depois escolher modelo/provedor e dimensionar processamento de músicas completas.

O backend/app permanece sem essa dependência: não foi alterado, não usa os stems automaticamente e não oferece ainda um fluxo integrado de separação. Os presets atuais e seu envio ao pedal continuam na V1.2.2.
