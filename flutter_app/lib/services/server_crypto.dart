import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as classic;

/// Criptografia ponta a ponta das mensagens trafegadas pelo broker MQTT.
///
/// POR QUE ISSO EXISTE:
/// O PapoCall usa um broker MQTT dedicado como transporte: ninguém entra sem
/// credencial de sessão, e cada publicação é conferida contra a lista de
/// participação. Mesmo assim o transporte é tratado como hostil — o broker é um
/// repetidor que pode ser compilado errado, preenchido por script ou mandado embora
/// por um operador de má fé, e nunca vê conteúdo legível.
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
  static final Map<String, Future<SecretKey>> _derivando = {};
  static final Map<String, String> _topicCache = {};

  /// Deriva (e memoriza) a chave AES-256 do código de convite do servidor.
  static Future<SecretKey> _keyFor(String inviteCode) async {
    final normalized = inviteCode.trim().toLowerCase();
    final cached = _keyCache[normalized];
    if (cached != null) return cached;

    // Duas chamadas simultâneas para o mesmo segredo esperariam duas vezes as
    // 210 mil iterações: a primeira ainda não terminou e já não há o que
    // memorizar. Quem chega depois espera a vez na mesma derivação.
    final emCurso = _derivando[normalized];
    if (emCurso != null) return emCurso;

    final futura = _derivarForaDoIsolate(normalized);
    _derivando[normalized] = futura;
    try {
      final key = await futura;
      _keyCache[normalized] = key;
      return key;
    } finally {
      _derivando.remove(normalized);
    }
  }

  /// PBKDF2 com 210 mil iterações em Dart puro custa de meio a dois segundos de
  /// CPU. Na interface isso era o aplicativo inteiro congelado nos primeiros
  /// segundos depois do login — um travamento por servidor, amigo e caixa de
  /// entrada recém-contatados. O trabalho vai para um isolate; só os bytes
  /// prontos voltam, e a chave privada nunca é atravessada.
  static Future<SecretKey> _derivarForaDoIsolate(String normalized) async {
    final bytes = await Isolate.run(() async {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 210000,
        bits: 256,
      );
      final derivada = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(normalized)),
        nonce: utf8.encode(_keyDomain),
      );
      return derivada.extractBytes();
    });
    return SecretKey(bytes);
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

  /// Compartimento de presença retido, um por membro.
  ///
  /// Todos os membros publicavam presença no mesmo tópico; retê-la ali faria
  /// cada um sobrescrever o anterior. Com um compartimento por usuário, quem
  /// abre o app recebe de imediato a última presença conhecida de cada membro,
  /// em vez de esperar até 10s pelo próximo heartbeat de cada um.
  ///
  /// Cada compartimento é assinado pelo nome exato, um por membro conhecido —
  /// sem curinga. Membros ainda desconhecidos são descobertos pelo heartbeat
  /// publicado em [presenceTopic], e só então o compartimento deles é assinado.
  static String presenceSlotTopic(String inviteCode, String userId) =>
      '${presenceTopic(inviteCode)}/${topicIdFor("presenceslot:$userId")}';


  /// Tópico onde os membros publicam (retido) a estrutura real do servidor.
  ///
  /// Sem isto, quem entra por convite não tem como saber o nome do servidor nem
  /// quais canais existem, e acabava inventando uma estrutura local própria —
  /// com IDs de canal diferentes dos de quem criou o servidor. Como o nome da
  /// sala do LiveKit é o ID do canal, os dois lados entravam em salas de voz
  /// distintas e nunca se ouviam.
  static String serverInfoTopic(String inviteCode) =>
      'papocall/v2/r/${topicIdFor(inviteCode)}/info';

  static String historyTopic(String inviteCode) =>
      'papocall/v2/r/${topicIdFor(inviteCode)}/history';

  /// Compartimento de histórico retido, um por membro.
  ///
  /// Cada membro publica ali sua própria visão das mensagens recentes, e quem
  /// chega depois intercala o que recebeu de todos. Um tópico único e
  /// compartilhado não serviria: o broker guarda só a última mensagem retida de
  /// cada tópico, então o último a publicar apagaria o histórico dos demais.
  ///
  /// Assinado pelo nome exato, um por membro conhecido — sem curinga. O roster
  /// chega junto com a estrutura do servidor ([serverInfoTopic]), que é retida
  /// pelo dono, então até quem acabou de entrar sabe de quem cobrar histórico.
  static String historySlotTopic(String inviteCode, String userId) =>
      '${historyTopic(inviteCode)}/${topicIdFor("historyslot:$userId")}';

  static String userInboxTopic(String username) =>
      'papocall/v2/u/${topicIdFor("inbox:${username.trim().toLowerCase()}")}/inbox';

  /// Caixa de entrada com um compartimento retido por remetente.
  ///
  /// Uma mensagem retida por tópico só guarda a última: se todos os remetentes
  /// publicassem no mesmo tópico, a segunda solicitação apagaria a primeira.
  /// Com um compartimento por remetente, cada pedido sobrevive até o próprio
  /// remetente limpá-lo (cancelamento) ou o destinatário respondê-lo.
  static String userInboxSlotTopic(String recipientUsername, String senderUsername) =>
      '${userInboxTopic(recipientUsername)}/${topicIdFor("inboxslot:${senderUsername.trim().toLowerCase()}")}';

  /// Assinatura única que cobre o tópico legado e todos os compartimentos.
  ///
  /// Pelo padrão MQTT, 'a/b/#' também casa com o próprio 'a/b', então esta
  /// assinatura continua entregando o que versões antigas do app publicam
  /// direto em [userInboxTopic].
  ///
  /// ÚNICO CURINGA DO APLICATIVO, e ele fica inteiramente **abaixo** da
  /// fronteira de autorização: o prefixo é o hash da caixa de entrada deste
  /// usuário, e o '#' só percorre os compartimentos dos remetentes dentro dela.
  /// Não alcança a caixa de outro usuário nem qualquer servidor. Isso é o
  /// oposto da falha corrigida na v1.0.0g, em que o curinga ficava no lugar do
  /// identificador do servidor ('papocall/v1/srv/+/chat') e dava a todo cliente
  /// o chat de servidores dos quais ele nunca participou.
  ///
  /// É o curinga que torna possível receber uma solicitação de amizade enviada
  /// enquanto este usuário estava offline: não há como assinar previamente o
  /// compartimento de um remetente que ainda não se conhece.
  static String userInboxWildcard(String username) => '${userInboxTopic(username)}/#';

  /// Ramal da caixa de entrada reservado às conversas privadas, um por
  /// remetente.
  ///
  /// Fica sob o mesmo wildcard da caixa do destinatário — nenhuma assinatura nova
  /// — mas em ramal separado dos compartimentos de amizade de propósito: aqueles
  /// são retidos, e publicar chat neles apagaria o pedido de amizade pendente
  /// que o broker guarda ali.
  static String userInboxDmTopic(String recipientUsername, String senderUsername) =>
      '${userInboxTopic(recipientUsername)}/dm/'
      '${topicIdFor("dmslot:${senderUsername.trim().toLowerCase()}")}';

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
