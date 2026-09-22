import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/chat_message.dart';
import 'package:papocall/models/role.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/models/user_model.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/widgets/chat_view.dart';

import 'app_sandbox.dart';

/// Onde o canal abre.
///
/// Abrir no começo era perder 200 mensagens de história para baixo, e abrir no
/// fim era pular a conversa que chegou enquanto a pessoa estava fora. O meio
/// termo é a marca de leitura: a primeira mensagem ainda não vista fica no topo
/// da tela, e sem nada novo o lugar certo é o pé da conversa.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  Server servidor() => Server(
        id: 'srv-chat',
        name: 'Squad',
        inviteCode: '',
        ownerId: 'eu',
        memberIds: ['eu'],
        roles: ServerRole.defaults(),
        channels: [
          Channel(id: 'c-texto', name: 'geral', type: ChannelType.text),
          Channel(id: 'c-fora', name: 'aviso', type: ChannelType.text),
        ],
      );

  /// Manda [quantidade] mensagens para o canal de texto, todas com o carimbo a
  /// partir de [de] — a marca de leitura é o relógio de verdade, então o que tem
  /// de parecer "chegou depois" precisa ter `sentAt` maior que ele.
  void injeta(AppState state, Server srv, int quantidade, int de, {String rotulo = ''}) {
    for (var i = 0; i < quantidade; i++) {
      state.processNetworkPayload({
        'action': 'chat_message',
        'channelId': 'c-texto',
        'channelName': 'geral',
        'channelType': 'text',
        'serverId': srv.id,
        'message': ChatMessage(
          id: 'm$rotulo$i',
          authorId: 'amigo',
          author: 'Amigo',
          text: 'mensagem $rotulo$i',
          timestamp: 'agora',
          sentAt: de + i,
        ).toJson(),
      }, srv);
    }
  }

  AppState aplicativo(Server srv) => AppState()
    ..isCheckingAuth = false
    ..isAuthenticated = true
    ..currentUser = UserModel(id: 'eu', username: 'feps', displayName: 'Feps')
    ..servers.add(srv)
    ..activeServerId = srv.id;

  Future<void> montar(WidgetTester tester, AppState state) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: Column(children: [ChatView()])),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// As mensagens acumuladas ligam a gravação adiada em disco e a republicação
  /// do retrato de histórico. O retrato não sai do sandbox (sem código de
  /// convite não para onde publicar), mas os dois relógios precisam se vencer
  /// antes de o teste terminar.
  Future<void> vencerOsRelogios(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
  }

  testWidgets('com mensagem nova, o canal abre na primeira ainda não vista', (tester) async {
    final srv = servidor();
    final state = aplicativo(srv);
    final agora = DateTime.now().millisecondsSinceEpoch;

    injeta(state, srv, 40, agora - 400000);
    state.selectChannel('c-texto');
    injeta(state, srv, 15, agora + 5000, rotulo: 'nova ');
    state.selectChannel('c-fora');
    state.selectChannel('c-texto');

    await montar(tester, state);

    expect(find.text('mensagem nova 0'), findsOneWidget);
    expect(tester.getTopLeft(find.text('mensagem nova 0')).dy, greaterThan(0));
    expect(tester.getTopLeft(find.text('mensagem nova 0')).dy, lessThan(220));
    // O começo da conversa não é mais o que a pessoa vê ao abrir.
    expect(find.text('mensagem 3'), findsNothing);
    // E o fim da conversa também não: a marca fica onde foi posta. O bloco da
    // marca é montado inteiro (é ele que encosta no pé da tela quando é curto),
    // então aqui o que diz "fora da tela" é a geometria, não a existência.
    expect(tester.getBottomLeft(find.text('mensagem nova 14')).dy,
        greaterThan(700));
    expect(tester.takeException(), isNull);
    await vencerOsRelogios(tester);
  });

  testWidgets('sem nada novo, o canal abre na última mensagem', (tester) async {
    final srv = servidor();
    final state = aplicativo(srv);
    final agora = DateTime.now().millisecondsSinceEpoch;

    injeta(state, srv, 40, agora - 400000);
    state.selectChannel('c-texto');
    state.selectChannel('c-fora');
    state.selectChannel('c-texto');

    await montar(tester, state);

    final ultima = find.text('mensagem 39');
    expect(ultima, findsOneWidget);
    expect(tester.getBottomLeft(ultima).dy, lessThanOrEqualTo(700));
    expect(find.text('mensagem 2'), findsNothing);
    expect(tester.takeException(), isNull);
    await vencerOsRelogios(tester);
  });

  testWidgets('a marca é resolvida uma vez por canal e não persegue a lista',
      (tester) async {
    final srv = servidor();
    final state = aplicativo(srv);
    final agora = DateTime.now().millisecondsSinceEpoch;

    injeta(state, srv, 40, agora - 400000);
    state.selectChannel('c-texto');
    injeta(state, srv, 15, agora + 5000, rotulo: 'nova ');
    state.selectChannel('c-fora');
    state.selectChannel('c-texto');
    await montar(tester, state);

    final antes = tester.getTopLeft(find.text('mensagem nova 0')).dy;
    // Reler a marca do canal ativo não pode reposicionar a conversa.
    state.selectChannel('c-texto');
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.getTopLeft(find.text('mensagem nova 0')).dy, antes);
    await vencerOsRelogios(tester);
  });

  /// O que o usuário viu: depois da última mensagem ainda dava para rolar, e a
  /// tela ia parar vazia. O fim da conversa tem de ser o limite da rolagem —
  /// com mensagem nova ou sem — e isso é a geometria da lista que garante, não
  /// um pulo de scroll calculado depois do quadro pintado.
  ScrollPosition _rolagem(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  testWidgets('sem nada novo não existe rolagem depois da última mensagem', (tester) async {
    final srv = servidor();
    final state = aplicativo(srv);
    injeta(state, srv, 40, DateTime.now().millisecondsSinceEpoch - 400000);
    state.selectChannel('c-texto');
    state.selectChannel('c-fora');
    state.selectChannel('c-texto');
    await montar(tester, state);

    expect(_rolagem(tester).maxScrollExtent, 0);
    expect(
      tester.getBottomLeft(find.text('mensagem 39')).dy,
      greaterThan(tester.getBottomLeft(find.byType(CustomScrollView)).dy - 40),
    );
    await vencerOsRelogios(tester);
  });

  testWidgets('com três novas não existe rolagem depois da última mensagem', (tester) async {
    final srv = servidor();
    final state = aplicativo(srv);
    final agora = DateTime.now().millisecondsSinceEpoch;
    injeta(state, srv, 40, agora - 400000);
    state.selectChannel('c-texto');
    injeta(state, srv, 3, agora + 5000, rotulo: 'nova ');
    state.selectChannel('c-fora');
    state.selectChannel('c-texto');
    await montar(tester, state);

    final pos = _rolagem(tester);
    expect(pos.maxScrollExtent, 0);
    expect(pos.pixels, 0);
    // Arrastar para baixo não tem para onde ir: o fim é o fim.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(_rolagem(tester).pixels, 0);
    expect(find.text('mensagem nova 2'), findsOneWidget);
    await vencerOsRelogios(tester);
  });
}
