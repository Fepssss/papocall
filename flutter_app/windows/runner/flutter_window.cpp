#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  canal_janela_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "papocall/janela",
      &flutter::StandardMethodCodec::GetInstance());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  // O ícone na bandeja é o que segura o aplicativo depois de fechada a janela.
  // Se o Windows recusá-lo, nada de esconder: sem ícone não há caminho de volta
  // e o PapoCall continuaria rodando invisível. Nesse caso o fechar volta a ser
  // o que era antes — encerrar o processo.
  bandeja_.Criar(GetHandle(), L"PapoCall");

  return true;
}

void FlutterWindow::OnDestroy() {
  // O desenho sai da bandeja junto com a janela: deixar o ícone lá depois de
  // morto o processo é deixar um botão que não faz nada.
  bandeja_.Remover();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Piso da janela: abaixo disto a HUD não cabe e a interface começa a cortar
  // coluna por coluna. É em pixels lógicos e convertido pelo DPI da própria
  // janela, então vale igual numa tela 4K com o Windows a 200%.
  if (message == WM_GETMINMAXINFO) {
    MINMAXINFO* info = reinterpret_cast<MINMAXINFO*>(lparam);
    const UINT dpi = ::GetDpiForWindow(hwnd);
    const LONG minimo_x = ::MulDiv(960, dpi, 96);
    const LONG minimo_y = ::MulDiv(600, dpi, 96);
    if (info->ptMinTrackSize.x < minimo_x) info->ptMinTrackSize.x = minimo_x;
    if (info->ptMinTrackSize.y < minimo_y) info->ptMinTrackSize.y = minimo_y;
    return 0;
  }

  // O que a bandeja manda chega aqui: clique simples ou duplo devolve a janela
  // para a tela, botão direito abre o menu com o sair de verdade.
  if (message == bandeja::kMensagem) {
    const TrayIcon::Resultado escolha =
        bandeja_.TrataMensagem(message, wparam, lparam);
    if (escolha == TrayIcon::Resultado::abrir) {
      TrazDeVolta();
      return 0;
    }
    if (escolha == TrayIcon::Resultado::sair) {
      // "Sair" é o único caminho que encerra: fecha a janela de verdade, do jeito
      // que o runner já fechava antes da bandeja existir.
      saindo_ = true;
      ::DestroyWindow(hwnd);
      return 0;
    }
    return 0;
  }

  // Fechar a janela é escondê-la na bandeja. A voz, o chat e a conexão continuam
  // onde estavam — é para isso que o aplicativo fica vivo lá.
  if (message == WM_CLOSE && !saindo_ && bandeja_.ativo()) {
    EsconderNaBandeja();
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::AvisaJanela(const std::string& evento) {
  if (!canal_janela_) return;
  canal_janela_->InvokeMethod(evento, nullptr);
}

void FlutterWindow::EsconderNaBandeja() {
  const bool escondida = ::ShowWindow(GetHandle(), SW_HIDE) == TRUE;
  AvisaJanela("escondeu");
  // O primeiro fechamento é o momento em que a pessoa ainda não sabe para onde
  // o aplicativo foi; depois disso o balão repetido só atrapalha.
  if (escondida) {
    bandeja_.Avisar(L"PapoCall continua aberto",
                    L"A janela foi escondida na bandeja, e voz e chat seguem "
                    L"ligados. Clique no ícone para voltar; botão direito para "
                    L"sair do aplicativo.");
  }
}

void FlutterWindow::TrazDeVolta() {
  const HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;

  // SW_SHOW, e não SW_SHOWNORMAL: quem escondia a janela maximizada quer ela
  // maximizada de volta, não do tamanho padrão.
  ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  AvisaJanela("voltou");
  ::SetForegroundWindow(hwnd);
  if (::GetForegroundWindow() != hwnd) {
    // O Windows não deixa qualquer processo tomar o primeiro plano. Quando ele
    // nega, o que sobra é avisar onde está: a barra de tarefas pisca.
    FLASHWINFO flash{static_cast<DWORD>(sizeof(FLASHWINFO)), hwnd,
                      FLASHW_ALL | FLASHW_TIMERNOFG, 3, 0};
    ::FlashWindowEx(&flash);
  }
}
