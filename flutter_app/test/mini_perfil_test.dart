import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/role.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/models/user_model.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/widgets/member_profile_card.dart';

import 'app_sandbox.dart';

/// O cartão que abre no clique sobre alguém da lista de membros.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  Server servidor() => Server(
        id: 'srv-perfil',
        name: 'Servidor de Teste',
        inviteCode: '',
        ownerId: 'dono',
        memberIds: ['eu', 'dono', 'alvo'],
        roles: ServerRole.defaults(),
        channels: [
          Channel(id: 'c-1', name: 'geral', type: ChannelType.text),
        ],
      );

  Future<AppState> abrirCartao(
    WidgetTester tester, {
    required String quem,
    bool euSouAmigo = false,
  }) async {
    final srv = servidor();
    final state = AppState()
      ..currentUser = UserModel(id: 'eu', username: 'eu', displayName: 'Quem Olha')
      ..servers.add(srv)
      ..activeServerId = srv.id;
    if (euSouAmigo) {
      state.friends.add(UserModel(id: quem, username: quem, displayName: 'Amigo Alvo'));
    }

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => MemberProfileCard.show(
                    context,
                    srv,
                    UserModel(id: quem, username: quem, displayName: 'Amigo Alvo'),
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

  testWidgets('o cartão mostra quem a pessoa é, e só o que existe', (tester) async {
    await abrirCartao(tester, quem: 'alvo');

    expect(find.text('Amigo Alvo'), findsOneWidget);
    expect(find.text('@alvo'), findsOneWidget);
    // Amigos em comum e biografia não existem no modelo: não têm o que mostrar.
    expect(find.textContaining('amigos mútuos'), findsNothing);
    expect(find.textContaining('Biografia'), findsNothing);
  });

  testWidgets('quem não é amigo recebe o convite, não o botão de mensagem',
      (tester) async {
    await abrirCartao(tester, quem: 'alvo');
    expect(find.text('Adicionar amigo'), findsOneWidget);
    expect(find.text('Mensagem direta'), findsNothing);
  });

  testWidgets('amigo vê os dois caminhos: conversar e remover a amizade',
      (tester) async {
    await abrirCartao(tester, quem: 'alvo', euSouAmigo: true);
    expect(find.text('Mensagem direta'), findsOneWidget);
    expect(find.text('Remover amigo'), findsOneWidget);
    expect(find.text('Adicionar amigo'), findsNothing);
  });

  testWidgets('o dono do servidor aparece marcado como dono', (tester) async {
    await abrirCartao(tester, quem: 'dono');
    expect(find.text('Dono'), findsOneWidget);
  });

  testWidgets('sem permissão de gestão não aparece o atalho de gerenciar',
      (tester) async {
    await abrirCartao(tester, quem: 'alvo');
    expect(find.text('Gerenciar membro'), findsNothing);
  });

  testWidgets('a própria pessoa não ganha ações sobre si mesma', (tester) async {
    await abrirCartao(tester, quem: 'eu');
    expect(find.text('Adicionar amigo'), findsNothing);
    expect(find.text('Mensagem direta'), findsNothing);
    expect(find.text('Gerenciar membro'), findsNothing);
  });
}
