import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/services/server_crypto.dart';

void main() {
  group('ServerCrypto — proteção do transporte MQTT público', () {
    const convite = 'papo-1a2b3c4d';
    const conviteIntruso = 'papo-99999999';

    final mensagem = <String, dynamic>{
      'action': 'chat_message',
      'channelId': 'srv-1-c-geral',
      'message': {'text': 'informação confidencial do squad'},
    };

    test('membro do servidor consegue ler a mensagem', () async {
      final envelope = await ServerCrypto.encryptPayload(convite, mensagem);
      final aberto = await ServerCrypto.decryptPayload(convite, envelope);

      expect(aberto, isNotNull);
      expect(aberto!['channelId'], 'srv-1-c-geral');
      expect(aberto['message']['text'], 'informação confidencial do squad');
    });

    test('o envelope publicado não expõe o conteúdo em claro', () async {
      final envelope = await ServerCrypto.encryptPayload(convite, mensagem);

      expect(envelope.contains('informação confidencial'), isFalse);
      expect(envelope.contains('chat_message'), isFalse);
      expect(envelope.contains('srv-1-c-geral'), isFalse);
    });

    test('quem não tem o convite não consegue decifrar', () async {
      final envelope = await ServerCrypto.encryptPayload(convite, mensagem);
      final tentativa = await ServerCrypto.decryptPayload(conviteIntruso, envelope);

      expect(tentativa, isNull);
    });

    test('mensagem adulterada no broker é rejeitada', () async {
      final envelope = await ServerCrypto.encryptPayload(convite, mensagem);
      final parts = jsonDecode(envelope) as Map<String, dynamic>;

      // Inverte um byte do texto cifrado, simulando adulteração em trânsito.
      final cipher = base64Decode(parts['c'] as String);
      cipher[0] = cipher[0] ^ 0xFF;
      parts['c'] = base64Encode(cipher);

      final adulterado = await ServerCrypto.decryptPayload(convite, jsonEncode(parts));
      expect(adulterado, isNull);
    });

    test('payload arbitrário publicado por terceiro é descartado', () async {
      final forjado = jsonEncode({'action': 'chat_message', 'message': {'text': 'spam'}});
      final resultado = await ServerCrypto.decryptPayload(convite, forjado);

      expect(resultado, isNull);
    });

    test('o nome do tópico não revela o código de convite', () {
      final topico = ServerCrypto.chatTopic(convite);

      expect(topico.contains('1a2b3c4d'), isFalse);
      expect(topico.startsWith('papocall/v2/r/'), isTrue);
    });

    test('servidores diferentes usam tópicos diferentes', () {
      expect(
        ServerCrypto.chatTopic(convite),
        isNot(ServerCrypto.chatTopic(conviteIntruso)),
      );
    });

    test('regenerar o convite invalida o acesso anterior', () async {
      final envelopeAntigo = await ServerCrypto.encryptPayload(convite, mensagem);

      // Após regenerar, o código antigo não abre as mensagens novas e o tópico muda.
      const novoConvite = 'papo-deadbeef';
      final envelopeNovo = await ServerCrypto.encryptPayload(novoConvite, mensagem);

      expect(await ServerCrypto.decryptPayload(novoConvite, envelopeAntigo), isNull);
      expect(await ServerCrypto.decryptPayload(convite, envelopeNovo), isNull);
    });
  });
}
