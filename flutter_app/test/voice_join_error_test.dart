import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/role.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/providers/app_state.dart';

import 'app_sandbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  // O canal precisa ser de um servidor meu: desde a correção do botão "Entrar na
  // Call" da lista de amigos, `connectVoice` recusa canal alheio antes de qualquer
  // outra coisa, e a recusa do backend só é exercitada num pedido legítimo.
  Server servidorComCanal() => Server(
        id: 'srv-1',
        name: 'Servidor',
        inviteCode: '',
        ownerId: 'eu',
        memberIds: ['eu'],
        roles: ServerRole.defaults(),
        channels: [
          Channel(id: 'srv-1-v-geral', name: 'Sala de Voz', type: ChannelType.voice),
        ],
      );

  // O HUD de voz só existe enquanto há conexão, então uma recusa do backend
  // não aparecia em lugar nenhum: connectVoice precisa devolver o motivo para
  // o chamador poder mostrar na tela.
  test('entrar na voz devolve o motivo da recusa em vez de falhar em silêncio', () async {
    final state = AppState()..servers.add(servidorComCanal());

    final erro = await state.connectVoice('srv-1-v-geral');

    expect(erro, isNotNull);
    expect(erro, contains('login'));
    expect(state.connectedVoiceChannelId, isNull);
    expect(state.isConnectingVoice, isFalse);
    // Entrar na call sem sessão não derruba mais o login: era isto que apagava
    // o session.dat e fazia a conta "desaparecer".
    expect(state.isAuthenticated, isFalse);
  });

  test('entrar no canal de voz já conectado não gera nova tentativa', () async {
    final state = AppState();
    state.connectedVoiceChannelId = 'srv-1-v-geral';

    expect(await state.connectVoice('srv-1-v-geral'), isNull);
    expect(state.isConnectingVoice, isFalse);
  });
}
