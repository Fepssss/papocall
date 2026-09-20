import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/models/user_model.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/services/direct_crypto.dart';
import 'package:papocall/widgets/direct_chat_view.dart';

import 'app_sandbox.dart';

/// A tela de conversa privada: o que ela promete tem de ser o que o estado da
/// malha permite, nem mais nem menos.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  late SimpleKeyPair parDoAmigo;
  late String publicaDoAmigo;

  setUp(() async {
    parDoAmigo = await X25519().newKeyPair();
    publicaDoAmigo = base64Encode((await parDoAmigo.extract()).publicKey.bytes);
  });

  AppState aplicativo() => AppState()
    ..currentUser = UserModel(id: 'user-eu', username: 'feps', displayName: 'Feps')
    ..friends.add(UserModel(id: 'user-amigo', username: 'victor', displayName: 'Victor'));

  void presenca(AppState state, {bool online = true}) {
    state.isNetworkOnline = true;
    state.processFriendPresencePayload({
      'action': 'user_presence',
      'userId': 'user-amigo',
      'username': 'victor',
      'displayName': 'Victor',
      'status': online ? 'online' : 'offline',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'dmPub': publicaDoAmigo,
    });
  }

  Future<AppState> montar(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 720,
                height: 640,
                child: DirectChatSection(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> entregarMensagem(AppState state, String texto) async {
    final bruto = await DirectCrypto.cifrar(
      minha: parDoAmigo,
      de: 'victor',
      para: 'feps',
      publicaDoParB64: await DirectCrypto.chavePublicaAtual(),
      conteudo: {
        'id': 'msg-${texto.hashCode}',
        'texto': texto,
        'enviadoEm': DateTime.now().millisecondsSinceEpoch,
      },
    );
    await state.processInboxPayload({'action': 'dm', 'envelope': bruto});
  }

  /// O caminho da conversa grava histórico em disco de verdade, e a zona de
  /// teste fake-async não bombeia a fila real: sem isto, o `await` do
  /// `_saveChatHistory()` não completa e o teste para de andar.
  Future<void> discoDeVerdade(WidgetTester tester, Future<void> Function() acao) async {
    await tester.runAsync(acao);
  }

  testWidgets('sem conversa aberta mostra o caminho para começar uma', (tester) async {
    await montar(tester, aplicativo());

    expect(find.textContaining('Nenhuma conversa privada ainda.'), findsOneWidget);
    expect(find.textContaining('Mensagem'), findsWidgets);
  });

  testWidgets('contato offline bloqueia o campo e explica o motivo', (tester) async {
    final state = aplicativo();
    presenca(state, online: false);
    state.openDirectChat('user-amigo');

    await montar(tester, state);

    expect(
      find.textContaining('está offline. A conversa privada acontece com os dois on-line'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    final botao = find
        .ancestor(of: find.byIcon(Icons.send_rounded), matching: find.byType(IconButton))
        .first;
    expect(tester.widget<IconButton>(botao).onPressed, isNull);
  });

  testWidgets('mensagem recebida aparece na conversa com a impressão da chave',
      (tester) async {
    final state = aplicativo();
    presenca(state);
    state.openDirectChat('user-amigo');
    await discoDeVerdade(tester, () => entregarMensagem(state, 'chegou do outro lado'));
    await montar(tester, state);

    expect(find.text('chegou do outro lado'), findsOneWidget);
    expect(find.textContaining('Cifrada ponta a ponta.'), findsOneWidget);
    expect(find.textContaining(DirectCrypto.impressao(publicaDoAmigo)), findsOneWidget);
  });

  testWidgets('voltar fecha a conversa e devolve a lista', (tester) async {
    final state = aplicativo();
    presenca(state);
    state.openDirectChat('user-amigo');
    await discoDeVerdade(tester, () => entregarMensagem(state, 'oi de novo'));
    await montar(tester, state);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(state.activeDirectPeer, isNull);
    expect(find.text('Victor'), findsOneWidget);
    expect(find.text('oi de novo'), findsOneWidget);
  });

  testWidgets('envio recusado pela malha devolve o texto digitado ao usuário',
      (tester) async {
    final state = aplicativo();
    presenca(state);
    state.openDirectChat('user-amigo');
    await montar(tester, state);

    await discoDeVerdade(tester, () async {
      await tester.enterText(find.byType(TextField), 'oi, você está aí?');
      await tester.tap(find.byIcon(Icons.send_rounded));
      // O envio faz PBKDF2 e escreve no disco, e essa fila só anda dentro do
      // runAsync. Esperar a mensagem entrar e ser retirada da lista é o que dá
      // a certeza de que a recusa aconteceu, em vez de apostar num tempo.
      var apareceu = false;
      for (var i = 0; i < 200; i++) {
        final naLista = state.directMessages('user-amigo').isNotEmpty;
        if (naLista) apareceu = true;
        if (apareceu && !naLista) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      // A recusa volta para a tela um tick depois de a mensagem sair da lista.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    // O broker deste teste nunca conectou: a mensagem não saiu, e a tela tem de
    // dizer isso em vez de deixar o balão verde pendurado.
    expect(state.directMessages('user-amigo'), isEmpty);
    expect(find.textContaining('A mensagem não saiu'), findsOneWidget);
    expect(find.text('oi, você está aí?'), findsOneWidget);
  });
}
