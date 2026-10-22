# Teste da V1.0.1 — 11/10/2026

## Atualizar

1. Instale o APK V1.0.1 por cima do aplicativo atual para preservar a biblioteca.
2. Mantenha o backend atualizado em execução no computador, porta 8000.
3. No telefone, abra Ajustes e teste o endereço do backend. Confirme a versão 1.0.1.

## Roteiro no telefone

1. Importe uma música com sinal audível, pelo menos um segundo e até 50 MB.
2. Informe nome/artista e selecione MK20 para base e MK300 para solo.
3. Inicie a análise. O progresso informa etapas; não é uma estimativa linear de tempo restante.
4. Confira os dois presets, modelos e parâmetros. A MK20 deve incluir AI Gate com Gate/Bias; o AMP deve incluir Gain, Level e Pres.
5. Edite um parâmetro e altere o estado de um bloco. Toque em Salvar e confira a alteração na tela anterior.
6. Feche/reabra o app. Confira que o preset editado e a URL do backend foram mantidos.
7. Abra Guia manual e confira os valores editados. Compartilhe o texto.
8. Toque em JSON e salve/compartilhe o arquivo. Confira os mesmos valores.
9. Desligue o backend ou a rede e confira que presets já salvos, edição e exportação local continuam funcionando.
10. Tente analisar um áudio silencioso: o app deve apresentar uma falha legível. Reinicie o backend durante uma análise e confira que o processamento interrompido é reportado.

Presets antigos sem informação de escala podem ser consultados/exportados, mas os controles de parâmetros ficam desabilitados. Reanalise o áudio para receber os metadados atuais. Atualizar não recupera presets que a versão anterior já perdeu.

## Limites da validação desta entrega

Os testes automatizados verificam o fluxo técnico com áudio de teste codificado em MP3, persistência e edição Flutter. Não demonstram fidelidade do timbre a uma música comercial. Nenhum telefone/emulador estava conectado por ADB; a instalação e as ações de compartilhamento no Android precisam do teste do usuário. Não houve teste físico MK20/MK300, execução de Demucs, Docker ou implantação AWS.

BLE/USB continuam indisponíveis. Use o guia para configurar manualmente e avaliar o som com sua guitarra e amplificação.

## Resultado automatizado

- Backend: 55 testes passaram (incluindo upload/análise de MP3 e recuperação dos resultados).
- Flutter: 10 testes passaram (incluindo fluxo de edição/salvamento).
- Flutter analyze: sem apontamentos.
- Build release: APK gerado, versão 1.0.1, build 2.
- Backend local: health check confirmou versão 1.0.1.

APK para instalar: `releases/ai-tone-studio-v1.0.1.apk`. O arquivo `.sha256` ao lado registra o hash da entrega. Instalação em telefone e avaliação musical ficam para o roteiro acima. Há avisos de depreciação no pytest de bibliotecas/uso de datas; não houve falha de teste.
