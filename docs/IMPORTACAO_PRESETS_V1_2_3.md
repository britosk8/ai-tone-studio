# V1.2.3 — importação local de presets MK300

A tela inicial inclui **Importar presets MK300 (JSON)** no ícone de arquivo ao lado de Ajustes. Aceita pares exportados no formato `ai-tone-studio`, versão 1, MK300, catálogo 0.4.0, até 1 MB. O par experimental de Infest está em `repertorio/fase_1/01/presets/piloto_r1/Infest_MK300_Piloto_R1.json`.

A importação mostra os nomes de base e solo e pede confirmação para criar uma nova análise. Gera novos IDs para o par e os dois presets, preservando registros existentes. Se cancelar ou o arquivo for inválido, não altera a biblioteca. Não envia comandos ao pedal, não faz upload do arquivo e funciona sem backend.

Valida funções, cadeia, slots, modelos/nomes, parâmetros e limites usando um catálogo incluído no aplicativo, derivado do catálogo MK300 0.4.0. Limites declarados no arquivo são substituídos pelos limites locais; não autorizam valores arbitrários. O catálogo de importação contém os 359 modelos atuais. A transferência mantém a validação adicional e o fluxo de backup/confirmação/leitura de retorno já implementado.

Nesta entrega só se importam pares MK300. O funcionamento anterior de análise/edição/guia MK20 não foi removido. Arquivos nativos do M-EFCS, exportações internas do modelo Python e dumps binários não são o formato aceito.

Os IDs importados são locais; não há perfil de comparação correspondente no servidor. Para comparar uma gravação no app, selecione o arquivo original e seu trecho. Importar uma análise não é o mesmo que reanalisar o áudio.

APK V1.2.3, build 8, mesma identidade e assinatura de teste das versões anteriores. O backend permanece na V1.2.2, sem migração ou alterações de API. Instale o APK por cima para preservar a biblioteca; os APKs anteriores permanecem em releases/.

Validação: testes de importação, limites locais contra limites forjados, novos IDs, persistência sem sobrescrever edições, exportação/reimportação, geração offline de imagem MK300, cancelamento, erro e confirmação pela tela com backend indisponível. Os testes de UI/transporte usam mocks; a avaliação sonora do Piloto R1 ainda depende da guitarra e da MK300 reais.

Resultado da verificação: 75 testes backend + 42 testes Flutter, análise estática sem problemas e compilação Android release. Nenhum teste enviou este Piloto R1 a uma pedaleira real.
