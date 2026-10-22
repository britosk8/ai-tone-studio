# V1.2.0 — envio e comparação de timbre

## Teste no Android

Instale `releases/ai-tone-studio-v1.2.0.apk` sobre a versão anterior. Mantenha o backend atualizado para 1.2.0 e acessível pela URL configurada no app.

1. Envie um preset MK300. Após confirmar a leitura de retorno, aparece **Preset <nome enviado> enviado com sucesso** e o aplicativo volta ao início. O nome é o efetivamente enviado, limitado a 19 caracteres ASCII. Uma falha mostra o erro e mantém a tela de envio; não repete automaticamente a escrita.
2. Abra uma análise na biblioteca e toque **Gravar e comparar meu timbre**.
3. Escolha Base ou Solo, correspondente ao preset aplicado na pedaleira. Trocar o preset descarta a captura anterior para evitar comparar o som de outro preset.
4. Conecte o USB/OTG, atualize as entradas e escolha a entrada de áudio USB. Confira no pedal que a USB transmite o som processado, com os efeitos aplicados. O app não identifica automaticamente sinal DI seco.
5. Escolha 5, 10, 20 ou 30 segundos e grave tocando a mesma passagem musical do áudio original, sem reproduzir a música junto. Também pode parar manualmente; o áudio precisa conter ao menos 3 segundos.
6. Selecione o áudio original e informe o início do trecho em segundos. A comparação usa um trecho de duração igual à captura. Marque guitarra isolada somente se o arquivo realmente contiver apenas a guitarra. Presets antigos exigem selecionar novamente o original, pois o servidor não guarda os arquivos de áudio.
7. Toque **Analisar e sugerir ajustes**, revise as sugestões e, se desejar, **Salvar ajustes sugeridos no aplicativo**. Depois use **Enviar preset ajustado ao pedal** e repita a gravação.

Sem arquivo original, análises novas podem usar o perfil geral salvo. Isso é menos útil que comparar a mesma passagem. Se a entrada USB não aparecer, não há troca automática para o microfone: confira cabo/modo de áudio e atualize a lista. É possível escolher explicitamente microfone ou importar uma gravação curta.

## Método e limites

A comparação mede potência espectral relativa em graves (80–250 Hz), médios (250–2500 Hz) e agudos (2500–8000 Hz), além de dinâmica e saturação. Diferenças de ao menos 3 dB podem sugerir alteração pequena, aproximadamente 3% da escala de Bass/Middle/Treble do amplificador habilitado. Valores são limitados ao mínimo, máximo e passo do catálogo e a aplicação rejeita parâmetros/modelos alterados desde a comparação.

Trata-se de DSP heurístico, não um modelo de IA treinado para matching. A confiança é baixa. Mixagem, outros instrumentos, execução, guitarra, captadores e rota de áudio influenciam a medição. Não há porcentagem de similaridade, identificação automática de amplificador ou ajuste automático de ganho, delay/reverb. Clipping significativo impede sugestões e solicita reduzir o nível da entrada. Não existe garantia de convergência ao timbre original.

Salvar sugestões atualiza somente o preset selecionado na biblioteca; aplicar no pedal exige novo envio com backup e confirmação. A comparação envia os áudios ao backend configurado; os arquivos temporários são excluídos ao concluir/falhar. WAVs capturados ficam temporariamente no cache Android e são removidos ao substituir/sair. A captura é cancelada ao sair do aplicativo.

## Implementação e validação

`POST /api/v1/compare-tone` recebe gravação (até 10 MB), preset atual e referência opcional (até 50 MB), início do trecho e tipo de entrada/referência. Analisa em thread, preservando as demais rotas. Análises novas salvam o perfil numérico em SQLite para reutilização.

A captura nativa usa AudioRecord PCM16 em 44.1/48 kHz, seleção explícita de AudioDeviceInfo e conferência do dispositivo efetivamente roteado. Desconexão ou rota diferente interrompem a captura. Desabilita AGC, redução de ruído e cancelamento de eco quando disponíveis. A permissão de gravação é necessária também para USB.

Fontes: [Android AudioRecord](https://developer.android.com/reference/android/media/AudioRecord), [Android AudioRouting](https://developer.android.com/reference/android/media/AudioRouting), [librosa spectral_flatness](https://librosa.org/doc/0.10.2/generated/librosa.feature.spectral_flatness.html).

Validação: 65 testes backend e 27 testes Flutter, incluindo envio com sucesso/erro, comparação multipart, invariância ao volume de captura, clipping, catálogo/limites, seleção USB sem fallback e persistência dos ajustes. Análise estática e compilação Android release. Os testes de canais nativos usam mocks; a captura USB real precisa ser testada no equipamento do usuário. O usuário já confirmou o envio USB da versão anterior.
