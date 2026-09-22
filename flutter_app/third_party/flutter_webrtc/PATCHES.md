# flutter_webrtc vendorizado e patcheado

Cópia de `flutter_webrtc` **1.6.2+hotfix.3** (sha256 `c1d3674f…` no `pubspec.lock`), com o
caminho Windows patcheado. O `dependency_overrides` do `pubspec.yaml` aponta para cá.

## Por que existe um fork

O microfone precisa de cancelamento de ruído **dentro da thread de captura**, em C++. O
libwebrtc pré-compilado que este plugin usa (`third_party/libwebrtc_version.ini`, hoje
`libwebrtc.m150.7871.02`, de <https://github.com/webrtc-sdk/libwebrtc>) já expõe isso:

    libwebrtc::RTCAudioProcessing::CustomProcessing   // Initialize / Process / Reset / Release
    RTCAudioProcessing::SetCapturePostProcessing(...)

que em `src/rtc_audio_processing_impl.cc` entra por
`BuiltinAudioProcessingBuilder().SetCapturePostProcessing(...)` e, em
`src/rtc_peerconnection_factory_impl.cc`, é o mesmo objeto que a fábrica usa e que
`GetAudioProcessing()` devolve.

O que o plugin **não** tem é um caminho do Dart até lá. `flutter_media_stream.cc` só lê quatro
booleanos (`echoCancellation`, `noiseSuppression`, `autoGainControl`, `highpassFilter`), e o
`TrackProcessor` do `livekit_client` não consegue ler PCM nem criar faixa no nativo. Por isso o
patch mora aqui, e não no app.

## O que está modificado

Tudo o mais é byte por byte igual ao pacote do pub. Para conferir:

    diff -rq "$LOCALAPPDATA/Pub/Cache/hosted/pub.dev/flutter_webrtc-1.6.2+hotfix.3" \
        third_party/flutter_webrtc

O modelo vem junto como fonte (`third_party/rnnoise`, Xiph, tag **v0.1.1** — a última com o
modelo compilado dentro; de v0.2 em diante ele é baixado à parte, o que não serve para uma
build reprodutível).

| Arquivo | Mudança |
| --- | --- |
| `third_party/rnnoise/` | **novo** — fontes do RNNoise v0.1.1 + `COPYING`/`AUTHORS`, sem `example/` nem scripts de treino |
| `third_party/rnnoise/src/pitch.c`, `src/celt_lpc.c` | **três VLAs trocadas por dimensão fixa**: o MSVC não compila array de tamanho variável (C99). As dimensões têm folga sobre o que o RNNoise pede (`len` 960, `max_pitch` 588, `maxperiod` 768) |
| `common/cpp/include/flutter_rnnoise.h`, `common/cpp/src/flutter_rnnoise.cc` | **novo** — o `CustomProcessing` que estica 16 kHz → 48 kHz, filtra, e enxuga de volta |
| `common/cpp/src/flutter_webrtc.cc` | método `setNeuralNoiseSuppression`, devolvendo se a máquina aceitou o filtro |
| `lib/src/helper.dart` | `Helper.setNeuralNoiseSuppression(bool)` |
| `windows/CMakeLists.txt` | `flutter_rnnoise.cc` na lista de fontes + `papocall_rnnoise` como estática de C (`/W0`, `_USE_MATH_DEFINES`), ligada ao plugin |
| `common/cpp/include/flutter_audio_endpoints.h`, `common/cpp/src/flutter_audio_endpoints.cc` | **novo** — fixa os endpoints padrão de *mídia* do Windows como os dispositivos do ADM, para o stream não nascer na classe "comunicações" |
| `common/cpp/src/flutter_webrtc_base.cc` | chamada a `FixarEndpointsPadraoDeMidia()` na criação do ADM |
| `windows/CMakeLists.txt` | `flutter_audio_endpoints.cc` na lista de fontes (`mmdevapi.lib` e `ole32.lib` já eram ligados pelo plugin) |

O filtro fica instalado para o processo inteiro e decide por dentro se filtra. Desinstalá-lo
passando `nullptr` não é opção: o adaptador do libwebrtc chama `Initialize()` no ponteiro que
recebe sempre que a captura já está de pé, e um nulo ali seria dereferência na thread de áudio.

### Ducking do Windows (o computador inteiro ficava mais baixo durante a chamada)

`modules/audio_device/win/audio_device_core_win.cc` constrói o ADM com
`_inputDevice = _outputDevice = kDefaultCommunicationDevice` (linhas 394-395 da versão de
junho/2026 do fonte), e o caminho de seleção por papel usa isso:

    ERole role;
    (_outputDevice == AudioDeviceModule::kDefaultDevice) ? role = eConsole
                                                         : role = eCommunications;

Papel `eCommunications` é o gatilho do recurso "Comunicações" do painel de Som: enquanto um
stream assim está aberto, o Windows atenua em 80% **os outros** aplicativos. Não é bug do
PapoCall nem escolha nossa — é o padrão do WebRTC no Windows —, mas é o nosso usuário que via
o jogo e o player baixarem de volume.

O conserto não pode ser feito do Dart: o wrapper `rtc_audio_device.h` do binário pré-compilado
só expõe `SetPlayoutDevice(uint16_t index)` / `SetRecordingDevice(uint16_t index)`, sem a
sobrecarga `WindowsDeviceType`. Escolher **por índice** usa a coleção enumerada e não passa por
papel nenhum, então o stream não entra na classe de comunicação — e é isso que `flutter_audio_endpoints.cc`
faz: pergunta ao COM qual é o endpoint padrão de mídia (`GetDefaultAudioEndpoint(fluxo, eConsole)`
→ `IMMDevice::GetId`), compara com o GUID que o próprio ADM devolve em `PlayoutDeviceName` /
`RecordingDeviceName`, e seleciona o índice correspondente.

Duas decisões registradas aqui porque são fáceis de desfazer sem querer:

- **Uma vez só, na criação do ADM.** Rodar isso a cada `getUserMedia` desfaria a escolha
  explícita de saída que a interface faz depois (`Hardware.selectAudioOutput`), que é o
  caminho do usuário que escolheu um alto-falante específico.
- **Falhar é silencioso por desenho.** Se o COM não responder ou o endpoint padrão não estiver
  na lista do ADM (aparelho desconectado, driver estranho), nada é alterado e o comportamento
  volta a ser o de antes — sem faixa muda e sem crash.

Custo, dito sem rodeio: quem configurou no Windows um "dispositivo de comunicação" diferente do
dispositivo de reprodução padrão passa a ouvir pelo de mídia. É a mesma troca que Discord e
Chrome fazem, e continua consertável na interface do PapoCall, onde a escolha manual vale.

## O que a medição anterior estabeleceu (e por que a sonda saiu)

Este fork já carregou uma sonda que media o quadro de áudio sem tocá-lo, ligada por um arquivo
de marca no diretório temporário. Ela respondeu três coisas que nenhuma documentação respondia,
e o filtro foi desenhado em cima delas:

- a captura chega a **16 kHz, mono, 160 amostras por quadro de 10 ms** — daí o reamostrador;
- os floats vêm na **escala de short (±32768)** — pico medido 31073 numa fala normal. A
  documentação do `webrtc::CustomProcessing` diz ±1; quem acreditasse nela multiplicaria por
  32768 e entregaria o microfone ceifado. Por isso não há conversão de escala no filtro;
- o custo do callback vazio é de **~1 µs por quadro** (pior 19 µs). A sonda também mostrou o que
  não se deve fazer ahí: abrir arquivo na thread de áudio emperrava um quadro em 85 ms na captura
  e ~1 s na reprodução.

Foi retirada em setembro de 2026 porque não servia para o que veio depois: a sonda e o filtro
disputam o **mesmo slot** (`SetCapturePostProcessing`), então medir o custo do RNNoise com ela
instalaria um no lugar do outro. Para esse número, o lugar certo é um contador dentro do próprio
`flutter_rnnoise.cc`, e ele não existe ainda. Quem precisar medir de novo o caminho de áudio
recria a sonda a partir do histórico deste diretório no Git.

## Como reaplicar em um upgrade do pacote

1. Trocar a versão no `pubspec.yaml` e rodar `flutter pub get` para baixar o pacote novo.
2. Copiar o pacote novo por cima desta pasta, **menos** `example/`, `.github/` e o conteúdo de
   `third_party/libwebrtc/` e `third_party/downloads/` (binários baixados pelo CMake, fora do Git).
3. Reaplicar as seis linhas da tabela: os arquivos novos são autocontidos; em
   `flutter_webrtc.cc` procure por `setNeuralNoiseSuppression`, em `lib/src/helper.dart` por
   `setNeuralNoiseSuppression` e em `windows/CMakeLists.txt` por `rnnoise`.
4. `flutter build windows --release` e conferir com o `diff -rq` acima que só restam essas
   diferenças.
5. Se o `libwebrtc_version.ini` mudou de major (m150 → m1xx), conferir no repositório do
   `webrtc-sdk/libwebrtc` se `SetCapturePostProcessing` e a assinatura de `Process` continuam as
   mesmas antes de assumir que o patch ainda vale.

## Licenças

Este diretório mantém a licença BSD-3 do original (`LICENSE`, `NOTICE` do pacote). O que for
adicionado aqui precisa continuar compatível com isso — RNNoise, do Xiph, é BSD-3, e o aviso que
acompanha a distribuição em binário está em `../../../../public/licencas.txt`.
