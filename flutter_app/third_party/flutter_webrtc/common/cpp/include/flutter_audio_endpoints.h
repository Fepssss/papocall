#ifndef FLUTTER_AUDIO_ENDPOINTS_HXX
#define FLUTTER_AUDIO_ENDPOINTS_HXX

#include "rtc_audio_device.h"

namespace flutter_webrtc_plugin {

/// Fixa nos endpoints que o Windows trata como **dispositivo padrão de mídia**
/// os dispositivos de reprodução e captura deste ADM.
///
/// POR QUE ISTO EXISTE: o ADM do WebRTC no Windows nasce com
/// `_inputDevice = _outputDevice = kDefaultCommunicationDevice`
/// (`modules/audio_device/win/audio_device_core_win.cc`), o que faz o endpoint
/// ser ativado com o papel `eCommunications`. É esse papel que dispara o
/// "Reduzir o volume de outros sons" do Windows: durante a chamada, o computador
/// inteiro fica 80% mais baixo, inclusive para quem nunca abriu o PapoCall.
///
/// Escolher o dispositivo **por índice** usa a coleção enumerada e não passa por
/// papel nenhum, então o ducking não acontece. Este helper descobre o índice do
/// endpoint padrão de mídia comparando o ID que o ADM devolve com o ID que o
/// próprio Windows reporta, e seleciona esse índice.
///
/// Falhar aqui é inofensivo por construção: se a consulta COM não responder ou o
/// endpoint padrão não estiver na lista do ADM, nada é alterado e o
/// comportamento continua o de antes.
void FixarEndpointsPadraoDeMidia(libwebrtc::RTCAudioDevice* audio_device);

}  // namespace flutter_webrtc_plugin

#endif
