#include "flutter_audio_endpoints.h"

#include <string>

#if defined(_WIN32)

#include <windows.h>

#include <mmdeviceapi.h>

namespace flutter_webrtc_plugin {

using libwebrtc::RTCAudioDevice;

namespace {

/// ID do endpoint que o Windows marca como dispositivo padrão de mídia
/// (`eConsole`), em UTF-8 — o mesmo formato em que o ADM devolve os seus.
/// String vazia significa "não consegui perguntar", e aí nada é mudado.
std::string IdDoEndpointPadraoDeMidia(EDataFlow fluxo) {
  std::string resultado;

  // O ADM usa COM nas threads dele; esta chamada vem da thread do plugin, que
  // pode não ter inicializado nada. RPC_E_CHANGED_MODE é resultado aceito: o
  // apartamento já está inicializado em outro modo, e os objetos abaixo não
  // dependem de apartamento para funcionar. Só descarregamos se fomos nós que
  // carregamos.
  const HRESULT inicializacao = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);

  IMMDeviceEnumerator* enumerador = nullptr;
  if (SUCCEEDED(::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                   IID_PPV_ARGS(&enumerador)))) {
    IMMDevice* dispositivo = nullptr;
    if (SUCCEEDED(enumerador->GetDefaultAudioEndpoint(fluxo, eConsole, &dispositivo))) {
      LPWSTR id = nullptr;
      if (SUCCEEDED(dispositivo->GetId(&id))) {
        const int necessario =
            ::WideCharToMultiByte(CP_UTF8, 0, id, -1, nullptr, 0, nullptr, nullptr);
        if (necessario > 1) {
          std::string convertido(necessario - 1, '\0');
          ::WideCharToMultiByte(CP_UTF8, 0, id, -1, convertido.data(), necessario,
                                nullptr, nullptr);
          resultado = std::move(convertido);
        }
        ::CoTaskMemFree(id);
      }
      dispositivo->Release();
    }
    enumerador->Release();
  }

  if (inicializacao == S_OK) ::CoUninitialize();
  return resultado;
}

/// Procura na lista do ADM o índice cujo GUID é o endpoint padrão de mídia e
/// seleciona esse índice. Um a um: render e capture têm coleções próprias.
void SelecionarEndpointPadrao(RTCAudioDevice* audio_device,
                              EDataFlow fluxo,
                              bool render) {
  const std::string alvo = IdDoEndpointPadraoDeMidia(fluxo);
  if (alvo.empty()) return;

  const int16_t total =
      render ? audio_device->PlayoutDevices() : audio_device->RecordingDevices();

  char nome[RTCAudioDevice::kAdmMaxDeviceNameSize];
  char guid[RTCAudioDevice::kAdmMaxGuidSize];

  for (int16_t i = 0; i < total; ++i) {
    nome[0] = '\0';
    guid[0] = '\0';

    const int32_t codigo = render ? audio_device->PlayoutDeviceName(i, nome, guid)
                                  : audio_device->RecordingDeviceName(i, nome, guid);
    if (codigo != 0) continue;

    if (alvo == guid) {
      // Índice, não papel: é isto que mantém o stream fora da classe
      // "comunicações" do Windows.
      if (render) {
        audio_device->SetPlayoutDevice(i);
      } else {
        audio_device->SetRecordingDevice(i);
      }
      return;
    }
  }
}

}  // namespace

void FixarEndpointsPadraoDeMidia(RTCAudioDevice* audio_device) {
  if (audio_device == nullptr) return;
  SelecionarEndpointPadrao(audio_device, eRender, /*render=*/true);
  SelecionarEndpointPadrao(audio_device, eCapture, /*render=*/false);
}

}  // namespace flutter_webrtc_plugin

#else  // !_WIN32

namespace flutter_webrtc_plugin {

// Fora do Windows não há ducking de comunicação nem endpoint COM: o WebRTC usa
// outro caminho de áudio e isto aqui não tem o que fazer.
void FixarEndpointsPadraoDeMidia(libwebrtc::RTCAudioDevice* audio_device) {}

}  // namespace flutter_webrtc_plugin

#endif
