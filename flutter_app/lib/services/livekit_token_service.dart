import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// Resultado da emissão de um token de voz pelo backend.
class LiveKitGrant {
  final String serverUrl;
  final String token;
  final String identity;

  const LiveKitGrant({
    required this.serverUrl,
    required this.token,
    required this.identity,
  });
}

/// Obtenção de credenciais de voz (LiveKit) exclusivamente pelo backend.
///
/// MODELO DE SEGURANÇA (a partir da v1.0.0g):
/// O aplicativo distribuído NÃO possui, NÃO lê e NÃO assina nada com a
/// LIVEKIT_API_SECRET. Todo binário entregue ao usuário é considerado público:
/// qualquer segredo embutido nele (via --dart-define, arquivo JSON ao lado do
/// executável ou .env) é extraível com um editor hexadecimal.
///
/// O cliente apenas apresenta seu access token JWT ao backend, que valida a
/// sessão, confere se o usuário pode entrar na sala pedida e então assina o
/// token do LiveKit no servidor, onde o segredo permanece.
class LiveKitTokenService {
  /// Endereço padrão do backend caso não injetado via --dart-define.
  static const String _defaultApiUrl = 'https://papocall.onrender.com';
  static const String _apiUrlFromEnv = String.fromEnvironment('PAPOCALL_API_URL');

  static String get apiBaseUrl =>
      _apiUrlFromEnv.isNotEmpty ? _apiUrlFromEnv : _defaultApiUrl;

  /// Solicita ao backend um token de acesso para a sala informada.
  ///
  /// [accessToken] é o JWT de sessão do usuário autenticado. A identity usada
  /// no LiveKit é derivada desse JWT pelo servidor e nunca enviada pelo cliente,
  /// o que impede personificação de outro usuário.
  ///
  /// [renewSession] renova a sessão por quem a possui em memória (AppState) e
  /// devolve a sessão renovada. Não se renova por conta própria lendo o disco:
  /// o refresh roda no servidor e consome o token antigo, então uma renovação
  /// paralela deixaria o chamador com um refresh token já queimado — o que o
  /// backend pune revogando todas as sessões da conta.
  static Future<LiveKitGrant> requestGrant({
    required String roomName,
    required String accessToken,
    required Future<AuthSession?> Function() renewSession,
  }) async {
    if (accessToken.isEmpty) {
      throw Exception('Sessão inválida. Faça login novamente para entrar na chamada.');
    }

    final uri = Uri.parse('$apiBaseUrl/livekit/token');
    Future<http.Response> chamar(String token) => http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'room': roomName}),
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

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200 || body['success'] != true) {
      final message = body['error']?['message'] as String? ??
          'Não foi possível obter autorização para entrar na sala de voz.';
      throw Exception(message);
    }

    final data = body['data'] as Map<String, dynamic>;
    final serverUrl = data['serverUrl'] as String? ?? '';
    final token = data['token'] as String? ?? '';

    if (serverUrl.isEmpty || token.isEmpty) {
      throw Exception('Resposta inválida do servidor de voz.');
    }

    return LiveKitGrant(
      serverUrl: serverUrl,
      token: token,
      identity: data['identity'] as String? ?? '',
    );
  }
}
