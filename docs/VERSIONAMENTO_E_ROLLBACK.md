# Versionamento e recuperação

Repositório: https://github.com/britosk8/ai-tone-studio.git

`main` preserva o baseline 56fbfbf. A evolução acontece em `develop`, incluindo os registros posteriores ao baseline e o piloto automático do app. Publicar em `develop` não atualiza a `main`; uma integração futura deve ser revisada antes de merge.

O baseline inicial contém fontes Android/backend, catálogos, documentação, scripts, metadados do laboratório e presets JSON. Áudios, modelos de IA, ambientes virtuais, caches, banco SQLite, configurações locais, credenciais e APKs ficam fora do Git. Os arquivos locais não são apagados por essa exclusão.

## Pontos de recuperação

O marco `baseline-v1.2.3-mk300-r1` identifica o estado anterior à evolução do motor calibrado: aplicativo V1.2.3 e piloto R1 com relato de distorções ruins. Não representa aprovação sonora do preset.

Para acompanhar alterações:

```bash
git status
git log --oneline --decorate
git diff
```

Para consultar ou compilar o baseline sem alterar a pasta de trabalho atual, crie outro checkout:

```bash
git worktree add --detach ../ai-tone-studio-baseline baseline-v1.2.3-mk300-r1
```

Esse checkout exige restaurar dependências e configurações locais. Os áudios e pesos não estarão nele.

Para desfazer um commit publicado preservando o histórico, primeiro deixe o trabalho local salvo e use `git revert <hash-do-commit>`. Avalie o diff e os testes antes de publicar o resultado. Não é necessário reescrever o histórico para recuperar uma versão.

## Backups fora do Git

Manter cópia independente de `backend/data/`, músicas, capturas, pesos e APKs desejados. Git recupera código e presets versionados; não restaura a biblioteca SQLite, os dados salvos no celular nem slots gravados na pedaleira. Preservar o backup do slot antes de cada envio continua necessário.

Desde a V1.3.4, `backend/data/recordings/` também contém capturas da guitarra enviadas pelo app. Preservar essa pasta junto com o SQLite, ou todo o diretório configurado em `TONE_DATA_DIR`. As gravações não são incluídas no Git.

Os presets R1 e os registros de calibração ficam versionados para permitir comparação entre rodadas. Cada evolução deve registrar código, parâmetros, motivo da mudança e resultado observado antes da expansão para outras músicas.

Na V1.4.0, incluir também `generation_inputs/` e `separations/` no backup de dados. O ponto imediatamente anterior à evolução do motor é o commit `2f2025c` (V1.3.4). A `main` e o baseline inicial permanecem preservados.

Antes da V1.4.2: commit `5bbb726` (Android 1.4.1/API 1.4.0). A V1.4.2 acrescenta seleções de referências e jobs idempotentes no SQLite, além de recortes persistidos em `separations/`; manter backup integral de dados. Reverter código não deve apagar capturas, instrumentos ou seleções já salvas.

Antes da V1.5.0: commit `e95ffae` (Android/API 1.4.2 com mensagem de referência silenciosa corrigida). A V1.5.0 acrescenta estados, pesquisa e variantes em registros SQLite, sem apagar os pares anteriores. Recortes e referências exigem o mesmo backup integral de dados; detalhes em [estados sonoros e pesquisa](TIMBRES_E_PESQUISA_V1_5_0.md).

Antes da V1.5.1: `8b9fb5d` (Android/API 1.5.0). A V1.5.1 adiciona diagnóstico de leitura MK20, com arquivos privados do app e registros `mk20_diagnostic` no SQLite. Não altera imagens no pedal nem migra presets. [Roteiro do primeiro teste](TESTE_MK20_V1_5_1.md).

Antes da V1.5.2: `74373a0` (Android/API 1.5.1). A correção reconhece a resposta real de leitura MK20 e reinterpreta os relatórios antigos sem alterar sua captura. Nenhuma escrita no pedal foi habilitada.

Antes da V1.5.3: `16b8e74` (Android/API 1.5.2). A V1.5.3 acrescenta piloto de nome MK20 no slot 150, com backup e restauração; relatórios em `mk20_name_pilot`. Rollback de código não desfaz gravação no pedal. [Roteiro e recuperação](TESTE_ESCRITA_MK20_V1_5_3.md).
