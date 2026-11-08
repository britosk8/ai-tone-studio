# Escuta da referência e preparação da calibração — V1.6.0

Esta entrega permite ouvir a guitarra já separada e confirmar o trecho/canal que será analisado. Acrescenta registros de avaliação vinculados às capturas reais e prepara a captura do preset aprovado de Infest na MK20. O motor continua heurístico: não foi treinado um renderer do pedal nem demonstrado um ganho de fidelidade sonora nesta entrega.

## Uso pelo aplicativo

Instalar `releases/ai-tone-studio-v1.6.0-develop.apk` sobre a versão atual, mantendo os dados. O arquivamento de testes da V1.5.6 não se repete quando seu marcador já está salvo.

### Escolher a referência antes de gerar

1. Em **Analisar música**, escolher uma música já separada na biblioteca. Não é necessário importar novamente o M4A nem executar Demucs de novo.
2. Usar **Ouvir e escolher guitarra base** ou **Ouvir e escolher guitarra solo**. Ajustar início, duração e canal, ouvir, e confirmar **Usar este trecho**.
3. A escuta usa cópias WAV PCM16 mono de 3–30 segundos. Os controles numéricos anteriores continuam aceitando até 120 segundos na geração, mas a confirmação na tela de escuta usa o intervalo mostrado, limitado a 30 segundos.
4. **Volume extra para escuta** altera somente a reprodução. Não modifica o stem, seus hashes, as medições ou parâmetros gerados. Uma limitação de pico é aplicada apenas à cópia de escuta para não introduzir clipping nessa cópia.
5. Gerar os presets pelos dispositivos escolhidos. Início, duração e canal são enviados juntos, incluídos na identidade da geração, e o canal escolhido é respeitado pela análise.

Na tela de presets → **Timbres ao longo da música**, cada estado também oferece **Ouvir e escolher trecho**. Nesse caso, o canal é o do próprio estado e a seleção fica dentro de um de seus intervalos. A geração rejeita regiões fora do estado. Repetir a mesma seleção reutiliza a variante; uma região diferente tem identidade própria. A reprodução é encerrada ao sair da tela, colocar o app em segundo plano ou perder o foco de áudio.

### Comparar com a gravação do pedal

Em **Gravar e comparar esta base/este solo**, usar **Ouvir e ajustar trecho da guitarra salva**. Confirmar a seleção salva o perfil dessa passagem para a função escolhida, incluindo o canal. Tocar a mesma passagem na guitarra e gravar pelo USB/OTG existente. Nenhum comando de preset é enviado pelo reprodutor de áudio.

A proteção de referência fraca foi estendida às seleções manuais e à geração pela biblioteca. O RMS do trecho original é comparado com blocos da mesma guitarra/canal; um trecho abaixo de -40 dBFS e mais de 18 dB abaixo do nível de referência do canal é rejeitado para geração/comparação. O nível de referência usa o percentil 95 de blocos de até 5 s. Um master uniformemente baixo não é rejeitado só por volume. Trechos fracos continuam disponíveis para escuta e inspeção. Alterar apenas o volume de escuta não permite contornar a proteção.

Também se reavalia o trecho curto escolhido dentro de um estado: um agrupamento forte não autoriza automaticamente qualquer subtrecho silencioso. No caso real de Infest salvo neste projeto, 9–21 s foi rejeitado pela nova proteção e 141–153 s foi aceito, sem nova separação e sem alteração dos arquivos originais.

## Primeiro ponto de calibração: Infest aprovado

Na comparação de um preset MK20 de Infest, **Gravar referência aprovada de Infest** abre uma captura dedicada ao `PAPA INFEST` do slot 76. O backend reconstitui os controles exclusivamente da leitura previamente validada e confere o hash da imagem. Se a evidência estiver ausente ou alterada, não inventa os parâmetros e não oferece um substituto.

Selecionar `PAPA INFEST`, slot 76, na MK20 e usar a Konig Stratocaster, conforme o teste originalmente aprovado. Ouvir/escolher a passagem de referência e gravar a saída processada. O app não seleciona esse slot automaticamente nem modifica o preset. A confirmação de qual preset está aplicado e da configuração usada é declarada pelo músico; não é uma nova leitura física em tempo real.

Esse modo não insere outro preset na biblioteca ativa, não substitui o gerado pela música e não oferece ajustes/envio do preset aprovado na tela de resultado. Ele serve para registrar um ponto de partida acústico que poderá ser comparado às próximas gerações. O gerador das demais músicas não copia essa cadeia de Infest.

## Registrar os testes para calibração

Depois da comparação, abrir **Registrar teste para calibração**:

- Informar guitarra (Konig SSS ou Strinberg HH), posição do captador, rota USB/OTG ou analógica MQ44 e se o sinal é processado ou DI seco.
- Confirmar se o preset indicado realmente estava aplicado no pedal.
- Registrar a escuta: precisa melhorar, ficou próximo, piorou após ajuste ou aprovado para o ensaio; notas são opcionais.

O registro mantém snapshots do preset submetido, SHA do áudio original, perfil e intervalo/canal da referência, resultado da comparação e contexto declarado. Não reenvia o áudio, não apaga a gravação e não altera o preset. A mesma avaliação tem ID estável; mudar a avaliação cria outra versão. O contexto do trecho é salvo no momento da comparação, não reconstruído a partir de uma seleção posterior.

Registros incompletos, DI não confirmado, clipping ou comparação com perfil geral continuam guardados, com flags para revisão. A aprovação pelo músico não eleva a confiança do gerador nem transforma uma captura saturada em dado de calibração válido. Ainda precisamos obter e ouvir as capturas reais dessa etapa antes de ajustar o motor com evidência acústica.

## Backend como serviço do usuário

O template `ops/ai-tone-studio.service.in` e `tools/install_backend_service.py` instalam `ai-tone-studio.service` em `~/.config/systemd/user/`. O serviço usa a mesma `.venv`, catálogo e diretório `backend/data`, com um worker, sem recarga automática e reinício em falha. É iniciado no login do usuário, independente do chat. Não foi habilitado `linger`; desligar o computador ou encerrar a sessão do usuário continua afetando a disponibilidade.

```bash
cd /home/adrianobn/ai-tone-studio
backend/.venv/bin/python tools/install_backend_service.py
# Encerrar antes o servidor manual, de forma graciosa, sem interromper trabalhos ativos.
systemctl --user start ai-tone-studio
systemctl --user status ai-tone-studio
journalctl --user -u ai-tone-studio -n 50
```

O instalador não mata processos nem inicia uma segunda instância na porta 8000. Para parar: `systemctl --user stop ai-tone-studio`. Para desabilitar a inicialização: `systemctl --user disable ai-tone-studio`. O serviço não é fila durável: reinícios podem interromper análises; retomada automática dos jobs e descoberta do IP na rede ficam para outra entrega. O endereço configurado no app ainda precisa corresponder ao IP atual do computador.

## Interfaces e fontes técnicas

- `GET /api/v1/presets/{pair}/reference/{role}/preview`: WAV temporário, com ganho apenas de escuta. Não persiste uma seleção.
- `PUT /api/v1/presets/{pair}/reference/{role}`: seleção confirmada e canal; aceita `-1` para o canal mais audível do trecho.
- `POST /api/v1/analyze-saved`: início/duração/canal por função, com reutilização dos stems.
- `POST /api/v1/presets/{pair}/tone-states/{state}/generate`: região opcional confirmada na escuta, validada dentro dos intervalos do estado.
- `POST /api/v1/presets/{pair}/calibration-baseline`: referência histórica aprovada, somente leitura.
- `POST /api/v1/recordings/{id}/evaluation` e `GET /api/v1/calibration-tests`: versões de avaliações, ligadas às capturas existentes.

Player nativo conforme [estado e liberação de recursos do MediaPlayer](https://developer.android.com/media/platform/mediaplayer/state-resources) e [API MediaPlayer](https://developer.android.com/reference/android/media/MediaPlayer). Reinício do serviço conforme [systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html). Não foram adicionadas bibliotecas de reprodução nem alterados codecs de escrita MK20/MK300.

## Validação desta entrega

- 160 testes do backend e 103 testes Flutter passaram; `flutter analyze` sem problemas.
- Verificados: canal L/R/automático na cópia de escuta e na análise; início/duração confirmados usados na geração; IDs idempotentes; originais e seleções preservados ao apenas ouvir; cancelamento da reprodução/download; proteção de trechos fracos e região fora do estado; avaliação versionada sem sobrescrever a captura; referência aprovada sem edição/envio.
- O APK release compila a implementação Kotlin de MediaPlayer. A reprodução audível no celular, o roteamento real do áudio e as novas capturas de calibração ainda exigem teste físico.
- O serviço do usuário foi instalado e habilitado; servidor manual encerrado de forma graciosa. Health 1.6.0 confirmado em localhost e no IP LAN atual, com um único processo gerenciado e `Restart=on-failure`. Não foi simulada queda de um servidor em uso.
- Em chamadas reais ao serviço, a cópia de Infest entregue pela API foi WAV PCM16 mono de 3 segundos e a referência aprovada foi reconstruída da captura MK20 do slot 76. Esses acessos não alteraram a seleção salva nem enviaram comandos ao pedal.

A descoberta automática de IP, fila durável de processamento, alinhamento de execução e otimização acústica dos controles permanecem etapas posteriores. O dado necessário agora é a gravação da referência aprovada pela cadeia real, seguida de uma captura do preset gerado tocando a mesma passagem.
