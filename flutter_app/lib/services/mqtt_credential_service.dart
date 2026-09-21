import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// Credencial de sessão do broker MQTT, emitida pelo backend.
///
/// [username] é o UUID interno da conta, não o `@`: o log do broker fica sem
/// nome de ninguém. [password] é aleatória e só o hash dela existe no banco.
class MqttCredential {
  final String username;
  final String password;
  final DateTime expiresAt;

  /// Onde conectar. Vêm vazios quando o servidor ainda não configurou o broker
  /// dedicado, e nesse caso o aplicativo usa o que foi injetado no build.
  final String host;
  final int port;
  final String wssUrl;

  const MqttCredential({
    required this.username,
    required this.password,
    required this.expiresAt,
    this.host = '',
    this.port = 0,
    this.wssUrl = '',
  });

  /// Falta menos de [folga] para expirar?
  bool expirandoEm(Duration folga) => DateTime.now().add(folga).isAfter(expiresAt);
}

/// Emissão de credencial MQTT e sincronização de participação, pelo backend.
///
/// MODELO DE SEGURANÇA: igual ao do LiveKit (`livekit_token_service.dart`) — o
/// aplicativo não guarda nem assina segredo do broker. A credencial é de sessão,
/// expira, e o backend revoga as linhas no "sair de todas as sessões". Um binário
/// extraído por hex não entrega nada de útil: a senha que ele continha já venceu.
///
/// Onde o broker fica também vem daqui, e não de uma constante no código: trocar
/// de broker passa a ser uma linha no painel do servidor, não uma versão nova.
class MqttCredentialService {
  static const String _defaultApiUrl = 'https://papocall.onrender.com';
  static const String _apiUrlFromEnv = String.fromEnvironment('PAPOCALL_API_URL');

  static String get apiBaseUrl =>
      _apiUrlFromEnv.isNotEmpty ? _apiUrlFromEnv : _defaultApiUrl;

  /// Pede uma credencial nova.
  ///
  /// [renewSession] é o mesmo contrato do serviço de voz: quem renova é o
  /// `AppState`, single-flight, nunca lendo o disco por conta própria — o backend
  /// rotaciona o refresh token a cada uso e puni reuso revogando a conta inteira.
  static Future<MqttCredential> requestCredential({
    required String accessToken,
    required Future<AuthSession?> Function() renewSession,
  }) async {
    final data = await _pos(
      caminho: '/mqtt/credentials',
      corpo: const {},
      accessToken: accessToken,
      renewSession: renewSession,
      mensagem: 'Não foi possível obter credencial do servidor de mensagens.',
    );

    final username = data['mqttUsername'] as String? ?? '';
    final password = data['mqttPassword'] as String? ?? '';
    final expira = DateTime.tryParse(data['expiresAt'] as String? ?? '');

    if (username.isEmpty || password.isEmpty || expira == null) {
      throw Exception('Resposta incompleta do servidor de mensagens.');
    }

    return MqttCredential(
      username: username,
      password: password,
      expiresAt: expira,
      host: data['host'] as String? ?? '',
      port: data['port'] as int? ?? 0,
      wssUrl: data['wssUrl'] as String? ?? '',
    );
  }

  /// Declara o conjunto de salas do usuário.
  ///
  /// Substituir, não acrescentar: é assim que sair de um servidor tira o acesso
  /// na mesma chamada. Só o identificador derivado do convite vai; o código em si
  /// é a chave AES-256 da sala e nunca sai do aparelho.
  static Future<void> syncMemberships({
    required List<String> topicIds,
    required String accessToken,
    required Future<AuthSession?> Function() renewSession,
  }) async {
    await _pos(
      caminho: '/mqtt/memberships',
      corpo: {'topicIds': topicIds},
      accessToken: accessToken,
      renewSession: renewSession,
      mensagem: 'Não foi possível sincronizar suas salas com o servidor de mensagens.',
    );
  }

  static Future<Map<String, dynamic>> _pos({
    required String caminho,
    required Map<String, dynamic> corpo,
    required String accessToken,
    required Future<AuthSession?> Function() renewSession,
    required String mensagem,
  }) async {
    if (accessToken.isEmpty) {
      throw Exception('Sessão inválida. Faça login novamente.');
    }

    final uri = Uri.parse('$apiBaseUrl$caminho');
    Future<http.Response> chamar(String token) => http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(corpo),
        )
        .timeout(const Duration(seconds: 12));

    var response = await chamar(accessToken);

    // Access token expirado (15 min): renova uma vez e repete a chamada.
    if (response.statusCode == 401) {
      final renewed = await renewSession();
      if (renewed != null && renewed.accessToken.isNotEmpty) {
        response = await chamar(renewed.accessToken);
      }
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(mensagem);
    }

    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['error']?['message'] as String? ?? mensagem);
    }

    return body['data'] as Map<String, dynamic>;
  }
}
