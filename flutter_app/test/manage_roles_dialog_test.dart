import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/role.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/models/user_model.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/widgets/modals/manage_roles_dialog.dart';

import 'app_sandbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  Server buildServer() => Server(
        id: 'srv-dlg',
        name: 'Servidor de Cargos',
        inviteCode: '',
        ownerId: 'dono',
        memberIds: ['dono', 'convidado'],
        roles: ServerRole.defaults(),
        channels: [
          Channel(id: 'c-1', name: 'geral', type: ChannelType.text),
        ],
      );

  Future<AppState> abrirDialogo(WidgetTester tester, String quemAbre) async {
    final srv = buildServer();
    final state = AppState()
      ..currentUser = UserModel(id: quemAbre, username: quemAbre)
      ..servers.add(srv)
      ..activeServerId = srv.id;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: ManageRolesDialog(server: srv),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('Dono vê os cargos padrão e pode criar um novo', (tester) async {
    await abrirDialogo(tester, 'dono');

    // O cargo selecionado aparece na lista e no campo de nome do editor.
    expect(find.text('Administrador'), findsAtLeastNWidgets(1));
    expect(find.text('Moderador'), findsOneWidget);
    expect(find.text('Novo cargo'), findsOneWidget);
    expect(find.text('Somente leitura'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('membro sem Gerenciar cargos abre em leitura', (tester) async {
    await abrirDialogo(tester, 'convidado');

    expect(find.text('Somente leitura'), findsOneWidget);
    expect(find.text('Novo cargo'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moderador com o poder edita só cargos mais fracos que o dele',
      (tester) async {
    final srv = buildServer();
    srv.memberRoles['convidado'] = 'role-mod';
    final state = AppState()
      ..currentUser = UserModel(id: 'convidado', username: 'convidado')
      ..servers.add(srv)
      ..activeServerId = srv.id;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(home: Scaffold(body: ManageRolesDialog(server: srv))),
      ),
    );
    await tester.pumpAndSettle();

    // Moderador não tem 'gerenciar_cargos', então a tela dele é de leitura.
    expect(find.text('Somente leitura'), findsOneWidget);
    expect(state.canEditRole('srv-dlg', 'role-mod'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('as cinco permissões aparecem na lista do cargo', (tester) async {
    await abrirDialogo(tester, 'dono');

    // O editor é uma lista rolável: as últimas permissões só entram na árvore
    // quando se rola até elas.
    final editor = find.byType(ListView).at(1);
    for (final permissao in Permissions.all) {
      await tester.dragUntilVisible(
        find.text(permissao.label),
        editor,
        const Offset(0, -60),
        maxIteration: 12,
      );
      expect(find.text(permissao.label), findsOneWidget, reason: permissao.key);
    }
  });
}
