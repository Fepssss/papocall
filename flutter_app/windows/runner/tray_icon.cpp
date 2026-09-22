#include "tray_icon.h"

#include "resource.h"

namespace {

// Dois cliques direitos seguidos em menos disto aqui é o Windows 11 mandando
// WM_RBUTTONUP e WM_CONTEXTMENU pelo mesmo gesto, e o segundo menu por cima do
// primeiro só confunde.
constexpr DWORD kEspantoDoMenuMs = 300;

}  // namespace

TrayIcon::~TrayIcon() { Remover(); }

bool TrayIcon::Criar(HWND janela, const wchar_t* texto) {
  if (ativo_) return true;
  if (janela == nullptr) return false;

  HICON icone = ::LoadIconW(::GetModuleHandleW(nullptr),
                            MAKEINTRESOURCEW(IDI_APP_ICON));
  if (icone == nullptr) return false;

  janela_ = janela;
  dados_ = {};
  dados_.cbSize = sizeof(NOTIFYICONDATAW);
  dados_.hWnd = janela_;
  dados_.uID = 1;
  dados_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  dados_.uCallbackMessage = bandeja::kMensagem;
  dados_.hIcon = icone;
  lstrcpynW(dados_.szTip, texto, ARRAYSIZE(dados_.szTip));

  if (!::Shell_NotifyIconW(NIM_ADD, &dados_)) {
    dados_ = {};
    janela_ = nullptr;
    return false;
  }
  ativo_ = true;
  return true;
}

void TrayIcon::Remover() {
  if (!ativo_) return;
  ::Shell_NotifyIconW(NIM_DELETE, &dados_);
  dados_ = {};
  janela_ = nullptr;
  ativo_ = false;
}

TrayIcon::Resultado TrayIcon::TrataMensagem(UINT mensagem, WPARAM wparam,
                                            LPARAM lparam) {
  if (!ativo_ || mensagem != bandeja::kMensagem) return Resultado::nada;
  if (LOWORD(wparam) != dados_.uID) return Resultado::nada;

  switch (static_cast<UINT>(lparam)) {
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
      return Resultado::abrir;
    case WM_RBUTTONUP:
    case WM_CONTEXTMENU:
      return MostraMenu();
    default:
      return Resultado::nada;
  }
}

void TrayIcon::Avisar(const wchar_t* titulo, const wchar_t* texto) {
  if (!ativo_ || avisou_) return;
  avisou_ = true;

  dados_.uFlags |= NIF_INFO;
  lstrcpynW(dados_.szInfoTitle, titulo, ARRAYSIZE(dados_.szInfoTitle));
  lstrcpynW(dados_.szInfo, texto, ARRAYSIZE(dados_.szInfo));
  dados_.dwInfoFlags = NIIF_INFO;
  dados_.uTimeout = 8000;
  ::Shell_NotifyIconW(NIM_MODIFY, &dados_);

  // O balão é uma mensagem de uma vez: sem tirar a bandeira, cada modificação
  // do ícone o reapresentaria.
  dados_.uFlags &= ~NIF_INFO;
}

TrayIcon::Resultado TrayIcon::MostraMenu() {
  // O ponto de espera é o FIM do menu anterior, não o começo: o Windows 11 manda
  // WM_RBUTTONUP e WM_CONTEXTMENU pelo mesmo gesto, e o segundo chega logo depois
  // de a pessoa escolher alguma coisa — sem isto, o menu reapareceria na cara de
  // quem já clicou.
  const DWORD agora = ::GetTickCount();
  if (agora - ultimo_menu_ms_ < kEspantoDoMenuMs) return Resultado::nada;

  POINT cursor{};
  ::GetCursorPos(&cursor);

  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) return Resultado::abrir;
  ::AppendMenuW(menu, MF_STRING, bandeja::kAbrir, L"Abrir o PapoCall");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, bandeja::kSair, L"Sair do PapoCall");

  // Sem isto o menu fica "preso" atrás da janela e não fecha ao clicar fora.
  ::SetForegroundWindow(janela_);
  const UINT escolhido = ::TrackPopupMenuEx(
      menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_RETURNCMD, cursor.x,
      cursor.y, janela_, nullptr);
  ::PostMessageW(janela_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
  ultimo_menu_ms_ = ::GetTickCount();

  if (escolhido == bandeja::kSair) return Resultado::sair;
  if (escolhido == bandeja::kAbrir) return Resultado::abrir;
  return Resultado::nada;
}
