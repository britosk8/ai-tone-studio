# Revisão técnica e lógica — AI Tone Studio V1.6.1

Documentação do comportamento atual, baseada no commit `b5f036568a965cfe791ff2272480ea98352efe88` da branch `develop`, em 08/11/2026. Não modifica app, serviço, biblioteca nem presets.

## Por onde começar

1. [PDF para leitura](DOCUMENTACAO_TECNICA_E_LOGICA.pdf) — 14 páginas, arquitetura, geração, fórmulas atuais, comparação, transporte e proposta de evolução.
2. [HTML offline](DOCUMENTACAO_TECNICA_E_LOGICA.html) — mesmo conteúdo, com diagramas SVG incorporados; abre no navegador sem serviço externo.
3. [Markdown editável](DOCUMENTACAO_TECNICA_E_LOGICA.md) — fonte principal do texto.
4. [Diagramas editáveis no diagrams.net](diagramas/arquitetura-e-fluxos.drawio) — três páginas: arquitetura, geração e comparação/envio. As fontes Mermaid `.mmd` e os SVGs estão em `diagramas/`.

Para avaliar o motor, priorize as seções 4 (regras), 5 (referência versus geração), 7 (limites da comparação), 12 (Infest) e 13 (evolução proposta).

## Evidências auxiliares

- [Inventário de API](inventario-api.json): 38 operações, incluindo a raiz; método, caminho e respostas declaradas.
- [Contrato OpenAPI](openapi-v1.6.1.json): schemas e parâmetros efetivamente expostos pela aplicação.
- [Inventário dos catálogos](inventario-catalogos.json): contagens por bloco, metadados originais, hashes e equivalência dos assets Android.
- [Mapa de fontes](mapa-fontes.json): 96 arquivos Python/Dart/Kotlin, hashes e localização de símbolos.

O inventário registra a existência da rota de regeneração legada; o texto esclarece que ela retorna 501. A pesquisa web anterior é uma proposta de enriquecimento, não conteúdo já incorporado ao motor.

## Reprodução dos artefatos

`gerar_documentacao.py` utiliza a biblioteca Python Markdown para renderizar o texto, inspeciona OpenAPI sem iniciar o servidor e gera diagramas a partir de uma estrutura comum. Ele escreve somente nesta pasta. A dependência de apresentação foi instalada isoladamente em `/tmp/ai-tone-doc-tools`, sem alteração de `requirements.txt` ou do ambiente do app.

Executar a partir da raiz do repositório:

```bash
PYTHONPATH=/tmp/ai-tone-doc-tools backend/.venv/bin/python docs/architecture/revisao-v1.6.1/gerar_documentacao.py
```

O PDF pode ser reexportado pelo comando Imprimir do navegador, tamanho A4. A entrega usa Chrome headless, sem cabeçalhos/rodapés automáticos. Para regeneração por linha de comando, fornecer o caminho absoluto do HTML e o destino do PDF a `google-chrome --headless --print-to-pdf=... --no-pdf-header-footer`.

A geração dos snapshots não executa análise, escrita MIDI, limpeza de dados ou requisições às rotas. A importação de `app.main` é usada apenas para obter `app.openapi()`.

## Verificação desta documentação

- Contratos comparados com OpenAPI; mapa de fontes conferido por SHA-256.
- JSON e XML de diagramas validados; contagem de três páginas editáveis.
- Imagens SVG do Markdown existentes e incorporadas no HTML.
- PDF com texto extraível e revisão visual da página de arquitetura.
- Somente arquivos de documentação alterados. Os 172 testes backend e 107 Flutter citados no documento pertencem à entrega V1.6.1; não foram executados novamente para uma mudança apenas documental.
