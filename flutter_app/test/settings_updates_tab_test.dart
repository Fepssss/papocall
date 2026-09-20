import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/services/update_service.dart';
import 'package:papocall/utils/app_version.dart';
import 'package:papocall/widgets/modals/settings_modal.dart';

import 'app_sandbox.dart';

UpdateManifest _manifesto({String versao = '99.0.0'}) {
  return UpdateManifest(
    version: AppVersion.tryParse(versao)!,
    url: Uri.parse('https://papocall.vercel.app/downloads/PapoCall-Setup.exe'),
    sha256: 'a' * 64,
    notes: 'Novidades desta versão.',
  );
}

Future<AppState> _abrir(
  WidgetTester tester, {
  UpdateManifest? disponivel,
  String? erro,
}) async {
  final state = AppState()
    ..atualizacaoDisponivel = disponivel
    ..erroAoVerificarAtualizacao = erro
    ..atualizacoesConferidas = disponivel == null && erro == null;

  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(
        home: SettingsModal(initialTab: SettingsTab.updates),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  testWidgets('a aba de atualizações mostra a versão real e conferir de novo',
      (tester) async {
    await _abrir(tester);

    expect(find.text('Versão instalada: ${AppVersion.atual}'), findsOneWidget);
    expect(find.text('Você está na versão mais recente.'), findsOneWidget);
    expect(find.text('Verificar agora'), findsOneWidget);
    // Sem novidade no servidor não existe botão de instalar esperando clique.
    expect(find.textContaining('Atualizar para'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existe atualização: a aba diz qual é e libera o instalar',
      (tester) async {
    await _abrir(tester, disponivel: _manifesto());

    expect(find.text('Versão 99.0.0 pronta para instalar.'), findsOneWidget);
    expect(find.text('Novidades desta versão.'), findsOneWidget);
    final botao = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.textContaining('Atualizar para 99.0.0'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(botao.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a checagem falhou: a aba admite a falha em vez de dizer que está em dia',
      (tester) async {
    await _abrir(tester, erro: 'O servidor de atualizações não respondeu a tempo.');

    expect(find.text('O servidor de atualizações não respondeu a tempo.'),
        findsOneWidget);
    expect(find.text('Você está na versão mais recente.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('em chamada de voz o instalar fica bloqueado, e a razão aparece',
      (tester) async {
    final state = await _abrir(tester, disponivel: _manifesto());
    state.connectedVoiceChannelId = 'canal-de-teste';
    state.notifyListeners();
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Saia da chamada de voz para atualizar'),
      findsOneWidget,
    );
    final botao = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.textContaining('Atualizar para 99.0.0'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(botao.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
