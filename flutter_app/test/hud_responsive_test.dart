import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/main.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/role.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/models/user_model.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/widgets/app_left_panel.dart';
import 'package:papocall/widgets/channels_sidebar.dart';

import 'app_sandbox.dart';

/// A HUD tem de acompanhar a janela em vez de cortar linha por linha.
///
/// O aplicativo já abre em janela mínima de 960x600, mas isso só vale se cada
/// tela couber em cada largura: abaixo da largura de projeto a interface cede
/// texto e colunas juntas, acima dela ela fica exatamente no tamanho desenhado.
/// Estas montagens percorrem as resoluções reais (da mínima às 2K) com nomes
/// propositadamente longos: qualquer [RenderFlex] estourado vira exceção
/// capturada pelo `takeException`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  const nomesLongos = 'Vitoria Albuquerque-Conselheiro';

  Server servidor() => Server(
        id: 'srv-hud',
        name: 'Servidor de Testes da Hud',
        inviteCode: '',
        ownerId: 'eu',
        memberIds: ['eu'],
        roles: ServerRole.defaults(),
        channels: [
          Channel(
            id: 'c-texto',
            name: 'estrategia-e-planejamento-de-sprint',
            type: ChannelType.text,
            topic: 'Topico longo do canal para ver se a barra de cima cede o espaço',
          ),
          Channel(id: 'c-voz', name: 'Sala Alfa', type: ChannelType.voice),
        ],
      );

  AppState aplicativo({bool naVoz = false, bool naHome = false}) {
    final state = AppState()
      ..isCheckingAuth = false
      ..isAuthenticated = true
      ..currentUser = UserModel(id: 'eu', username: 'feps', displayName: nomesLongos)
      ..servers.add(servidor())
      ..activeServerId = 'srv-hud';
    if (naHome) return state..isHomePageActive = true;
    state.isHomePageActive = false;
    state.activeChannelId = naVoz ? 'c-voz' : 'c-texto';
    if (naVoz) state.connectedVoiceChannelId = 'c-voz';
    return state;
  }

  /// O tamanho da janela tem de chegar ao [MediaQuery], não só à superfície de
  /// pintura: é pela largura lógica que a HUD decide quanto escalar.
  void janela(WidgetTester tester, Size tamanho) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = tamanho;
    addTearDown(tester.view.reset);
  }

  Future<AppState> montar(WidgetTester tester, AppState state, Size tamanho) async {
    janela(tester, tamanho);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const PapoCallApp(),
      ),
    );
    // pumpAndSettle não serve: a faixa de reconexão tem um girador que nunca
    // para de girar. Basta assentar a árvore com alguns quadros.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return state;
  }

  // As fontes dos testes (Ahem) são quase o dobro de largura da Segoe UI real,
  // então o que passa aqui em 1280 tem folga de sobra no aplicativo.
  final resolucoes = <String, Size>{
    'na janela mínima (960x600)': const Size(960, 600),
    'na janela de projeto (1280x800)': const Size(1280, 800),
    'em Full HD (1920x1080)': const Size(1920, 1080),
    'em 2K (2560x1440)': const Size(2560, 1440),
  };

  for (final entrada in resolucoes.entries) {
    testWidgets('o chat se acomoda ${entrada.key}', (tester) async {
      await montar(tester, aplicativo(), entrada.value);
      expect(tester.takeException(), isNull);
      expect(find.byType(ChannelsSidebar), findsOneWidget);
    });
  }

  for (final entrada in resolucoes.entries) {
    testWidgets('a sala de voz se acomoda ${entrada.key}', (tester) async {
      await montar(tester, aplicativo(naVoz: true), entrada.value);
      expect(tester.takeException(), isNull);
    });
  }

  for (final entrada in resolucoes.entries) {
    testWidgets('a tela inicial se acomoda ${entrada.key}', (tester) async {
      await montar(tester, aplicativo(naHome: true), entrada.value);
      expect(tester.takeException(), isNull);
    });
  }

  Future<void> redimensionar(WidgetTester tester, Size tamanho) async {
    janela(tester, tamanho);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('a barra de membros cede lugar na janela estreita e volta na larga',
      (tester) async {
    final state = aplicativo();
    await montar(tester, state, const Size(1000, 700));
    expect(find.byType(ChannelsSidebar), findsOneWidget);
    expect(find.textContaining('DISPONÍVEL'), findsNothing);

    await redimensionar(tester, const Size(1600, 900));
    expect(find.textContaining('DISPONÍVEL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o painel esquerdo encolhe na janela estreita e para no tamanho desenhado',
      (tester) async {
    final state = aplicativo();

    await montar(tester, state, const Size(960, 600));
    final estreito = tester.getSize(find.byType(AppLeftPanel));
    final escalaEstreita = MediaQuery.of(tester.element(find.byType(AppLeftPanel))).textScaler;

    await redimensionar(tester, const Size(2560, 1440));
    final largo = tester.getSize(find.byType(AppLeftPanel));
    final escalaLarga = MediaQuery.of(tester.element(find.byType(AppLeftPanel))).textScaler;

    // O tamanho de projeto é um teto, não um ponto de partida: numa janela
    // grande a pessoa vê a HUD do jeito que ela foi desenhada, e não 30% maior.
    expect(largo.width, 312);
    expect(escalaLarga.scale(100), 100);
    expect(estreito.width, lessThan(largo.width));
    expect(escalaEstreita.scale(100), lessThan(escalaLarga.scale(100)));
  });
}
