import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';

/// Log de diagnóstico em `%APPDATA%\PapoCall\papocall.log`.
///
/// Existe porque as falhas de sessão e de voz eram silenciosas: o usuário só
/// via um botão que não fazia nada. Nunca gravar segredos aqui — somente
/// códigos, status HTTP, expirações e caminhos.
class AppLog {
  /// `flutter test` define FLUTTER_TEST no ambiente do processo. Além do
  /// override de raiz, isso mantém qualquer suíte fora do log da instalação.
  static bool get _emTeste =>
      Platform.environment.containsKey('FLUTTER_TEST');

  static void write(String tag, String message) {
    if (_emTeste) return;
    try {
      AppPaths.file('papocall.log').writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] [$tag] $message\n',
        mode: FileMode.append,
        encoding: utf8,
        flush: true,
      );
    } catch (_) {
      // Log é melhor esforço: nunca pode derrubar o app.
    }
  }
}
