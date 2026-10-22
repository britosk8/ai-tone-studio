# Piloto automático MK300 — Android 1.3.0+9

Implementado em `develop`. `main` e a tag `baseline-v1.2.3-mk300-r1` permanecem no commit 56fbfbf, antes da evolução. O roteiro manual R2 anterior é histórico e foi substituído: o usuário não precisa configurar knobs no pedal/editor nem importar um JSON para esta rodada.

## Fluxo no app

1. Atualizar o APK por cima do instalado, preservando a biblioteca.
2. Na tela inicial, tocar no ícone de laboratório (frasco), **Piloto Infest — MK300**.
3. Selecionar um preset de origem de Infest, com base e solo MK300 e catálogo 0.4.0. A biblioteca já existente serve. Na ausência de análise compatível, analisar a música pelo app, escolhendo MK300 para ambos os papéis.
4. Tocar **Gerar candidatos na biblioteca**. O app monta e valida os três candidatos localmente, sem backend, sem arquivo intermediário e sem escrever no pedal. Salva todos em uma operação; falha de persistência restaura a biblioteca anterior.
5. Tocar **Enviar base para a MK300** no candidato desejado. O fluxo existente continua exigindo leitura, backup do slot e confirmação de substituição. Nenhuma escrita é disparada apenas pela geração.
6. Tocar a passagem base 00:50–01:10 com Konig SSS. Usar gravação/comparação do app após cada teste; selecionar a referência original quando necessário, pois candidatos locais não têm análise associada no backend. Selecionar o início 50 s para comparar a passagem aprovada.

Os candidatos persistem como análises novas na biblioteca, mesmo após voltar ao início ou fechar o app. Cada um contém base nova e cópia do solo anterior com ID novo; o solo não foi regenerado. Não modificar os controles manualmente faz parte do fluxo solicitado. O usuário ainda escolhe candidato/slot e confirma o envio, como antes.

## Busca inicial controlada

| Candidato | AMP | CAB |
|---|---|---|
| A | 98MES_CH2_AMP | 11MESA_412_57 |
| B | 100MES_CH3_AM | 11MESA_412_57 |
| C | 98MES_CH2_AMP | 12MESA_412_EC |

A/B altera apenas AMP; A/C apenas CAB. Identidade de nome/ID/knobs é conferida contra o catálogo canônico do app. Escolha por rótulos é hipótese para escuta: não identifica o equipamento da gravação nem demonstra equivalência ao MK20. Não usa a classificação heurística `crunch` desses amps para prever sua resposta.

Em todos: AI Gate Gate 40/Bias 50; DS 22TS-9 Gain 10/Level 80/Bass 42/Middle 58/Treble 52/Reso 0/Pres 50/Bright 60; AMP Gain 56/Level 60/Bass 58/Middle 50/Treble 60/Reso 35/Pres 58/Bright 45; CAB Level 80. Esses valores são hipóteses iniciais derivadas da referência aprovada pelo usuário na Konig/MK20, sem equivalência acústica dos controles entre aparelhos demonstrada.

## Tratamento explícito das lacunas

- **Cortes CAB:** copiar exatamente os dois valores raw da base de origem para todos os candidatos; não inventar uma conversão para 80 Hz/7,5 kHz. Sem ambos os controles, ou com valor inválido, a geração falha com mensagem. Isso mantém os cortes controlados nesta comparação, mas pode preservar uma configuração inadequada da origem. O resultado precisa ser ouvido.
- **EQ:** desativado nesta primeira rodada. Não arredondar −1,5/+2,5/+0,5 dB nem emitir bytes fracionários sem conhecer a representação real. A fidelidade ao EQ do MK20 fica pendente.
- **Volume:** volume de preset 60 no campo documentado 0x18 e pan central em 0x1c. Não confundir com o bloco VOL: ele fica desligado. A leitura de volta existente verifica a imagem final. Antes desta mudança, esses campos eram herdados do destino; agora presets novos podem declará-los explicitamente. Presets antigos continuam preservando esses campos se não os declararem.
- **Outros efeitos:** somente GATE/DS/AMP/CAB ativos; todos os controles relevantes desses modelos são explícitos. FX, WAH, EQ, MOD, DLY, REV e VOL ficam desligados, independentemente do estado anterior do slot. Campos não documentados e footswitches seguem preservados.

Não é uma nova análise IA da música, treinamento de matching ou otimização perceptiva. É a primeira busca controlada dentro do aplicativo com a referência humana aprovada. Próximas etapas: registrar avaliação dos candidatos no app, validar escalas físicas, calibrar resposta com capturas e somente então automatizar a seleção por similaridade. A análise DSP/comparação anterior permanece disponível e não ganha novas capacidades por esta entrega.

## Rastreabilidade e compatibilidade

Serviço `Mk300Pilot`, tela `Mk300PilotScreen` e rota `/mk300-pilot`. Cada geração usa IDs novos, conserva nome do áudio e registra em `generation_metadata` origem, versão do gerador, candidato, cortes utilizados e pendências. Metadados e os novos campos opcionais de volume/pan sobrevivem à persistência, exportação/importação e `copyWith`.

O protocolo, leitura/backup/commit/readback e bloqueio da MK20 não mudam. Backend e catálogo permanecem nas versões anteriores. O APK não instala bibliotecas de IA adicionais nem envia músicas para serviços externos.

Os testes verificam geração e isolamento das variantes, origem inalterada, IDs novos, persistência, rejeição de cortes inválidos, imagem binária, campos de volume/pan, desligamento de blocos herdados e navegação até o envio. Não substituem validação sonora na MK300 real.

Validação executada: `flutter analyze` sem problemas; 47 testes Flutter passaram; `flutter build apk --release` concluído. APK local: `releases/ai-tone-studio-v1.3.0-develop.apk`, SHA-256 no arquivo adjacente. Pacote `com.aitone.studio`, versionName 1.3.0/versionCode 9. Assinatura verificada e igual à V1.2.3 (certificado SHA-256 `6cdae0f216cd11b8ebc60e0c1ec16c42d6b06a153c19aa74feeb245f82b1a390`). Não houve teste físico nem escrita na pedaleira nesta entrega.
