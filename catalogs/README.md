# Catálogos MK20 e MK300

Os arquivos são separados por dispositivo, status geral `COMMUNITY`. MK20 permanece em 0.3.0; MK300 usa 0.4.0 com nomes, índices e knobs importados de jpfaria/mvave no commit 7363c896202508c57218fa68fb941d943fa40cd1. A referência foi capturada em V73; V75 ainda depende de teste físico.

| Catálogo | Amplificadores listados | Drives listados | Cabinets selecionados |
|---|---:|---:|---:|
| MK20 | 55 | 13 | 7 |
| MK300 | 120 | 40 | 100 |

As capacidades declaradas (120 amps, 40 drives, 100 cabinets) não equivalem ao número de modelos efetivamente enumerados. A MK300 lista todos os 359 modelos da referência. Os metadados internos que dizem `VERIFIED` registram as alegações/fontes da implementação anterior; não constituem comprovação física nesta entrega.

O loader usa apenas os modelos listados. A MK20 registra gate/compressão em `effect_modules.NS`; a MK300 usa `blocks.GATE` e `blocks.FX`. O compilador atual usa AI Gate na MK20 e não combina um compressor do mesmo módulo. Os parâmetros editáveis incluem as escalas existentes no JSON.

A seleção de amp/cab é uma regra heurística que escolhe um modelo cadastrado compatível com o caráter estimado. Parâmetros sem correspondência conhecida são omitidos, não inventados. Os efeitos indisponíveis no catálogo não são gerados.

A versão 0.4.0 da MK300 substitui aliases antigos pelos nomes/índices capturados; presets 0.3.0 não são enviados automaticamente. Limites genéricos, classificação musical e seleção do modelo continuam heurísticos; o catálogo de referência comprova nomes, posições e alguns defaults, não calibração de timbre ou todos os limites numéricos. Antes de implementar transferência direta, confirmar modelos, escalas, índices e protocolos no firmware de cada equipamento. Não presumir compatibilidade de MK20 com o protocolo MK300.

Fontes registradas nos arquivos: manuais/guia M-VAVE e projeto comunitário `jpfaria/mvave`. A conferência dessas fontes e testes físicos permanecem necessários para elevar o nível de verificação. Um aviso antigo que dizia que o catálogo MK20 estava vazio foi removido por já não corresponder aos arquivos atuais.
