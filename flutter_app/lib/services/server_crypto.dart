import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as classic;

/// Criptografia ponta a ponta das mensagens trafegadas pelo broker MQTT.
///
/// POR QUE ISSO EXISTE:
/// O PapoCall usa um broker MQTT público e anônimo como transporte. Qualquer
/// pessoa na internet pode se inscrever nos tópicos e publicar neles. Portanto o
/// transporte é tratado como hostil: o broker é apenas um repetidor burro que
/// nunca vê conteúdo legível.
///
/// COMO FUNCIONA:
/// 1. O código de convite do servidor (ex: 'papo-1a2b3c4d') é o segredo
///    compartilhado entre os membros — quem tem o convite tem acesso, quem não
///    tem não consegue ler nem escrever.
/// 2. A chave AES-256 é derivada do convite com PBKDF2-HMAC-SHA256 (210k
///    iterações, conforme recomendação OWASP de 2023), e não usada diretamente.
/// 3. O nome do tópico é um hash do convite com um rótulo de domínio distinto,
///    de modo que o tópico não revela o convite e não é adivinhável.
/// 4. O payload é cifrado com AES-256-GCM, que garante confidencialidade e
///    autenticidade: mensagem adulterada ou publicada por quem não tem a chave
///    falha na verificação do MAC e é descartada.
class ServerCrypto {
  static const String _keyDomain = 'papocall/v2/key';
  static const String _topicDomain = 'papocall/v2/topic';

  static final _algorithm = AesGcm.with256bits();
  static final Map<String, SecretKey> _keyCache = {};
  static final Map<String, String> _topicCache = {};

  /// Deriva (e memoriza) a chave AES-256 do código de convite do servidor.
  static Future<SecretKey> _keyFor(String inviteCode) async {
    final normalized = inviteCode.trim().toLowerCase();
    final cached = _keyCache[normalized];
    if (cached != null) return cached;

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    );

    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(normalized)),
      nonce: utf8.encode(_keyDomain),
    );

    _keyCache[normalized] = key;
    return key;
  }

  /// Identificador opaco e estável do servidor, usado para montar o tópico MQTT.
  ///
  /// Usa um rótulo de domínio diferente do usado na derivação da chave, de modo
  /// que conhecer o tópico não ajuda em nada a descobrir a chave.
  static String topicIdFor(String inviteCode) {
    final normalized = inviteCode.trim().toLowerCase();
    final cached = _topicCache[normalized];
    if (cached != null) return cached;

    final digest = classic.sha256.convert(utf8.encode('$_topicDomain:$normalized'));
    final id = digest.toString().substring(0, 32);
    _topicCache[normalized] = id;
    return id;
  }

  static String chatTopic(String inviteCode) =>
      'papocall/v2/r/${topicIdFor(inviteCode)}/chat';

  static String presenceTopic(String inviteCode) =>
      'papocall/v2/r/${topicIdFor(inviteCode)}/presence';

  static String userInboxTopic(String username) =>
      'papocall/v2/u/${topicIdFor("inbox:${username.trim().toLowerCase()}")}/inbox';

  static String userPresenceTopic(String username) =>
      'papocall/v2/u/${topicIdFor("presence:${username.trim().toLowerCase()}")}/presence';

  static String inboxKeySecret(String username) =>
      'inbox_key:${username.trim().toLowerCase()}';

  static String presenceKeySecret(String username) =>
      'presence_key:${username.trim().toLowerCase()}';

  static Future<String> encryptInboxPayload(
    String targetUsername,
    Map<String, dynamic> payload,
  ) {
    return encryptPayload(inboxKeySecret(targetUsername), payload);
  }

  static Future<Map<String, dynamic>?> decryptInboxPayload(
    String myUsername,
    String envelope,
  ) {
    return decryptPayload(inboxKeySecret(myUsername), envelope);
  }

  static Future<String> encryptFriendPresencePayload(
    String myUsername,
    Map<String, dynamic> payload,
  ) {
    return encryptPayload(presenceKeySecret(myUsername), payload);
  }

  static Future<Map<String, dynamic>?> decryptFriendPresencePayload(
    String friendUsername,
    String envelope,
  ) {
    return decryptPayload(presenceKeySecret(friendUsername), envelope);
  }

  /// Cifra o payload. O envelope publicado no broker contém apenas o nonce e o
  /// texto cifrado autenticado — nenhum metadado legível.
  static Future<String> encryptPayload(
    String inviteCode,
    Map<String, dynamic> payload,
  ) async {
    final key = await _keyFor(inviteCode);
    final plaintext = utf8.encode(jsonEncode(payload));

    final box = await _algorithm.encrypt(plaintext, secretKey: key);

    return jsonEncode({
      'v': 2,
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
  }

  /// Decifra o envelope. Retorna null se a mensagem foi adulterada, veio de
  /// alguém sem a chave, ou está em formato desconhecido — nunca lança, porque
  /// lixo vindo de um broker público é esperado e não é condição de erro.
  static Future<Map<String, dynamic>?> decryptPayload(
    String inviteCode,
    String envelope,
  ) async {
    try {
      final decoded = jsonDecode(envelope);
      if (decoded is! Map<String, dynamic> || decoded['v'] != 2) return null;

      final nonce = base64Decode(decoded['n'] as String);
      final cipherText = base64Decode(decoded['c'] as String);
      final mac = base64Decode(decoded['m'] as String);

      final key = await _keyFor(inviteCode);
      final clear = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );

      final parsed = jsonDecode(utf8.decode(clear));
      return parsed is Map<String, dynamic> ? parsed : null;
    } catch (_) {
      // MAC inválido, chave errada ou payload malformado: descarta em silêncio.
      return null;
    }
  }

  /// Limpa as chaves derivadas da memória (usado no logout).
  static void clearCache() {
    _keyCache.clear();
    _topicCache.clear();
  }

  /// Compara dois valores em tempo constante, para checagens de igualdade
  /// sensíveis sem vazar informação por tempo de resposta.
  static bool constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
