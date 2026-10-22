# Preset do pedal como referência — Android 1.3.2+11

Recurso auxiliar, implementado em `develop`. O objetivo principal permanece: enviar música → analisar áudio → gerar presets → testar e aproximar o timbre. Importar um preset da pedaleira não é requisito para gerar, não substitui o áudio original e não transforma este piloto em um catálogo de presets prontos.

## Uso

1. Atualizar o APK por cima da versão existente, preservando a biblioteca.
2. Abrir os resultados de uma música já analisada, com ao menos um preset MK300.
3. Tocar **Importar preset do pedal e comparar**, abaixo das ações de gravação/exportação.
4. Selecionar base ou solo, conectar a MK300 por USB/OTG e fechar o M-EFCS.
5. Buscar USB, selecionar o dispositivo, confirmar MK300 e informar o slot de origem (1–160).
6. Tocar **Importar preset do pedal**. O app verifica o layout, lê o slot salvo e armazena uma referência local. O app mostra uma mensagem de sucesso e volta ao topo com o resumo da comparação. Expanda **Ver modelos e controles** para consultar as diferenças.

É leitura de um slot salvo, não do estado de edição não salvo. Não muda o preset ativo, não envia alterações, não grava flash e não emite COMMIT. Funciona offline depois de a análise estar na biblioteca. Nesta versão, a importação do hardware é pela MK300 USB/OTG; o bloqueio de escrita MK20 e o transporte de envio existente não mudam.

## Comparação

O relatório mostra cadeias ativas, volume/panorama, modelos, estados ligados/desligados e valores dos controles. Blocos desligados nos dois lados não contribuem com diferenças de knobs irrelevantes. Valores são exibidos como lidos, sem inventar conversões de Hz, dB ou escalas fracionárias. Modelos diferentes podem ter valores iguais e respostas sonoras diferentes. A contagem de diferenças não é percentual de fidelidade nem critério automático de preferência.

Os nomes dos modelos são os do catálogo embarcado. Caso um slot de modelo ou gabinete tenha recebido arquivo de terceiro, o nome canônico não identifica seu conteúdo real. Não há leitura dos pesos NAM/arquivos IR, identificação de firmware, aquisição de áudio nem importação de ajustes globais nesta operação.

Para avaliar o som, o botão **Gravar e comparar com a música** abre o fluxo de gravação/análise já existente. O novo relatório não treina o motor, não altera automaticamente Gain/EQ/modelos e não promete uma métrica perceptiva que ainda não foi validada. A captura do preset conhecido fornece uma referência rastreável para a evolução do motor.

## Persistência e integridade

Uma referência por ID de análise e função base/solo em SharedPreferences, chave `pedal_reference_v1:[pairId,role]`. Reimportar atualiza essa referência, sem acumular análises ou candidatos. Salva nome contido na imagem, slot, data UTC, conexão e imagem binária integral de 448 bytes em base64. Nenhuma referência é salva na biblioteca de presets gerados ou usada como nova análise de música.

`Mk300TransferSession.readSlot` exige sessão verificada, valida faixa do slot e layout. Decodificação utiliza a ordem de cadeia capturada, estados por bloco, índices canônicos e int16 little-endian para knobs. Valores negativos são preservados. O snapshot é apenas referência de leitura; não é automaticamente convertido em preset editável/enviável com limites físicos supostamente validados.

Falhas de leitura, formato ou persistência mantêm a tela com mensagem de erro, sem substituir o preset gerado. Uma referência anterior continua disponível se uma nova importação falhar. A referência persistida pode ser consultada novamente sem reconectar a pedaleira.

## Validação da entrega

56 testes Flutter passaram e `flutter analyze` não apontou problemas. Os testes incluem slots 1/160, rejeição de slots/layout inválidos, decodificação de EQ negativo, comparação sem mutação do preset, persistência por análise/função e importações repetidas pela interface USB simulada. Os comandos capturados na importação são somente de leitura (classe 13), sem seleção de preset, escrita ou commit.

Build release concluído: `releases/ai-tone-studio-v1.3.2-develop.apk`, hash SHA-256 adjacente, applicationId `com.aitone.studio`, versionName 1.3.2/versionCode 11. Assinatura igual à instalação anterior, verificada com apksigner. Instalar por cima, sem desinstalar. O teste físico desta nova função na MK300 do usuário permanece pendente; nesta sessão não foi acessado um pedal real.
