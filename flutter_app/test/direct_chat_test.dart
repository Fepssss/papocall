import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/models/user_model.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/services/direct_crypto.dart';

import 'app_sandbox.dart';

/// Conversa privada: a chave vem da presença do amigo, a mensagem chega pela
/// caixa de entrada e nada disso depende de broker — por isso o envio real é
/// exercitado no caminho em que ele falha.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  late SimpleKeyPair parDoAmigo;
  late String publicaDoAmigo;

  setUp(() async {
    parDoAmigo = await X25519().newKeyPair();
    publicaDoAmigo = base64Encode((await parDoAmigo.extract()).publicKey.bytes);
  });

  AppState aplicativo() => AppState()
    ..currentUser = UserModel(id: 'user-eu', username: 'feps', displayName: 'Feps')
    ..friends.add(UserModel(id: 'user-amigo', username: 'victor', displayName: 'Victor'));

  void presencaDoAmigo(AppState state, {String? chave}) {
    state.isNetworkOnline = true;
    state.processFriendPresencePayload({
      'action': 'user_presence',
      'userId': 'user-amigo',
      'username': 'victor',
      'displayName': 'Victor',
      'status': 'online',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'dmPub': ?chave,
    });
  }

  Future<Map<String, dynamic>> envelopeDe(
    SimpleKeyPair parDeQuemEnvia, {
    required String de,
    required String texto,
    String id = 'msg-1',
    int? enviadoEm,
  }) async {
    final minhaPublica = await DirectCrypto.chavePublicaAtual();
    final bruto = await DirectCrypto.cifrar(
      minha: parDeQuemEnvia,
      de: de,
      para: 'feps',
      publicaDoParB64: minhaPublica,
      conteudo: {
        'id': id,
        'texto': texto,
        'enviadoEm': enviadoEm ?? DateTime.now().millisecondsSinceEpoch,
      },
    );
    return {'action': 'dm', 'envelope': bruto};
  }

  group('conversa privada', () {
    test('a chave do contato chega pela presença e destrava o envio', () {
      final state = aplicativo();

      expect(state.bloqueioDeEnvioDireto('user-amigo'), isNotNull);

      // Lixo publicado no canal de presença do amigo não vira chave de conversa.
      presencaDoAmigo(state, chave: 'nao-e-uma-chave');
      expect(state.chavePublicaDoPar('user-amigo'), isNull);

      presencaDoAmigo(state, chave: publicaDoAmigo);
      expect(state.chavePublicaDoPar('user-amigo'), publicaDoAmigo);
      expect(state.impressaoDoPar('user-amigo'), hasLength(19));
      expect(state.bloqueioDeEnvioDireto('user-amigo'), isNull);
    });

    test('amigo offline não recebe promessa de entrega', () {
      final state = aplicativo();
      presencaDoAmigo(state, chave: publicaDoAmigo);

      // A mesma presença, agora com carimbo velho: é o que fica no broker depois
      // que o amigo fecha o aplicativo, e a conversa tem de perceber isso.
      state.processFriendPresencePayload({
        'action': 'user_presence',
        'userId': 'user-amigo',
        'username': 'victor',
        'displayName': 'Victor',
        'status': 'online',
        'timestamp': DateTime.now().millisecondsSinceEpoch - 60000,
      });

      final motivo = state.bloqueioDeEnvioDireto('user-amigo');
      expect(motivo, contains('offline'));
    });

    test('a mensagem não fica na tela quando não saiu do aparelho', () async {
      final state = aplicativo();
      presencaDoAmigo(state, chave: publicaDoAmigo);

      final motivo = await state.sendDirectMessage('user-amigo', 'oi, tudo bem?');

      // Sem broker conectado a publicação falha, e o balão some junto: uma
      // conversa privada que finge entrega é pior que uma que recusa.
      expect(motivo, isNotNull);
      expect(state.directMessages('user-amigo'), isEmpty);
    });

    test('mensagem de amigo entra na conversa e conta como não lida', () async {
      final state = aplicativo();
      presencaDoAmigo(state, chave: publicaDoAmigo);

      await state.processInboxPayload(
        await envelopeDe(parDoAmigo, de: 'victor', texto: 'chegou?'),
      );

      final mensagens = state.directMessages('user-amigo');
      expect(mensagens, hasLength(1));
      expect(mensagens.single.text, 'chegou?');
      expect(mensagens.single.authorId, 'user-amigo');
      expect(state.unreadDirectFor('user-amigo'), 1);

      final conversas = state.directConversations;
      expect(conversas, hasLength(1));
      expect(conversas.single.ultima.text, 'chegou?');
      expect(conversas.single.naoLidas, 1);

      state.openDirectChat('user-amigo');
      expect(state.activeDirectPeer?.username, 'victor');
      expect(state.unreadDirectFor('user-amigo'), 0);
    });

    test('a mesma mensagem entregue duas vezes não se repete', () async {
      final state = aplicativo();
      presencaDoAmigo(state, chave: publicaDoAmigo);
      final envelope = await envelopeDe(parDoAmigo, de: 'victor', texto: 'repetida');

      await state.processInboxPayload(envelope);
      await state.processInboxPayload(envelope);

      expect(state.directMessages('user-amigo'), hasLength(1));
    });

    test('quem não é amigo não abre conversa', () async {
      final state = aplicativo();
      final estranho = await X25519().newKeyPair();

      await state.processInboxPayload(
        await envelopeDe(estranho, de: 'invasor', texto: 'oi'),
      );

      expect(state.directConversations, isEmpty);
      expect(state.directMessages('user-amigo'), isEmpty);
    });

    test('envelope endereçado a outra pessoa é descartado', () async {
      final state = aplicativo();
      presencaDoAmigo(state, chave: publicaDoAmigo);
      final minhaPublica = await DirectCrypto.chavePublicaAtual();

      final bruto = await DirectCrypto.cifrar(
        minha: parDoAmigo,
        de: 'victor',
        para: 'alguem-fora-da-lista',
        publicaDoParB64: minhaPublica,
        conteudo: const {'id': 'msg-x', 'texto': 'não é para você', 'enviadoEm': 1},
      );

      await state.processInboxPayload({'action': 'dm', 'envelope': bruto});
      expect(state.directMessages('user-amigo'), isEmpty);
    });

    test('quem escreve com outra chave não entra na conversa nem desvia a resposta',
        () async {
      final state = aplicativo();
      presencaDoAmigo(state, chave: publicaDoAmigo);
      await state.processInboxPayload(
        await envelopeDe(parDoAmigo, de: 'victor', texto: 'a primeira'),
      );

      // O broker é público e a chave da caixa de entrada se calcula a partir do
      // apelido: qualquer um pode cifrar isto aqui assinando como o Victor. Sem a
      // conferência da chave fixada, o texto abaixo entraria na conversa e a
      // resposta da pessoa passaria a ir para o estranho.
      final outroPar = await X25519().newKeyPair();
      final outraPublica = base64Encode((await outroPar.extract()).publicKey.bytes);
      await state.processInboxPayload(
        await envelopeDe(outroPar, de: 'victor', texto: 'a segunda', id: 'msg-2'),
      );

      expect(state.directMessages('user-amigo').map((m) => m.text), ['a primeira']);
      expect(state.chavePublicaDoPar('user-amigo'), publicaDoAmigo);
      expect(state.chavePublicaDoPar('user-amigo'), isNot(outraPublica));
    });

    test('a reinstalação do amigo, anunciada na presença, muda a chave com aviso',
        () async {
      final state = aplicativo();
      presencaDoAmigo(state, chave: publicaDoAmigo);
      await state.processInboxPayload(
        await envelopeDe(parDoAmigo, de: 'victor', texto: 'a primeira'),
      );

      final outroPar = await X25519().newKeyPair();
      final outraPublica = base64Encode((await outroPar.extract()).publicKey.bytes);
      presencaDoAmigo(state, chave: outraPublica);

      expect(state.chavePublicaDoPar('user-amigo'), outraPublica);
      expect(state.directMessages('user-amigo').where((m) => m.isSystem), hasLength(1));
      expect(
        state.directMessages('user-amigo').firstWhere((m) => m.isSystem).text,
        contains('mudou'),
      );

      // E a conversa continua: o envelope cifrado com a chave que a presença
      // acabou de anunciar é aceito.
      await state.processInboxPayload(
        await envelopeDe(outroPar, de: 'victor', texto: 'de novo eu', id: 'msg-2'),
      );
      expect(
        state.directMessages('user-amigo').where((m) => !m.isSystem).map((m) => m.text),
        ['a primeira', 'de novo eu'],
      );
    });

    test('o primeiro envelope, sem presença ainda, fixa a chave e entra', () async {
      final state = aplicativo();
      state.isNetworkOnline = true;

      await state.processInboxPayload(
        await envelopeDe(parDoAmigo, de: 'victor', texto: 'antes da presença'),
      );

      expect(state.directMessages('user-amigo').map((m) => m.text), ['antes da presença']);
      expect(state.chavePublicaDoPar('user-amigo'), isNotNull);
    });

    test('a conversa some da lista quando o amigo é removido', () async {
      final state = aplicativo();
      presencaDoAmigo(state, chave: publicaDoAmigo);
      await state.processInboxPayload(
        await envelopeDe(parDoAmigo, de: 'victor', texto: 'tchau'),
      );
      state.openDirectChat('user-amigo');

      await state.removeFriend('user-amigo');

      expect(state.directConversations, isEmpty);
      expect(state.activeDirectPeer, isNull);
      expect(state.chavePublicaDoPar('user-amigo'), isNull);
    });
  });
}
