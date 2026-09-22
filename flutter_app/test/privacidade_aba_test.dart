import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/widgets/modals/settings_modal.dart';

import 'app_sandbox.dart';

/// O texto desta aba é afirmação sobre criptografia, e afirmação errada em
/// documento de privacidade não é detalhe de redação.
///
/// A versão anterior dizia que "todas as mensagens e áudio" eram ponta a ponta.
/// O código não sustenta isso: o `RoomOptions` do VoiceService não habilita E2EE,
/// então o LiveKit Cloud processa o áudio para roteá-lo. Estes testes amarram o
/// texto àquilo que foi conferido no código, inclusive o que ainda não existe.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  Future<void> abrirAba(WidgetTester tester) async {
    final state = AppState()
      ..isCheckingAuth = false
      ..isAuthenticated = true;
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: SettingsModal(initialTab: SettingsTab.privacy)),
      ),
    );
    await tester.pump();
  }

  Finder textoHonesto(String trecho) => find.textContaining(trecho, skipOffstage: false);

  testWidgets('o áudio é declarado cifrado no trajeto, e não ponta a ponta',
      (tester) async {
    await abrirAba(tester);

    expect(textoHonesto('Voz, câmera e tela: cifrados no trajeto, não ponta a ponta'),
        findsOneWidget);
    expect(textoHonesto('HOP-BY-HOP'), findsOneWidget);
    expect(textoHonesto('DTLS/SRTP'), findsOneWidget);
    // A câmera entrou nesta aba no dia em que entrou no aplicativo, e com a
    // promessa que o código cumpre: `leaveVoice` desliga a captura antes de
    // derrubar a conexão.
    expect(textoHonesto('a câmera só captura'), findsOneWidget);
    // A frase que não era sustentada pelo código não pode voltar.
    expect(textoHonesto('Todas as mensagens e áudio'), findsNothing);
    expect(textoHonesto('Nem intermediários nem brokers têm acesso'), findsNothing);
  });

  testWidgets('o chat é afirmado com os números que o código usa de fato',
      (tester) async {
    await abrirAba(tester);

    expect(textoHonesto('AES-256-GCM'), findsWidgets);
    expect(textoHonesto('210.000'), findsOneWidget);
    expect(textoHonesto('X25519'), findsOneWidget);
    // A parte que a versão antiga omitia: o retrato cifrado retido no broker
    // público, e o convite sendo a própria chave.
    expect(textoHonesto('broker.emqx.io'), findsOneWidget);
    expect(textoHonesto('RETIDO'), findsOneWidget);
    expect(textoHonesto('O código de convite é a chave da conversa'), findsOneWidget);
  });

  testWidgets('o que não existe ainda está escrito como não existindo',
      (tester) async {
    await abrirAba(tester);

    expect(textoHonesto('Excluir a conta ainda não existe'), findsOneWidget);
    expect(textoHonesto('EM ABERTO'), findsOneWidget);
    expect(textoHonesto('Idade: a gente recomenda, não verifica'), findsOneWidget);
    expect(textoHonesto('13+'), findsOneWidget);
    // O endereço publicado na aba é o da página que existe no site.
    expect(textoHonesto('papocall.vercel.app/politica-de-privacidade'), findsOneWidget);
  });
}
