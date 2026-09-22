import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/models/user_model.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/widgets/home_page_view.dart';

import 'app_sandbox.dart';

/// A porta de entrada das conversas privadas dentro da tela de amigos: a aba
/// nova e o botão de cada contato precisam levar à conversa, não a um beco.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  late String publicaDoAmigo;

  setUp(() async {
    final par = await X25519().newKeyPair();
    publicaDoAmigo = base64Encode((await par.extract()).publicKey.bytes);
  });

  AppState aplicativo() => AppState()
    ..currentUser = UserModel(id: 'user-eu', username: 'feps', displayName: 'Feps')
    ..friends.add(UserModel(id: 'user-amigo', username: 'victor', displayName: 'Victor'));

  /// Chegada da presença do amigo: é por ela que a chave pública dele chega.
  void presenca(AppState state) {
    state.isNetworkOnline = true;
    state.processFriendPresencePayload({
      'action': 'user_presence',
      'userId': 'user-amigo',
      'username': 'victor',
      'displayName': 'Victor',
      'status': 'online',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'dmPub': publicaDoAmigo,
    });
  }

  Future<AppState> montar(WidgetTester tester, AppState state) async {
    // A fonte de teste (Ahem) é muito mais larga que a real: numa janela de
    // 800px as barras do HUD estourariam o layout por motivos que não existem
    // no aplicativo.
    await tester.binding.setSurfaceSize(const Size(2600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: HomePageView(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('a aba Conversas abre a central de conversas privadas', (tester) async {
    final state = aplicativo();
    presenca(state);
    await montar(tester, state);

    expect(find.textContaining('Nenhuma conversa privada ainda.'), findsNothing);

    await tester.tap(find.text('Conversas'));
    await tester.pumpAndSettle();

    expect(find.text('CONVERSAS PRIVADAS (0)'), findsOneWidget);
    expect(find.text('Cifradas entre os dois aparelhos'), findsOneWidget);
    expect(find.textContaining('Nenhuma conversa privada ainda.'), findsOneWidget);
    // A barra de busca é de amigos; na lista de conversas ela seria um campo
    // que não filtra nada.
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o botão de mensagem de um contato abre a conversa dele', (tester) async {
    final state = aplicativo();
    presenca(state);
    await montar(tester, state);

    final botao = find.byTooltip('Mensagem privada');
    await tester.ensureVisible(botao);
    await tester.pumpAndSettle();
    await tester.tap(botao);
    await tester.pumpAndSettle();

    expect(state.activeDirectPeerId, 'user-amigo');
    expect(find.text('Victor'), findsWidgets);
    expect(find.textContaining('Cifrada ponta a ponta.'), findsOneWidget);
    expect(find.textContaining(publicaDoAmigo.substring(0, 8)), findsNothing);
    // Campo ativo: os dois estão na malha e a chave do amigo chegou.
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('as linhas da página de amigos têm onde pintar o hover', (tester) async {
    final state = aplicativo();
    presenca(state);
    await montar(tester, state);

    // O fundo da página é um Container de cor opaca, e um InkWell pinta a tinta
    // no Material mais próximo *acima* dele. Sem o Material transparente, o
    // hover ia parar atrás da cor da página e a lista não reagiria ao mouse —
    // exatamente o que foi reclamado.
    expect(
      find.ancestor(
        of: find.text('Victor').first,
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.type == MaterialType.transparency,
        ),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });
}
