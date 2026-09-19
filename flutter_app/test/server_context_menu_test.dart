import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/widgets/server_context_menu.dart';
import 'package:papocall/widgets/server_rail.dart';

void main() {
  Server buildServer() => Server(
        id: 'srv-menu',
        name: 'Servidor de Teste',
        inviteCode: 'papo-teste',
        ownerId: 'dono-1',
        channels: [
          Channel(id: 'canal-1', name: 'geral', type: ChannelType.text),
          Channel(id: 'canal-2', name: 'jogos', type: ChannelType.text),
        ],
      );

  Future<AppState> pumpRail(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: ServerRail()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> rightClickOnIcon(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Servidor de Teste')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('botão direito no ícone abre o menu com as opções reais', (tester) async {
    await pumpRail(tester, AppState()..servers.add(buildServer()));

    await rightClickOnIcon(tester);

    expect(find.text('Marcar como lida'), findsOneWidget);
    expect(find.text('Convidar para o servidor'), findsOneWidget);
    expect(find.text('Silenciar'), findsOneWidget);
    expect(find.text('Config. de notificação'), findsOneWidget);
    expect(find.text('Config. de privacidade'), findsOneWidget);
    // O dono vê "Remover servidor"; quem só participa vê "Sair do servidor".
    expect(find.text('Remover servidor'), findsNothing);
    expect(find.text('Sair do servidor'), findsOneWidget);
  });

  testWidgets('menu cabe inteiro dentro da janela mesmo no canto inferior', (tester) async {
    // A janela de teste é 800x600 e o clique parte do rodapé da barra.
    final state = AppState()..servers.add(buildServer());
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Builder(
                builder: (context) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (_) => ServerContextMenu.show(
                    context,
                    buildServer(),
                    const Offset(780, 590),
                  ),
                  child: const SizedBox(width: 60, height: 60),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(30, 30));
    await tester.pumpAndSettle();

    final header = tester.getRect(find.text('Servidor de Teste'));
    final lastItem = tester.getRect(find.byIcon(Icons.logout_rounded));
    expect(header.left, greaterThanOrEqualTo(0));
    expect(lastItem.right, lessThanOrEqualTo(800));
    expect(lastItem.bottom, lessThanOrEqualTo(600));
    expect(find.text('Sair do servidor'), findsOneWidget);
  });

  testWidgets('Silenciar marca o servidor e some com a marcação ao rever', (tester) async {
    final state = await pumpRail(tester, AppState()..servers.add(buildServer()));

    await rightClickOnIcon(tester);
    await tester.tap(find.text('Silenciar'));
    await tester.pumpAndSettle();

    expect(state.isServerMuted('srv-menu'), isTrue);

    await rightClickOnIcon(tester);
    expect(find.text('Não silenciar'), findsOneWidget);
  });

  testWidgets('Marcar como lida fecha o menu e marca os canais do servidor', (tester) async {
    final state = await pumpRail(tester, AppState()..servers.add(buildServer()));

    await rightClickOnIcon(tester);
    await tester.tap(find.text('Marcar como lida'));
    await tester.pumpAndSettle();

    expect(find.text('Marcar como lida'), findsNothing);
    // Sem mensagens não lidas o contador derivado continua em zero, e a
    // marcação gravada vale para os dois canais do servidor.
    expect(state.mentionCountForServer('srv-menu'), 0);
  });
}
