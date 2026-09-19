import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/providers/app_state.dart';

/// Isola os testes de escrita no diretório temporário do sistema.
///
/// Sem isso basta um `AppState()` numa suíte para a aplicação sobrescrever o
/// `servers.json`, o `settings.json` e as marcas de leitura reais desta máquina
/// — e para o teste abrir conexão MQTT de verdade e ler a sessão gravada.
/// Com a raiz redirecionada, o construtor também não inicializa a rede.
void useAppDataSandbox() {
  late Directory raiz;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('papocall-teste');
    AppState.dataRootOverride = raiz.path;
  });

  tearDown(() {
    AppState.dataRootOverride = null;
    try {
      if (raiz.existsSync()) raiz.deleteSync(recursive: true);
    } on FileSystemException {
      // O Windows às vezes segura o arquivo recém-escrito. É dado de teste no
      // diretório temporário: o próprio sistema o descarta.
    }
  });
}
