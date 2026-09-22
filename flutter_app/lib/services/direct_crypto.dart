import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../utils/app_log.dart';
import '../utils/app_paths.dart';
import 'secure_storage.dart';

/// Chave ponta a ponta de uma conversa direta entre duas pessoas.
///
/// POR QUE NÃO A CHAVE DO SERVIDOR: a caixa de entrada de um usuário é cifrada
/// por uma chave derivada do próprio nome de usuário (`ServerCrypto.inboxKeySecret`).
/// Isso basta para um pedido de amizade, mas para uma conversa privada qualquer
/// pessoa que saiba o apelido do destinatário poderia calcular a mesma chave,
/// ler e até inventar mensagens. Aqui a chave de cada conversa sai de um
/// X25519 entre as duas partes: quem não tem a chave privada do outro não lê.
///
/// O que isto NÃO resolve sozinho: autenticidade. A chave pública do par chega
/// pela presença do próprio par, cifrada com aquela chave fraca derivada do
/// nome. Um atacante ativo que consiga publicar presença falsa no lugar dele
/// também consegue trocar a chave. A impressão digital exposta na conversa é o
/// que permite às duas pessoas conferirem isso por outro canal.
class DirectCrypto {
  static const String _dominio = 'papocall/dm/v1';
  static const String _arquivoIdentidade = 'dm_identity.key';

  static final X25519 _x25519 = X25519();
  static final AesGcm _aes = AesGcm.with256bits();

  static SimpleKeyPair? _par;

  /// Par desta conta, nesta instalação. Gerado na primeira execução e relido do
  /// disco nas seguintes: trocar de chave a cada abertura quebraria toda
  /// conversa antiga.
  ///
  /// Fica na pasta da conta de propósito. Enquanto viveu na raiz, a pessoa que
  /// criasse uma conta nova no mesmo computador assinava as mensagens dela com a
  /// chave privada da conta anterior — a identidade privada também vazava de uma
  /// conta para a outra.
  static Future<SimpleKeyPair> identidade() async {
    final existente = _par;
    if (existente != null) return existente;

    final arquivo = AppPaths.contaFile(_arquivoIdentidade);
    final gravado = await SecureStorage.readEncrypted(arquivo);
    if (gravado != null && gravado.isNotEmpty) {
      try {
        final json = jsonDecode(gravado) as Map<String, dynamic>;
        final privada = base64Decode(json['privada'] as String);
        final par = await _x25519.newKeyPairFromSeed(privada);
        _par = par;
        AppLog.write('Direct', 'identidade de conversa direta relida do disco');
        return par;
      } catch (e) {
        AppLog.write('Direct', 'identidade ilegível, gerando outra: $e');
      }
    }

    final novo = await _x25519.newKeyPair();
    final dados = await novo.extract();
    final ok = await SecureStorage.writeEncrypted(
      arquivo,
      jsonEncode({
        'privada': base64Encode(dados.bytes),
        'publica': base64Encode(dados.publicKey.bytes),
      }),
    );
    if (!ok) {
      // Sem DPAPI a chave privada não pode ser gravada. As conversas ainda
      // funcionam nesta sessão; só não sobrevivem a um reinício.
      AppLog.write('Direct', 'FALHA ao cifrar a identidade (DPAPI)');
    }
    _par = novo;
    AppLog.write('Direct', 'identidade de conversa direta gerada');
    return novo;
  }

  /// Esquece o par carregado, para a próxima [identidade] ler o disco da conta
  /// que acabou de entrar. Sem isto, a segunda conta desta instalação continuava
  /// usando a chave da primeira, que ficou na memória.
  static void esquecerIdentidade() => _par = null;

  /// Chave pública desta instalação, em base64, para ir na presença.
  static Future<String> chavePublicaAtual() async {
    final dados = await (await identidade()).extract();
    return base64Encode(dados.publicKey.bytes);
  }

  /// Os dois apelidos em ordem estável, para que remetente e destinatário
  /// derivem exatamente a mesma chave sem combinar quem é "a".
  static List<String> _parDeNomes(String a, String b) {
    final x = a.trim().toLowerCase();
    final y = b.trim().toLowerCase();
    return x.compareTo(y) <= 0 ? [x, y] : [y, x];
  }

  /// Envelope cifrado para [para]. O par de quem envia entra como argumento, e
  /// não é lido de um global, para que as duas pontas possam ser exercitadas
  /// num mesmo processo em teste.
  static Future<String> cifrar({
    required SimpleKeyPair minha,
    required String de,
    required String para,
    required String publicaDoParB64,
    required Map<String, dynamic> conteudo,
  }) async {
    final nomes = _parDeNomes(de, para).join('|');
    final dados = await minha.extract();
    final compartilhada = await _x25519.sharedSecretKey(
      keyPair: minha,
      remotePublicKey: SimplePublicKey(base64Decode(publicaDoParB64), type: KeyPairType.x25519),
    );
    final chave = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: compartilhada,
      info: utf8.encode('$_dominio|$nomes'),
    );
    final nonce = _aes.newNonce();
    final caixa = await _aes.encrypt(
      utf8.encode(jsonEncode(conteudo)),
      secretKey: chave,
      nonce: nonce,
      aad: utf8.encode('$_dominio|$nomes'),
    );

    return jsonEncode({
      'v': 1,
      'acao': 'dm',
      'de': de.trim().toLowerCase(),
      'para': para.trim().toLowerCase(),
      'pub': base64Encode(dados.publicKey.bytes),
      'n': base64Encode(caixa.nonce),
      'c': base64Encode(caixa.cipherText),
      'm': base64Encode(caixa.mac.bytes),
    });
  }

  /// Abre um envelope recebido na caixa de entrada.
  ///
  /// Devolve null para qualquer coisa que não feche: envelope de outro par,
  /// texto adulterado, MAC errado. `publicaDoEnvelope` sai junto para que quem
  /// recebe compare com a chave publicada na presença daquele contato e avise
  /// se forem diferentes.
  static Future<ConversaDecifrada?> decifrar({
    required SimpleKeyPair minha,
    required String meuUsuario,
    required String envelope,
  }) async {
    try {
      final json = jsonDecode(envelope) as Map<String, dynamic>;
      if (json['acao'] != 'dm') return null;
      final de = (json['de'] as String?)?.trim().toLowerCase() ?? '';
      final para = (json['para'] as String?)?.trim().toLowerCase() ?? '';
      if (para != meuUsuario.trim().toLowerCase() || de.isEmpty) return null;

      final nomes = _parDeNomes(de, para).join('|');
      final compartilhada = await _x25519.sharedSecretKey(
        keyPair: minha,
        remotePublicKey: SimplePublicKey(
          base64Decode(json['pub'] as String),
          type: KeyPairType.x25519,
        ),
      );
      final chave = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: compartilhada,
        info: utf8.encode('$_dominio|$nomes'),
      );
      final caixa = SecretBox(
        base64Decode(json['c'] as String),
        nonce: base64Decode(json['n'] as String),
        mac: Mac(base64Decode(json['m'] as String)),
      );
      final claro = await _aes.decrypt(
        caixa,
        secretKey: chave,
        aad: utf8.encode('$_dominio|$nomes'),
      );

      final conteudo = jsonDecode(utf8.decode(claro)) as Map<String, dynamic>;
      return ConversaDecifrada(de: de, conteudo: conteudo, publicaDoEnvelope: json['pub'] as String);
    } catch (e) {
      // Um envelope que não abre pode ser de outra conversa ou estar adulterado.
      // Não há o que mostrar ao usuário; registrar é o suficiente para depurar.
      AppLog.write('Direct', 'envelope descartado: $e');
      return null;
    }
  }

  /// Atalho legível da chave pública, para conferência por outro canal.
  static String impressao(String publicaB64) {
    final bytes = base64Decode(publicaB64);
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 4)} ${hex.substring(4, 8)} ${hex.substring(8, 12)} ${hex.substring(12, 16)}';
  }
}

class ConversaDecifrada {
  ConversaDecifrada({
    required this.de,
    required this.conteudo,
    required this.publicaDoEnvelope,
  });

  final String de;
  final Map<String, dynamic> conteudo;
  final String publicaDoEnvelope;
}
