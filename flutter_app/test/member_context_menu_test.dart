import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/role.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/models/user_model.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/widgets/member_context_menu.dart';

import 'app_sandbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  Server buildServer() => Server(
        id: 'srv-mem',
        name: 'Servidor',
        inviteCode: '',
        ownerId: 'dono',
        memberIds: ['dono', 'alvo'],
        roles: ServerRole.defaults(),
        channels: [
          Channel(id: 'c-1', name: 'geral', type: ChannelType.text),
        ],
      );

  Future<AppState> abrirMenu(WidgetTester tester, Server srv, String quemAbre) async {
    final state = AppState()
      ..currentUser = UserModel(id: quemAbre, username: quemAbre)
      ..servers.add(srv)
      ..activeServerId = srv.id;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => MemberContextMenu.show(
                    context,
                    srv,
                    UserModel(id: 'alvo', username: 'alvo'),
                    const Offset(120, 120),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('Dono vê cargos e expulsão ao clicar num membro', (tester) async {
    await abrirMenu(tester, buildServer(), 'dono');

    expect(find.text('CARGO DO MEMBRO'), findsOneWidget);
    expect(find.text('Nenhum (Membro)'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('Expulsar do servidor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('membro sem poder nenhum não ganha menu vazio', (tester) async {
    await abrirMenu(tester, buildServer(), 'observador');

    expect(find.text('CARGO DO MEMBRO'), findsNothing);
    expect(find.text('Expulsar do servidor'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Moderador sem Gerenciar cargos só vê a expulsão', (tester) async {
    final srv = buildServer();
    srv.memberRoles['dono-que-abre'] = 'role-mod';
    await abrirMenu(tester, srv, 'dono-que-abre');

    expect(find.text('CARGO DO MEMBRO'), findsNothing);
    expect(find.text('Expulsar do servidor'), findsOneWidget);
  });

  testWidgets('cargo mais poderoso que o meu aparece desabilitado', (tester) async {
    final srv = buildServer();
    // Gerente tem Gerenciar cargos, mas não o poder inteiro do Administrador.
    srv.roles.add(ServerRole(
      id: 'r-gerente',
      name: 'Gerente',
      colorHex: '8B5CF6',
      permissions: {Permissions.manageRoles},
    ));
    srv.memberRoles['convidado'] = 'r-gerente';
    await abrirMenu(tester, srv, 'convidado');

    expect(find.text('CARGO DO MEMBRO'), findsOneWidget);
    expect(find.text('Expulsar do servidor'), findsNothing);

    final admin = find.text('Administrador');
    expect(admin, findsOneWidget);
    final area = tester.widget<MouseRegion>(
      find.ancestor(of: admin, matching: find.byType(MouseRegion)).last,
    );
    expect(area.cursor, SystemMouseCursors.forbidden); // sem o poder, sem o clique
  });
}
