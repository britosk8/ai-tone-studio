# MK20: primeiro envio completo pelo app — V1.5.5

A leitura real de `PAPA INFEST` no slot 76 foi recebida, e a restauração do teste de nome foi confirmada. O app agora prepara uma imagem MK20 de 412 bytes, com o perfil próprio de controles, backup integral e leitura de retorno. O primeiro teste completo está restrito ao **slot 150**; o slot 76 não é destino permitido por esse serviço.

## Testar

1. Instalar `releases/ai-tone-studio-v1.5.5-develop.apk` sobre a instalação existente. Manter os dados do app e o backend atualizado.
2. Para uma música já analisada, abrir seus presets → **Timbres ao longo da música**, detectar/reabrir os estados da guitarra já separada e gerar a base ou solo selecionando **MK20**. Essa variante usa o catálogo 0.4.0. A identidade agora inclui a versão MK20 para não reutilizar um preset antigo com índices incompatíveis. A análise anterior não é apagada e o stem persistido é reutilizado.
3. Abrir **Enviar para pedaleira**, selecionar a variante MK20, definir nome ASCII de até 16 caracteres, conectar USB/OTG e fechar o M-EFCS.
4. Buscar a pedaleira, confirmar MK20 e **Conectar e conferir leitura**.
5. **Ler destino e salvar backup**. O original do slot 150 é salvo e relido do armazenamento local antes de qualquer escrita. Compartilhar uma cópia do backup se desejado.
6. **Revisar e enviar preset** → confirmar a substituição do slot 150. Aguardar sem desconectar. Sucesso exige ACK da escrita, ACK do commit e leitura final exatamente igual aos 412 bytes previstos. O app mostra `Preset <nome> enviado com sucesso` e volta à inicial; erro fica na tela.
7. Selecionar o slot 150 no próprio pedal para ouvir: o envio não troca automaticamente o preset ativo. Conferir os blocos/modelos e tocar a mesma passagem da música. Comparar/gravar pelo fluxo existente do app.

Para voltar ao original, reabrir a tela de envio com um preset MK20, conectar, e usar **Restaurar backup MK20 do slot 150**, sem preparar outro backup. Funciona após reiniciar o app: `mk20-latest-full.json` aponta para o backup integral mais recente. A restauração só escreve quando a leitura atual corresponde exatamente à imagem enviada; se já for o original, confirma por leitura sem escrever. Uma alteração inesperada cancela a operação.

Os backups do teste anterior de nome continuam separados em `mk20_name_pilot/`. Não são convertidos nem apagados.

## Modelos, controles e evidências

O catálogo MK20 0.4.0 contém o subconjunto revisado do recurso AM4 do editor oficial: 40 drives, 90 amplificadores de guitarra e 100 gabinetes. Os nomes vêm dos cabeçalhos do binário próprio MK20, e o ID é seu prefixo numérico menos um. O perfil inclui AI Gate, Guitar EQ 6, Chorus, Clean (delay), Room (reverb) e VOL. FX e algoritmos temporais adicionais ficam fora do envio até revisão. Os valores iniciais do app não são apresentados como defaults de reset do firmware.

A análise estática confirmou que a MK20 chama explicitamente os construtores compartilhados de controles AMP/DS, gabinete, EQ e efeitos temporais. Isso permite reutilizar definições de algoritmos documentados, **não** os nomes/índices de AMP/CAB da MK300. Fontes, hashes e endereços estão em [mk20-editor-evidence.json](device-protocols/mk20-editor-evidence.json). O script `tools/build_mk20_catalog.py` reproduz os catálogos Android/backend a partir do APK com hash revisado e dos metadados históricos do projeto; não executa binários do fornecedor nem acessa hardware.

Layout: nome 0..19; volume 24 (u16); BPM 26 (u16); pan 28 (i16); cadeia 30..39; estados 40..49; modelos 50..59; parâmetros 60..299 (10 × 12 i16). Bytes 300..411 são preservados do destino, assim como campos não alterados explicitamente. Todos os controles conhecidos de cada bloco selecionado são inicializados; knobs não usados do bloco são zerados. Blocos ausentes ficam desligados. AMP e CAB ligados são obrigatórios. Limites são conferidos contra o catálogo embarcado, não contra limites enviados pelo preset.

Conversões físicas revisadas:

| Controle | App | Imagem |
|---|---|---|
| AMP/DS/Gate | escala do pedal | inteiro direto |
| CAB Low Cut | Hz (20–300) | inteiro direto |
| CAB High Cut | Hz (5000–18000, passo 100) | Hz ÷ 100 |
| EQ | dB (-24–24, passo 0,5) | dB × 2 |

Na captura real de Infest: DS 21 (`22TS-9`), AMP 69 (`70OD2_meas`), CAB 53 (`54MbSOSS4t412`). Gate 40/Bias 50; AMP Gain 56 e **Middle 49**, gabinete raw `[80,80,75]`; EQ raw `[4,0,-3,2,5,1]`, ou `[+2.0, 0.0, -1.5, +1.0, +2.5, +0.5] dB`. Os controles armazenados prevalecem sobre a referência lembrada anteriormente; não se corrige o preset real para fazê-lo concordar com aquela tabela. Volume global 60; VOL do bloco 61, porém desligado.

O comando de banco MK20 é classe 9, comando `0xD21`, offset `149×412=61388`, espaço 0. O commit usa o envelope comum (espaço 15). Não se chama `Mk300Protocol.bankWrite` nem se grava buffer ativo/global. O envio é de tentativa única: flags persistidas antes de enviar impedem repetir a mesma escrita após timeout ou reinício. Somente leituras são repetidas. O commit não é enviado sem ACK da escrita.

## Persistência e limites

Backups em `pedal_backups/mk20-slot-150-*.json`; relatórios em `mk20-transfer-*.json`. Os relatórios são enviados a `POST /api/v1/mk20/transfers`, que reconstitui a imagem pelo catálogo e verifica preflight, ordem dos comandos, ACKs e leitura final. Ficam no SQLite como `mk20_transfer`, consultáveis por lista e ID. Falha de rede mantém o relatório no celular para nova sincronização na próxima conexão; nunca repete comandos ao pedal. A sincronização não transforma uma falha de envio em sucesso nem invalida uma leitura física já confirmada.

O catálogo descreve recursos AM4 de fábrica. Confirmar no diálogo que os slots de modelos usados não foram substituídos por recursos personalizados. Não habilitamos BLE MK20 nem ampliamos a escrita para outros slots. A validação física completa e a escuta deste novo fluxo ainda dependem do teste do usuário. O gerador continua derivando presets da música, usando separação por IA e regras de timbre; a leitura de Infest é evidência de compatibilidade, não substituto da análise nem prova de fidelidade sonora universal.

## Verificações desta entrega

147 testes do backend e 92 testes Flutter passaram; `flutter analyze` sem problemas. Casos cobertos: índices/controles conhecidos do Infest, escala do EQ e do gabinete, preservação de campos, destino 76 bloqueado, ausência de ACK, leitura divergente, backup alterado, recuperação após reinício, restauração exata e envio/cancelamento pela interface de 360 px. O relatório sintético produzido pela UI Android também passou pelo endpoint Python, que reconstituiu os mesmos 412 bytes. Esses testes não substituem a confirmação física do envio completo.
