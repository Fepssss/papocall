import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/role.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/models/user_model.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/widgets/channels_sidebar.dart';

import 'app_sandbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  Server buildServer() => Server(
        id: 'srv-canais',
        name: 'Servidor',
        inviteCode: '',
        ownerId: 'dono',
        memberIds: ['dono'],
        roles: ServerRole.defaults(),
        channels: [
          Channel(id: 'c-texto', name: 'geral', type: ChannelType.text),
          Channel(id: 'c-voz', name: 'Sala de Voz', type: ChannelType.voice),
        ],
      );

  Future<AppState> montar(WidgetTester tester, Server srv, String quemAbre) async {
    final state = AppState()
      ..currentUser = UserModel(id: quemAbre, username: quemAbre)
      ..servers.add(srv)
      ..activeServerId = srv.id;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 320, child: ChannelsSidebar())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  /// A linha do canal é o GestureDetector mais próximo do nome; a lixeira é
  /// filha dela, então é dentro dela que se procura.
  bool lixeiraVisivel(WidgetTester tester, String nome) {
    final linha = find
        .ancestor(of: find.text(nome), matching: find.byType(GestureDetector))
        .first;
    return find
        .descendant(of: linha, matching: find.byIcon(Icons.delete_outline_rounded))
        .evaluate()
        .isNotEmpty;
  }

  /// MouseRegion só reage a um ponteiro de mouse de verdade; um toque não
  /// conta como hover.
  Future<void> passarMouse(WidgetTester tester, Finder alvo) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(alvo));
    await tester.pumpAndSettle();
  }

  testWidgets('canal de texto mostra a lixeira ao passar o mouse', (tester) async {
    await montar(tester, buildServer(), 'dono');

    expect(lixeiraVisivel(tester, 'geral'), isFalse);
    await passarMouse(tester, find.text('geral'));

    expect(lixeiraVisivel(tester, 'geral'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sala de voz não ganha lixeira no hover', (tester) async {
    await montar(tester, buildServer(), 'dono');

    await passarMouse(tester, find.text('Sala de Voz'));

    expect(lixeiraVisivel(tester, 'Sala de Voz'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('botão direito na sala de voz abre o apagar canal', (tester) async {
    await montar(tester, buildServer(), 'dono');

    await tester.tap(find.text('Sala de Voz'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Apagar canal'), findsOneWidget);

    await tester.tap(find.text('Apagar canal'));
    await tester.pumpAndSettle();

    // A confirmação nomeia a sala sem o '#' de canal de texto.
    expect(find.text('Apagar "Sala de Voz"'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quem não gerencia canais não ganha menu', (tester) async {
    await montar(tester, buildServer(), 'visitante');

    await tester.tap(find.text('Sala de Voz'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Apagar canal'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
