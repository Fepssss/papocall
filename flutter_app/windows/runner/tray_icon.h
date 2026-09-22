#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>

#include <shellapi.h>

// O que a bandeja devolve para a janela quando mexem no ícone dela.
namespace bandeja {
// A faixa WM_APP é a reservada ao aplicativo; o Windows manda esta mensagem com
// o evento do mouse no lparam.
inline constexpr UINT kMensagem = WM_APP + 100;
inline constexpr UINT kAbrir = 1;
inline constexpr UINT kSair = 2;
}  // namespace bandeja

// Ícone do aplicativo na bandeja do Windows, com o menu de abrir e sair.
//
// Existe por causa de uma decisão de produto: fechar a janela esconde o
// aplicativo, e o que esconde tem de oferecer o caminho de volta. Por isso
// [Criar] devolve falso quando o Windows recusa o ícone — sem ícone não há
// como voltar, e nesse caso a janela tem de fechar do jeito antigo, matando o
// processo, em vez de sumir com ele vivo.
class TrayIcon {
 public:
  enum class Resultado { nada, abrir, sair };

  TrayIcon() = default;
  ~TrayIcon();

  TrayIcon(const TrayIcon&) = delete;
  TrayIcon& operator=(const TrayIcon&) = delete;

  // Coloca o ícone na bandeja, usando o mesmo desenho do executável.
  bool Criar(HWND janela, const wchar_t* texto);

  // Tira o ícone da bandeja. Chamado na destruição da janela e antes de sair,
  // para não deixar um desenho morto pendurado na barra.
  void Remover();

  // Trata uma mensagem que a bandeja mandou para [janela]. Devolve o que o
  // usuário escolheu, ou [nada] enquanto ele só passou o mouse.
  Resultado TrataMensagem(UINT mensagem, WPARAM wparam, LPARAM lparam);

  // Balão de aviso uma vez por execução, para quem fechou a janela sem saber
  // para onde ela foi.
  void Avisar(const wchar_t* titulo, const wchar_t* texto);

  bool ativo() const { return ativo_; }

 private:
  // O menu suspenso do botão direito. Devolve [nada] se a pessoa fechou o menu
  // sem escolher.
  Resultado MostraMenu();

  NOTIFYICONDATAW dados_{};
  HWND janela_ = nullptr;
  bool ativo_ = false;
  bool avisou_ = false;
  DWORD ultimo_menu_ms_ = 0;
};

#endif  // RUNNER_TRAY_ICON_H_
