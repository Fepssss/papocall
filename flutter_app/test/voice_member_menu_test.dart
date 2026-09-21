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

/// O menu do botão direito num participante da chamada de voz, e a regra que
/// decide se um canal de voz é meu.
///
/// A segunda parte é a que corrige o bug: na lista de amigos, o botão de entrar na
/// call era oferecido para qualquer presença em canal de voz — inclusive canal de
/// um servidor em que o usuário não está. Como o nome da sala no LiveKit é o id do
/// canal, oferecer o botão era oferecer a porta. O botão lê exatamente
/// `servidorDoCanal(...)`, então é aí que a regra é testada.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  Server buildServer() => Server(
        id: 'srv-voz',
        name: 'Servidor',
        inviteCode: '',
        ownerId: 'dono',
        memberIds: ['dono', 'alvo'],
        roles: ServerRole.defaults(),
        channels: [
          Channel(id: 'c-texto', name: 'geral', type: ChannelType.text),
          Channel(id: 'c-voz', name: 'Sala de Voz', type: ChannelType.voice),
        ],
      );

  Future<AppState> abrirMenu(
    WidgetTester tester, {
    required Server? servidor,
    required UserModel quemAbre,
    UserModel? alvo,
    List<UserModel> amigos = const [],
  }) async {
    final state = AppState()
      ..currentUser = quemAbre
      ..friends.addAll(amigos);
    if (servidor != null) {
      state.servers.add(servidor);
      state.activeServerId = servidor.id;
    }

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => VoiceMemberMenu.show(
                    context,
                    servidor ?? buildServer(),
                    alvo ?? UserModel(id: 'alvo', username: 'alvo'),
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

  group('menu do participante da chamada de voz', () {
    testWidgets('mostra perfil e mensagem direta para quem já é amigo', (tester) async {
      await abrirMenu(
        tester,
        servidor: buildServer(),
        quemAbre: UserModel(id: 'dono', username: 'dono'),
        amigos: [UserModel(id: 'alvo', username: 'alvo')],
      );

      expect(find.text('Perfil'), findsOneWidget);
      expect(find.text('Mensagem direta'), findsOneWidget);
      expect(find.text('Adicionar amigo'), findsNothing);
    });

    testWidgets('oferece adicionar amigo para quem ainda não é', (tester) async {
      await abrirMenu(
        tester,
        servidor: buildServer(),
        quemAbre: UserModel(id: 'dono', username: 'dono'),
      );

      expect(find.text('Adicionar amigo'), findsOneWidget);
      expect(find.text('Mensagem direta'), findsNothing);
    });

    testWidgets('só quem pode gerenciar membros vê a linha de gestão', (tester) async {
      final srv = buildServer();

      await abrirMenu(
        tester,
        servidor: srv,
        // Dono do servidor: tem todos os poderes por construção.
        quemAbre: UserModel(id: 'dono', username: 'dono'),
      );
      expect(find.text('Gerenciar membro'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());

      await abrirMenu(
        tester,
        servidor: srv,
        // Membro comum, sem 'gerenciar_cargos' nem 'expulsar_membros'.
        quemAbre: UserModel(id: 'visitante', username: 'visitante'),
      );
      expect(find.text('Gerenciar membro'), findsNothing);
    });

    testWidgets('não abre menu sobre a própria pessoa', (tester) async {
      await abrirMenu(
        tester,
        servidor: buildServer(),
        quemAbre: UserModel(id: 'eu', username: 'eu'),
        alvo: UserModel(id: 'eu', username: 'eu'),
      );

      expect(find.text('Perfil'), findsNothing);
    });

    testWidgets('nenhuma linha do menu é decorativa: o que existe hoje é o que aparece',
        (tester) async {
      await abrirMenu(
        tester,
        servidor: buildServer(),
        quemAbre: UserModel(id: 'dono', username: 'dono'),
        amigos: [UserModel(id: 'alvo', username: 'alvo')],
      );

      // Ações que outros programas mostram neste menu e o PapoCall ainda não tem.
      // Se alguém acrescentar uma delas de verdade, tira a linha desta lista e o
      // teste deixa de ser um espelho do que existe.
      for (final inexistente in [
        'Iniciar chamada',
        'Adicionar nota',
        'Adicionar apelido de amigo',
        'Volume do usuário',
        'Silenciar',
        'Silenciar efeitos sonoros',
        'Desativar vídeo',
        'Ver Código de Verificação',
        'Apps',
        'Ignorar',
        'Bloquear',
        'Mover para',
        'Abrir na visualização de moderador',
        'Silenciar voz no servidor',
        'Desativar áudio no servidor',
        'Desconectar',
      ]) {
        expect(find.text(inexistente), findsNothing, reason: '"$inexistente" não tem ação atrás');
      }
    });
  });

  group('canal de voz de servidor alheio', () {
    test('servidorDoCanal só reconhece canal que está nos meus servidores', () {
      final state = AppState()..servers.add(buildServer());

      expect(state.servidorDoCanal('c-voz')?.id, 'srv-voz');
      expect(state.servidorDoCanal('canal-de-outro-servidor'), isNull);
      expect(state.servidorDoCanal(null), isNull);
      expect(state.servidorDoCanal(''), isNull);
    });

    test('connectVoice recusa canal fora dos meus servidores antes de mexer em estado',
        () async {
      final state = AppState()..servers.add(buildServer());

      final erro = await state.connectVoice('canal-de-outro-servidor');

      expect(erro, isNotNull);
      expect(erro, contains('não faz parte'));
      // A recusa tem de acontecer antes de marcar como conectando: se ficasse
      // marcado, o app travaria no estado "conectando" sem nunca conectar.
      expect(state.isConnectingVoice, isFalse);
      expect(state.connectedVoiceChannelId, isNull);
    });
  });
}
