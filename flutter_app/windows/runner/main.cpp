#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);

  // A janela nasce do tamanho do monitor, não de um 1280x800 fixo: na mesma
  // tela de 27" de quem usa o aplicativo, o retângulo padrão ocupava um terço
  // da área útil e a HUD inteira vinha espremida. O piso é o mínimo que a
  // interface suporta sem cortes; o teto é a própria área de trabalho.
  Win32Window::Size size(1280, 800);
  HMONITOR monitor = ::MonitorFromWindow(nullptr, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (::GetMonitorInfo(monitor, &monitor_info)) {
    const RECT area = monitor_info.rcWork;
    const int largura_util = area.right - area.left;
    const int altura_util = area.bottom - area.top;
    int largura = largura_util * 78 / 100;
    int altura = altura_util * 82 / 100;
    if (largura < 1120) largura = largura_util < 1120 ? largura_util : 1120;
    if (altura < 720) altura = altura_util < 720 ? altura_util : 720;
    size = Win32Window::Size(largura, altura);
    origin = Win32Window::Point((area.left + (largura_util - largura) / 2),
                                (area.top + (altura_util - altura) / 2));
  }

  if (!window.Create(L"PapoCall", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
