#ifndef FLUTTER_RNNOISE_H_
#define FLUTTER_RNNOISE_H_

namespace libwebrtc {
class RTCAudioProcessing;
}

namespace flutter_webrtc_plugin {

// Liga ou desliga o filtro em tempo real, sem reinstalar nada no APM.
//
// Desinstalar passando `nullptr` em SetCapturePostProcessing não é opção: o
// adaptador do libwebrtc chama Initialize() no ponteiro que recebeu sempre que a
// captura já está de pé, então um nulo aqui seria dereferência na thread de
// áudio. O filtro fica instalado para o processo inteiro e decide por dentro.
void DefinirRnnoiseAtivo(bool ativo);

// Verdadeiro quando o modelo abriu e o filtro pode trabalhar. Um falso aqui é o
// sinal para o resto do aplicativo tratar a opção como indisponível — o
// cancelamento de ruído do WebRTC continua no lugar, nada mais muda.
bool RnnoiseDisponivel();

// Instala o filtro na captura. Idempotente: chama-se tantas vezes quanto
// quiser, o APM fica com um único exemplar. Devolve false se o modelo não abriu.
bool InstalarRnnoise(libwebrtc::RTCAudioProcessing* processing);

}  // namespace flutter_webrtc_plugin

#endif  // FLUTTER_RNNOISE_H_
