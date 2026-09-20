import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';

/// Log de diagnóstico em `%APPDATA%\PapoCall\papocall.log`.
///
/// Existe porque as falhas de sessão e de voz eram silenciosas: o usuário só
/// via um botão que não fazia nada. Nunca gravar segredos aqui — somente
/// códigos, status HTTP, expirações e caminhos.
///
/// A escrita é acumulada num `IOSink` aberto uma única vez e escoado a cada dois
/// segundos. Antes era `writeAsStringSync(flush: true)` por linha: cada mudança
/// de fala, cada track assinada e cada heartbeat de presença abria, escrevia e
/// fechava o arquivo no isolate da interface — era isso que travava a janela no
/// meio de uma chamada.
class AppLog {
  /// Passou disto, a primeira linha do dia descarta o começo do arquivo. O log
  /// serve para entender o que está acontecendo agora, não para arquivar semanas.
  static const int _tetoBytes = 512 * 1024;

  /// Quanto manter ao podar: dá para ver o que veio antes da última abertura.
  static const int _manterBytes = 192 * 1024;

  static bool get _emTeste =>
      Platform.environment.containsKey('FLUTTER_TEST');

  static IOSink? _sink;
  static Timer? _escoador;
  static bool _sujo = false;

  static void write(String tag, String message) {
    if (_emTeste) return;
    final linha = '[${DateTime.now().toIso8601String()}] [$tag] $message\n';
    try {
      _sink ??= _abrir();
      _sink!.write(linha);
      _sujo = true;
      _escoador ??= Timer(const Duration(seconds: 2), _escoar);
    } catch (e) {
      // Log é melhor esforço: nunca pode derrubar o app.
      debugPrint('[$tag] $message (log indisponível: $e)');
    }
  }

  static IOSink _abrir() {
    final arquivo = AppPaths.file('papocall.log');
    _podar(arquivo);
    return arquivo.openWrite(mode: FileMode.append, encoding: utf8);
  }

  static void _podar(File arquivo) {
    try {
      if (!arquivo.existsSync()) return;
      if (arquivo.lengthSync() <= _tetoBytes) return;
      final conteudo = arquivo.readAsStringSync();
      var corte = conteudo.length - _manterBytes;
      // Começar no meio de uma linha deixaria a primeira entrada ilegível.
      final quebra = conteudo.indexOf('\n', corte);
      if (quebra != -1 && quebra + 1 < conteudo.length) corte = quebra + 1;
      arquivo.writeAsStringSync(
        conteudo.substring(corte),
        mode: FileMode.write,
        encoding: utf8,
      );
    } catch (_) {}
  }

  static void _escoar() {
    _escoador = null;
    final sink = _sink;
    if (sink == null || !_sujo) return;
    _sujo = false;
    unawaited(sink.flush().catchError((Object _) {}));
  }

  /// Escorre o que está em memória antes de um `exit()`: o processo morre e o
  /// buffer do sink morre junto com ele.
  static Future<void> encerrar() async {
    _escoador?.cancel();
    _escoador = null;
    final sink = _sink;
    _sink = null;
    _sujo = false;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {}
  }
}
