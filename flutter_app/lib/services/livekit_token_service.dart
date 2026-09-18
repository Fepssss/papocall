import 'dart:convert';
import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class LiveKitConfig {
  final String url;
  final String apiKey;
  final String apiSecret;

  const LiveKitConfig({
    required this.url,
    required this.apiKey,
    required this.apiSecret,
  });
}

class LiveKitTokenService {
  static const String defaultLiveKitUrl = 'wss://seu-projeto.livekit.cloud';
  static const String defaultApiKey = 'your_api_key_here';
  static const String defaultApiSecret = 'your_api_secret_here';

  static LiveKitConfig? _cachedConfig;

  static LiveKitConfig getConfig() {
    if (_cachedConfig != null) return _cachedConfig!;

    // 1. Tentar ler do %APPDATA%/PapoCall/livekit.json
    try {
      final appData = Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final configFile = File('$appData\\PapoCall\\livekit.json');
      if (configFile.existsSync()) {
        final content = configFile.readAsStringSync();
        if (content.isNotEmpty) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          final url = json['url'] as String? ?? defaultLiveKitUrl;
          final key = json['apiKey'] as String? ?? defaultApiKey;
          final secret = json['apiSecret'] as String? ?? defaultApiSecret;
          if (key != defaultApiKey && secret != defaultApiSecret) {
            _cachedConfig = LiveKitConfig(url: url, apiKey: key, apiSecret: secret);
            return _cachedConfig!;
          }
        }
      }
    } catch (_) {}

    // 2. Tentar ler do arquivo .env local
    try {
      final envFile = File('.env');
      if (envFile.existsSync()) {
        final lines = envFile.readAsLinesSync();
        String url = defaultLiveKitUrl;
        String key = defaultApiKey;
        String secret = defaultApiSecret;
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('LIVEKIT_URL=')) {
            url = trimmed.substring('LIVEKIT_URL='.length).replaceAll('"', '').trim();
          } else if (trimmed.startsWith('LIVEKIT_API_KEY=')) {
            key = trimmed.substring('LIVEKIT_API_KEY='.length).replaceAll('"', '').trim();
          } else if (trimmed.startsWith('LIVEKIT_API_SECRET=')) {
            secret = trimmed.substring('LIVEKIT_API_SECRET='.length).replaceAll('"', '').trim();
          }
        }
        if (key != defaultApiKey && secret != defaultApiSecret) {
          _cachedConfig = LiveKitConfig(url: url, apiKey: key, apiSecret: secret);
          return _cachedConfig!;
        }
      }
    } catch (_) {}

    _cachedConfig = const LiveKitConfig(
      url: defaultLiveKitUrl,
      apiKey: defaultApiKey,
      apiSecret: defaultApiSecret,
    );
    return _cachedConfig!;
  }

  static String get liveKitUrl => getConfig().url;

  /// Gera um token de acesso LiveKit compatível com a API de Nuvem LiveKit
  static String generateToken({
    required String roomName,
    required String identity,
    required String name,
  }) {
    final config = getConfig();
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
      issuer: config.apiKey,
      subject: identity,
    );

    return jwt.sign(
      SecretKey(config.apiSecret),
      algorithm: JWTAlgorithm.HS256,
      expiresIn: const Duration(hours: 12),
      notBefore: const Duration(seconds: -5),
    );
  }
}
