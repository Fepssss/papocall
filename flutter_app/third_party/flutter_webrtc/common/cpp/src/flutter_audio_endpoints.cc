#include "flutter_audio_endpoints.h"

#include <string>

#if defined(_WIN32)

#include <windows.h>

#include <mmdeviceapi.h>

namespace flutter_webrtc_plugin {

using libwebrtc::RTCAudioDevice;

namespace {

std::string g_status;

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
  const char* papel = render ? "saida" : "microfone";
  const std::string alvo = IdDoEndpointPadraoDeMidia(fluxo);
  if (alvo.empty()) {
    g_status += std::string(papel) + "=o Windows nao respondeu; ";
    return;
  }

  const int16_t total =
      render ? audio_device->PlayoutDevices() : audio_device->RecordingDevices();
  if (total <= 0) {
    // Foi aqui que o conserto se perdeu uma vez: o ADM ainda não tinha listado
    // aparelho nenhum, o laço abaixo não girou, e nada foi mudado — com o
    // ducking de volta e sem uma linha em lugar nenhum contando isso.
    g_status += std::string(papel) + "=ADM sem aparelhos na hora; ";
    return;
  }

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
      g_status += std::string(papel) + "=indice " + std::to_string(i) +
                  " (" + nome + ") fora do papel comunicacoes; ";
      return;
    }
  }
  g_status += std::string(papel) + "=" + std::to_string(total) +
              ": nenhum e o padrao de midia; ";
}

}  // namespace

void FixarEndpointsPadraoDeMidia(RTCAudioDevice* audio_device) {
  g_status.clear();
  if (audio_device == nullptr) {
    g_status = "sem ADM";
    return;
  }
  SelecionarEndpointPadrao(audio_device, eRender, /*render=*/true);
  SelecionarEndpointPadrao(audio_device, eCapture, /*render=*/false);
}

std::string StatusoDoFixDeEndpoints() {
  return g_status.empty() ? std::string("o conserto ainda nao rodou") : g_status;
}

}  // namespace flutter_webrtc_plugin

#else  // !_WIN32

namespace flutter_webrtc_plugin {

// Fora do Windows não há ducking de comunicação nem endpoint COM: o WebRTC usa
// outro caminho de áudio e isto aqui não tem o que fazer.
void FixarEndpointsPadraoDeMidia(libwebrtc::RTCAudioDevice* audio_device) {}

std::string StatusoDoFixDeEndpoints() { return "fora do Windows nao ha ducking"; }

}  // namespace flutter_webrtc_plugin

#endif
