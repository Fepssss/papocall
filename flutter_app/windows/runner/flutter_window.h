#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "tray_icon.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Esconde a janela e explica, uma vez só, onde o aplicativo foi morar.
  void EsconderNaBandeja();

  // Devolve a janela ao estado de antes de esconder: mesmo lugar, mesmo
  // tamanho, maximizada se estava assim.
  void TrazDeVolta();

  // Conta para o Dart que a janela saiu de cena ou voltou. O ciclo de vida que o
  // próprio Flutter entrega no Windows não avisa nada quando a janela é
  // escondida por nós, e sem esse recado a conversa voltaria parada no ponto em
  // que foi deixada.
  void AvisaJanela(const std::string& evento);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> canal_janela_;

  // The project to run.
  flutter::DartProject project_;

  // O ícone que segura o aplicativo na bandeja depois de fechada a janela.
  TrayIcon bandeja_;

  // Só true depois de "Sair" no menu: é o que distingue o fechar que esconde do
  // fechar que encerra.
  bool saindo_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
