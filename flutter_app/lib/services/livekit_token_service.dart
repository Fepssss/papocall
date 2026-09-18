import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class LiveKitTokenService {
  static const String liveKitUrl = 'wss://seu-projeto.livekit.cloud';
  static const String apiKey = 'your_api_key_here';
  static const String apiSecret = 'your_api_secret_here';

  /// Gera um token de acesso LiveKit compatível com a API de Nuvem LiveKit
  static String generateToken({
    required String roomName,
    required String identity,
    required String name,
  }) {
    final jwt = JWT(
      {
        'name': name,
        'video': {
          'roomJoin': true,
          'room': roomName,
          'canPublish': true,
          'canSubscribe': true,
          'canPublishData': true,
        },
      },
      issuer: apiKey,
      subject: identity,
    );

    return jwt.sign(
      SecretKey(apiSecret),
      algorithm: JWTAlgorithm.HS256,
      expiresIn: const Duration(hours: 12),
      notBefore: const Duration(seconds: -5),
    );
  }
}
