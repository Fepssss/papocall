import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import 'secure_storage.dart';

class AuthUser {
  final String id;
  final String email;
  final String username;     // Ex: '@joaosilva'
  final String rawUsername;  // Ex: 'joaosilva'
  final String displayName;
  final bool emailVerified;

  AuthUser({
    required this.id,
    required this.email,
    required this.username,
    required this.rawUsername,
    required this.displayName,
    required this.emailVerified,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawUser = (json['rawUsername'] as String? ?? json['username'] as String? ?? '')
        .replaceAll('@', '')
        .trim()
        .toLowerCase();
    final disp = json['displayName'] as String? ?? json['display_name'] as String? ?? rawUser;

    return AuthUser(
      id: json['id'] as String? ?? 'user-${DateTime.now().millisecondsSinceEpoch}',
      email: json['email'] as String? ?? '',
      username: '@$rawUser',
      rawUsername: rawUser,
      displayName: disp,
      emailVerified: json['emailVerified'] as bool? ?? json['email_verified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'username': username,
    'rawUsername': rawUsername,
    'displayName': displayName,
    'emailVerified': emailVerified,
  };

  UserModel toUserModel() {
    final cleanUser = (rawUsername.isNotEmpty ? rawUsername : username)
        .replaceAll('@', '')
        .trim();
    return UserModel(
      id: id,
      username: cleanUser,
      displayName: displayName,
      status: UserStatus.online,
    );
  }
}

class AuthSession {
  final AuthUser user;
  final String accessToken;
  final String refreshToken;

  AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };
}

class UsernameAvailabilityResult {
  final bool available;
  final String username;
  final List<String> suggestions;

  UsernameAvailabilityResult({
    required this.available,
    required this.username,
    this.suggestions = const [],
  });
}

class AuthService {
  /// Endereço do backend, injetado no build (--dart-define=PAPOCALL_API_URL).
  ///
  /// Precisa ser HTTPS: até a v1.0.0f o app apontava para 'http://localhost:3333',
  /// endereço que nunca existe na máquina de um usuário final — o que fazia todo
  /// login cair num cofre local inseguro, hoje removido.
  static const String _apiUrlFromEnv = String.fromEnvironment('PAPOCALL_API_URL');

  static String get apiBaseUrl =>
      _apiUrlFromEnv.isNotEmpty ? _apiUrlFromEnv : 'https://papocall.vercel.app';

  static Future<File> _getSessionFile() async {
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    final dir = Directory('$appData\\PapoCall');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}\\session.dat');
  }

  /// Salva a sessão cifrada com a DPAPI do Windows.
  ///
  /// Se a criptografia falhar, a sessão simplesmente não é persistida: gravar
  /// os tokens em texto puro como alternativa seria pior do que pedir um novo
  /// login na próxima abertura do app.
  static Future<void> saveSession(AuthSession session) async {
    try {
      final file = await _getSessionFile();
      final ok = await SecureStorage.writeEncrypted(file, jsonEncode(session.toJson()));
      if (!ok && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Carrega e decifra a sessão persistida.
  static Future<AuthSession?> loadSession() async {
    try {
      final file = await _getSessionFile();
      final content = await SecureStorage.readEncrypted(file);
      if (content != null && content.isNotEmpty) {
        final json = jsonDecode(content) as Map<String, dynamic>;
        return AuthSession.fromJson(json);
      }
    } catch (_) {}
    return null;
  }

  /// Apaga resquícios das versões anteriores, que gravavam tokens e hashes de
  /// senha em texto puro no disco.
  static Future<void> purgeLegacyInsecureFiles() async {
    try {
      final appData = Platform.environment['APPDATA'] ??
          Platform.environment['USERPROFILE'] ??
          Directory.current.path;
      for (final name in ['session.json', 'users_vault.json', 'livekit.json']) {
        final legacy = File('$appData\\PapoCall\\$name');
        if (await legacy.exists()) {
          await legacy.delete();
        }
      }
    } catch (_) {}
  }

  /// Remove a sessão (logout)
  static Future<void> clearSession() async {
    try {
      final file = await _getSessionFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Verifica se o backend HTTP está ativo (usado apenas para diagnóstico na UI).
  static Future<bool> isBackendReachable() async {
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/health')).timeout(
        const Duration(seconds: 5),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 1. Registro de Usuário
  static Future<AuthSession> register({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) async {
    final cleanUsername = username.replaceAll('@', '').trim().toLowerCase();

    final res = await http.post(
      Uri.parse('$apiBaseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'username': cleanUsername,
        'displayName': displayName.trim(),
        'password': password,
      }),
    ).timeout(const Duration(seconds: 15));

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 201 && body['success'] == true) {
      final data = body['data'] as Map<String, dynamic>;
      final session = AuthSession.fromJson(data);
      await saveSession(session);
      return session;
    }

    throw Exception(
      body['error']?['message'] as String? ??
          'Não foi possível criar a conta. Verifique os dados.',
    );
  }

  /// 2. Login (por E-mail OU @username)
  static Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    final cleanIdentifier = identifier.trim();

    final res = await http.post(
      Uri.parse('$apiBaseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identifier': cleanIdentifier,
        'password': password,
      }),
    ).timeout(const Duration(seconds: 15));

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 200 && body['success'] == true) {
      final data = body['data'] as Map<String, dynamic>;
      final session = AuthSession.fromJson(data);
      await saveSession(session);
      return session;
    }

    throw Exception(
      body['error']?['message'] as String? ??
          'Credenciais inválidas. Verifique seu e-mail/username e senha.',
    );
  }

  /// 3. Checagem de Disponibilidade de Username em Tempo Real
  static Future<UsernameAvailabilityResult> checkUsernameAvailable(String rawUsername) async {
    final clean = rawUsername.replaceAll('@', '').trim().toLowerCase();
    if (clean.length < 3) {
      return UsernameAvailabilityResult(available: false, username: '@$clean');
    }

    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/auth/username-available?username=${Uri.encodeQueryComponent(clean)}'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        final suggestions = (data['suggestions'] as List<dynamic>?)
                ?.map((s) => s.toString())
                .toList() ??
            [];
        return UsernameAvailabilityResult(
          available: data['available'] == true,
          username: data['username'] as String? ?? '@$clean',
          suggestions: suggestions,
        );
      }
    } catch (_) {}

    // Sem resposta do servidor não há como afirmar que o @ está livre.
    // Reportar 'disponível' aqui levaria o usuário a um registro que falha.
    return UsernameAvailabilityResult(available: false, username: '@$clean');
  }
}
