# V1.2.1 — referência, geração e confiança

O objetivo é orientar a aproximação do timbre usando uma referência mais específica e evitar decisões automáticas que alteravam o áudio sem evidência. Esta versão não promete fidelidade validada ao original: os métodos permanecem heurísticos e não identificam amplificador, cabinet ou cadeia de efeitos usados no disco.

## O que significavam os selos do print

A música completa recebia confiança baixa para quase todos os blocos, independentemente da qualidade real da estimativa. O gate recebia média por ser uma configuração padrão do gerador, não por ter sido detectado na gravação. Além disso, o solo escolhia uma família fixa de lead e ligava drive independentemente do caráter limpo do áudio. A variação das notas era usada como indicativo de chorus, confundindo música com modulação.

Agora o gate é marcado como sugestão especulativa, com motivo explícito. O solo usa a família de amplificador/cabinet correspondente ao caráter estimado; drive fica desligado em referências limpas. O ganho mínimo do amp no solo não é aumentado apenas pelo papel musical. A detecção automática de chorus pela variação de notas foi removida; modulação de baixa confiança, caso fornecida ao compilador, fica desligada.

## Como testar com música completa

1. Instale `releases/ai-tone-studio-v1.2.1.apk` por cima da versão atual e utilize backend 1.2.1.
2. Importe novamente a música. Mantenha **Música com outros instrumentos**.
3. Se desejar, ative **Analisar apenas um trecho** e informe o início (0–7200 segundos) e a duração (3–120 segundos). Prefira uma passagem com a guitarra em destaque e pouco acompanhamento. O arquivo inteiro é enviado, mas apenas o trecho escolhido alimenta a análise e a geração.
4. Base e solo são aproximações geradas a partir desse mesmo trecho, não separações automáticas de partes musicais. Para referências distintas, crie análises separadas para trechos de base e solo.
5. Toque no selo de confiança para consultar a justificativa de cada efeito. Blocos desligados agora aparecem como **Desligado**.
6. Envie o preset, grave via USB/OTG a mesma passagem e use **Gravar e comparar meu timbre**. Selecione o arquivo original e o mesmo início em segundos para a comparação. Revise os ajustes, salve no app e reenvie. A comparação ainda propõe apenas pequenos ajustes de EQ; não otimiza amp, cabinet ou efeitos automaticamente.

Presets salvos anteriormente permanecem com os parâmetros e níveis antigos. A reanálise gera novos registros e aplica a política atual; não altera automaticamente o pedal. A escolha de trecho é opcional: o fluxo da música completa continua disponível.

## Política de confiança

Os níveis são qualitativos; não são percentuais calibrados de acerto ou semelhança. Nenhum caminho novo produz automaticamente confiança alta.

- **Mixagem ou stem `other`:** confiança geral/de ganho baixa, pois a referência contém múltiplos instrumentos.
- **Guitarra já isolada, declarada pelo usuário:** geral/de ganho podem ser médios quando há pelo menos 10 segundos, RMS ≥ 0,001 e menos de 0,5% das amostras em amplitude ≥ 0,99. Estes são critérios de qualidade de entrada, não uma validação estatística da fidelidade. A declaração de guitarra isolada não é verificada automaticamente.
- **Curto, baixo ou com clipping:** não recebe confiança média por essa política.
- **Reverb, delay e compressão:** continuam baixos devido às limitações dos métodos. Cabinet não é identificado e permanece baixo. Gate é configuração sugerida, portanto especulativo.
- **Chorus:** não é inferido da simples mudança de notas.

Apenas marcar música completa como isolada pode produzir uma confiança indevida: escolha isolada somente se o arquivo realmente contiver apenas guitarra. Não existe ganho demonstrado de similaridade por mudar o rótulo.

O Demucs padrão `htdemucs` separa bateria, baixo, voz e `other`, que não comprova guitarra isolada. A documentação descreve um modelo experimental de seis fontes com guitarra dedicada; não foi instalado ou ativado nesta entrega. Fonte: [documentação Demucs](https://github.com/facebookresearch/demucs). A seleção do trecho usa offset/duration do [librosa.load](https://librosa.org/doc/0.10.2/generated/librosa.load.html).

## Validação

75 testes backend e 29 Flutter passaram; análise estática sem problemas e compilação release Android. Inclui regressões de solo limpo, modulação incerta desligada, variação musical sem falso chorus, mix/stem `other` sem confiança média, qualidade mínima para referência isolada, recorte real e metadados de upload inválidos, e diálogo explicando a confiança. São testes funcionais com sinais sintéticos, não uma avaliação auditiva de proximidade ao disco. Essa avaliação requer o áudio e a gravação real do equipamento do usuário.
