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
  /// URL do backend, injetada em tempo de build (--dart-define=PAPOCALL_API_URL).
  static const String _apiUrlFromEnv = String.fromEnvironment('PAPOCALL_API_URL');

  static String get apiBaseUrl =>
      _apiUrlFromEnv.isNotEmpty ? _apiUrlFromEnv : 'https://papocall.vercel.app';

  /// Solicita ao backend um token de acesso para a sala informada.
  ///
  /// [accessToken] é o JWT de sessão do usuário autenticado. A identity usada
  /// no LiveKit é derivada desse JWT pelo servidor e nunca enviada pelo cliente,
  /// o que impede personificação de outro usuário.
  static Future<LiveKitGrant> requestGrant({
    required String roomName,
    required String accessToken,
  }) async {
    if (accessToken.isEmpty) {
      throw Exception('Sessão inválida. Faça login novamente para entrar na chamada.');
    }

    final uri = Uri.parse('$apiBaseUrl/livekit/token');
    http.Response response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({'room': roomName}),
        )
        .timeout(const Duration(seconds: 12));

    // Se o access token tiver expirado (401), tenta renovar silenciosamente via refresh token
    if (response.statusCode == 401) {
      final session = await AuthService.loadSession();
      if (session != null) {
        final renewed = await AuthService.refreshSession(session);
        if (renewed != null && renewed.accessToken.isNotEmpty) {
          response = await http
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer ${renewed.accessToken}',
                },
                body: jsonEncode({'room': roomName}),
              )
              .timeout(const Duration(seconds: 12));
        }
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
