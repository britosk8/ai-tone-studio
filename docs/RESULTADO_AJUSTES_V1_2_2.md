# V1.2.2 — resultado da comparação, atualização e envio

O usuário relatou captura de 10 segundos por USB-Audio MK300 e análise concluída, mas o resultado ficava abaixo do formulário e, com clipping, não mostrava um caminho claro para continuar. Agora a análise abre automaticamente **Resultado e ajustes**, no início de uma tela dedicada.

## Estados do resultado

- **Ajustes recomendados para o preset:** apresenta o preset escolhido, diferenças de graves/médios/agudos em dB, controles com valores antes/depois e justificativa. As mudanças vêm selecionadas e podem ser desmarcadas. **Atualizar preset e seguir para envio** salva somente as mudanças aceitas no mesmo registro da biblioteca, preserva seu ID e a outra guitarra (Base ou Solo), e abre a transferência desse preset. Também há a opção de apenas salvar no aplicativo.
- **EQ sem ajustes recomendados:** diferenças das três bandas abaixo do limiar de 3 dB; o app diz explicitamente que não recomenda mudança de EQ. Não afirma que o timbre inteiro é idêntico ou que ganho/efeitos estão corretos. Permite enviar o preset atual sem alterações ou fazer nova gravação.
- **Há diferenças, mas sem ajuste automático disponível:** há diferenças de EQ, mas o controle está em um limite ou não é ajustável pelo método/catálogo. O resultado explica que requer revisão manual e permite enviar o preset atual sem alterações.
- **Gravação saturada — grave novamente:** é o caso das capturas enviadas pelo usuário. A qualidade `clipped` bloqueia aplicar sugestões e seguir para o envio nessa tela, inclusive se a resposta indevidamente contiver sugestões. Exibe o nível de amostras próximas ao limite, quando informado. Solicita reduzir o nível enviado pela pedaleira à USB ou a entrada da interface e gravar novamente. Reduzir o volume depois da captura não recupera áudio já saturado. Não altera ganho ou Level do preset automaticamente, pois a comparação não identifica a origem da saturação.

Mensagens sobre limitações ficam em uma seção expansível, depois do resultado e das ações. A avaliação é DSP orientativa, sem percentual de semelhança validado. Ajustes automáticos continuam restritos ao EQ do amp; esta mudança organiza e torna aplicável o resultado, sem expandir a identificação de amp/cabinet/ganho/efeitos.

## Teste sugerido

1. Instale `releases/ai-tone-studio-v1.2.2.apk` sobre a versão atual. Os presets existentes permanecem disponíveis; não é necessário reanalisar a música só para usar a nova tela.
2. Abra **Gravar e comparar meu timbre**, selecione o preset aplicado e grave novamente em USB/OTG. Confira o nível enviado à USB caso a captura anterior tenha acusado clipping.
3. Para uma referência mais útil, selecione a música original e o início da mesma passagem tocada. Sem isso, o backend pode comparar com o perfil geral salvo, o que inclui outros instrumentos e trechos.
4. Toque **Analisar e sugerir ajustes**. A nova tela abre automaticamente e mostra a avaliação no topo.
5. Havendo mudanças, revise os valores e toque **Atualizar preset e seguir para envio**. O preset existente é atualizado no aplicativo; ele não é duplicado.
6. Na transferência, confira dispositivo/nome/slot, salve o backup e confirme o envio como antes. A escrita no pedal continua sendo uma ação separada e confirmada, com leitura de retorno.
7. Depois de aplicar no pedal, grave a mesma passagem para avaliar o resultado. Não reaplique sugestões antigas sobre valores já modificados.

Alterações do preset desde a comparação são verificadas antes de salvar: ID, catálogo, modelo, parâmetro original e limites. Se não corresponderem, o app mostra o erro e permanece na revisão. Falha ao persistir a biblioteca restaura o estado em memória e não segue para envio. Nenhum erro provoca escrita automática no pedal.

## Validação

75 testes backend e 34 Flutter passaram, com análise estática e compilação release Android. Inclui abertura automática do resultado após gravação/comparação, atualização persistida no mesmo preset, preservação da outra guitarra, seleção correta de Solo ao continuar para transferência, clipping sem atualização/envio, resultado sem mudanças, rejeição de parâmetro alterado e desmarcação de sugestões. Testes de UI/transporte usam mocks; a captura USB foi relatada pelo usuário, mas a fidelidade sonora e o novo fluxo devem ser conferidos no celular/pedal.
