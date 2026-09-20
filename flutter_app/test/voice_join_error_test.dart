import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/providers/app_state.dart';

import 'app_sandbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  // O HUD de voz só existe enquanto há conexão, então uma recusa do backend
  // não aparecia em lugar nenhum: connectVoice precisa devolver o motivo para
  // o chamador poder mostrar na tela.
  test('entrar na voz devolve o motivo da recusa em vez de falhar em silêncio', () async {
    final state = AppState();

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
