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

### Sonda de captura (diagnóstico)

| Arquivo | Mudança |
| --- | --- |
| `common/cpp/include/flutter_audio_probe.h` | **novo** — declara `MaybeInstallAudioProbe` |
| `common/cpp/src/flutter_audio_probe.cc` | **novo** — mede o quadro de áudio sem tocá-lo |
| `common/cpp/src/flutter_webrtc_base.cc` | `#include` + chamada a `MaybeInstallAudioProbe(audio_processing_.get())` sob `#if defined(_WIN32)`, logo depois de a fábrica entregar o APM |
| `windows/CMakeLists.txt` | adiciona `flutter_audio_probe.cc` à lista de fontes |

### RNNoise no microfone

O modelo vem junto como fonte (`third_party/rnnoise`, Xiph, tag **v0.1.1** — a última
com o modelo compilado dentro; de v0.2 em diante ele é baixado à parte). Cinco arquivos,
todos com a razão de ser escrita neles:

| Arquivo | Mudança |
| --- | --- |
| `third_party/rnnoise/` | **novo** — fontes do RNNoise v0.1.1 + COPYING/AUTHORS, sem `example/` nem scripts de treino |
| `third_party/rnnoise/src/pitch.c`, `src/celt_lpc.c` | **três VLAs trocadas por dimensão fixa**: o MSVC não compila array de tamanho variável (C99). As dimensões têm folga sobre o que o RNNoise pede (`len` 960, `max_pitch` 588, `maxperiod` 768) |
| `common/cpp/include/flutter_rnnoise.h`, `common/cpp/src/flutter_rnnoise.cc` | **novo** — o `CustomProcessing` que estica 16 kHz → 48 kHz, filtra, e enxuga de volta |
| `common/cpp/src/flutter_webrtc.cc` | método `setNeuralNoiseSuppression`, devolvendo se a máquina aceitou o filtro |
| `lib/src/helper.dart` | `Helper.setNeuralNoiseSuppression(bool)` |
| `windows/CMakeLists.txt` | `papocall_rnnoise` como estática de C (`/W0`, `_USE_MATH_DEFINES`), ligada ao plugin |

O filtro fica instalado para o processo inteiro e decide por dentro se filtra. Desinstalá-lo
passando `nullptr` não é opção: o adaptador do libwebrtc chama `Initialize()` no ponteiro que
recebe sempre que a captura já está de pé, e um nulo ali seria dereferência na thread de áudio.

### A sonda

Não altera áudio nenhum. Instala-se apenas se existir `%TEMP%\papocall_audio_probe.on`, e enquanto
ela roda mede os dois lados da chamada — `SetCapturePostProcessing` (o microfone antes de virar
faixa publicada) e `SetRenderPreProcessing` (o que chegou dos outros antes de sair no alto-falante)
—, escrevendo no diretório temporário, por lado (`captura`, `reproducao`):

- `papocall_audio_<lado>.f32` — o PCM bruto que o APM entregou (float 32 little-endian), para
  comparar com e sem filtro e para medir a largura de banda que realmente chegou;
- `papocall_audio_<lado>.txt` — reescrito a cada 5 s: taxa, canais, `num_bands`, `buffer_size`,
  contagem de quadros, **pico de amplitude** (é o que responde se o caminho entrega em ±1 ou na
  escala de ±32768 que o RNNoise espera), **rms**, **amostras recortadas** (o ceifamento que
  "som de tv de tubo" costuma ser), e o tempo médio/pior por quadro em µs.

Para desligar, apaga-se a marca e reinicia-se o app. O despejo tem teto de 60 s por lado porque
isto vai dentro de um build publicado.

### Comparando a qualidade do filtro com a sonda

Os dois disputam o **mesmo slot**: quem chamar `SetCapturePostProcessing` por último fica com ele,
então ligar o RNNoise desinstala a sonda. Hoje isso dá a comparação *entre execuções* (sonda com
RNNoise desligado, duas vezes, mudando só as quatro chaves), mas não a entrada e a saída do filtro
na mesma passada — para isso teria de instrumentar o próprio `flutter_rnnoise.cc`.

## Como reaplicar em um upgrade do pacote

1. Trocar a versão no `pubspec.yaml` e rodar `flutter pub get` para baixar o pacote novo.
2. Copiar o pacote novo por cima desta pasta, **menos** `example/`, `.github/` e o conteúdo de
   `third_party/libwebrtc/` e `third_party/downloads/` (binários baixados pelo CMake, fora do Git).
3. Reaplicar os quatro itens da tabela: os dois arquivos novos são autocontidos; nas mudanças em
   `flutter_webrtc_base.cc` procure por `MaybeInstallAudioProbe` e em `windows/CMakeLists.txt` por
   `flutter_audio_probe.cc`.
4. `flutter build windows --release` e conferir com o `diff -rq` acima que só restam essas quatro
   diferenças.

Se o `libwebrtc_version.ini` mudar de major (m150 → m1xx), conferir no repositório do
`webrtc-sdk/libwebrtc` se `SetCapturePostProcessing` e a assinatura de `Process` continuam as
mesmas antes de assumir que o patch ainda vale.

## Licenças

Este diretório mantém a licença BSD-3 do original (`LICENSE`, `NOTICE` do pacote). O que for
adicionado aqui precisa continuar compatível com isso — RNNoise, do Xiph, é BSD-3 e é.
