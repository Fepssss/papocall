#ifndef FLUTTER_AUDIO_PROBE_H_
#define FLUTTER_AUDIO_PROBE_H_

namespace libwebrtc {
class RTCAudioProcessing;
}

namespace flutter_webrtc_plugin {

// Instala o coletor de quadro de áudio na captura, se a marca dele existir.
//
// Serve para medir o caminho antes de mudar o áudio: quantos quadros chegam, a
// que taxa e em que escala vêm os floats, e quanto tempo se gasta dentro do
// callback da thread de captura. Sem o arquivo de marca, não faz nada.
void MaybeInstallAudioProbe(libwebrtc::RTCAudioProcessing* processing);

}  // namespace flutter_webrtc_plugin

#endif  // FLUTTER_AUDIO_PROBE_H_
