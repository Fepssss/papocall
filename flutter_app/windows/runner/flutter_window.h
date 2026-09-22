#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

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
