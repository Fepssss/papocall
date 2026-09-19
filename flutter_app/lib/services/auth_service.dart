import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';

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
  static const String defaultApiUrl = 'http://localhost:3333';

  static Future<File> _getSessionFile() async {
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    final dir = Directory('$appData\\PapoCall');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}\\session.json');
  }

  static Future<File> _getLocalVaultFile() async {
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    final dir = Directory('$appData\\PapoCall');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}\\users_vault.json');
  }

  /// Salva a sessão ativa no disco local
  static Future<void> saveSession(AuthSession session) async {
    try {
      final file = await _getSessionFile();
      await file.writeAsString(jsonEncode(session.toJson()));
    } catch (e) {
      // Falha silenciosa de escrita de cache
    }
  }

  /// Carrega a sessão ativa do disco local
  static Future<AuthSession?> loadSession() async {
    try {
      final file = await _getSessionFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          return AuthSession.fromJson(json);
        }
      }
    } catch (_) {}
    return null;
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

  /// Verifica se o backend HTTP está ativo
  static Future<bool> isBackendReachable() async {
    try {
      final res = await http.get(Uri.parse('$defaultApiUrl/health')).timeout(
        const Duration(milliseconds: 1200),
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

    // Tenta conectar ao backend oficial na porta 3333
    if (await isBackendReachable()) {
      final res = await http.post(
        Uri.parse('$defaultApiUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim().toLowerCase(),
          'username': cleanUsername,
          'displayName': displayName.trim(),
          'password': password,
        }),
      );

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 201 && body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>;
        final session = AuthSession.fromJson(data);
        await saveSession(session);
        return session;
      } else {
        final errorMsg = body['error']?['message'] as String? ??
            'Não foi possível criar a conta. Verifique os dados.';
        throw Exception(errorMsg);
      }
    }

    // Fallback de Autenticação Local Resiliente (para quando o Node não estiver rodando)
    return await _localRegister(
      email: email.trim().toLowerCase(),
      username: cleanUsername,
      displayName: displayName.trim(),
      password: password,
    );
  }

  /// 2. Login (por E-mail OU @username)
  static Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    final cleanIdentifier = identifier.trim();

    if (await isBackendReachable()) {
      final res = await http.post(
        Uri.parse('$defaultApiUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identifier': cleanIdentifier,
          'password': password,
        }),
      );

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>;
        final session = AuthSession.fromJson(data);
        await saveSession(session);
        return session;
      } else {
        final errorMsg = body['error']?['message'] as String? ??
            'Credenciais inválidas. Verifique seu e-mail/username e senha.';
        throw Exception(errorMsg);
      }
    }

    // Fallback Local Resiliente
    return await _localLogin(
      identifier: cleanIdentifier,
      password: password,
    );
  }

  /// 3. Checagem de Disponibilidade de Username em Tempo Real
  static Future<UsernameAvailabilityResult> checkUsernameAvailable(String rawUsername) async {
    final clean = rawUsername.replaceAll('@', '').trim().toLowerCase();
    if (clean.length < 3) {
      return UsernameAvailabilityResult(available: false, username: '@$clean');
    }

    if (await isBackendReachable()) {
      try {
        final res = await http.get(
          Uri.parse('$defaultApiUrl/auth/username-available?username=$clean'),
        );
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
    }

    // Checagem no cofre local
    final vault = await _loadVault();
    final isTaken = vault.any((u) => (u['username'] as String).toLowerCase() == clean);
    final suggestions = isTaken
        ? ['@${clean}1', '@${clean}_', '@${clean}2026']
        : <String>[];

    return UsernameAvailabilityResult(
      available: !isTaken,
      username: '@$clean',
      suggestions: suggestions,
    );
  }

  // ===========================================================================
  // IMPLEMENTAÇÃO DO COFRE LOCAL RESILIENTE
  // ===========================================================================

  static Future<List<Map<String, dynamic>>> _loadVault() async {
    try {
      final file = await _getLocalVaultFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          final list = jsonDecode(raw) as List<dynamic>;
          return list.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<void> _saveVault(List<Map<String, dynamic>> vault) async {
    final file = await _getLocalVaultFile();
    await file.writeAsString(jsonEncode(vault));
  }

  static String _hashPassword(String password) {
    final bytes = utf8.encode('papocall_salt_$password');
    return sha256.convert(bytes).toString();
  }

  static Future<AuthSession> _localRegister({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) async {
    final vault = await _loadVault();

    if (vault.any((u) => u['email'] == email)) {
      throw Exception('Este endereço de e-mail já está cadastrado em outra conta.');
    }

    if (vault.any((u) => u['username'] == username)) {
      throw Exception('O nome de usuário \'@$username\' já está em uso.');
    }

    final newUser = {
      'id': 'user-${DateTime.now().millisecondsSinceEpoch}',
      'email': email,
      'username': username,
      'displayName': displayName,
      'passwordHash': _hashPassword(password),
      'emailVerified': true,
      'createdAt': DateTime.now().toIso8601String(),
    };

    vault.add(newUser);
    await _saveVault(vault);

    final user = AuthUser(
      id: newUser['id'] as String,
      email: email,
      username: '@$username',
      rawUsername: username,
      displayName: displayName,
      emailVerified: true,
    );

    final session = AuthSession(
      user: user,
      accessToken: 'local-token-${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'local-refresh-${DateTime.now().millisecondsSinceEpoch}',
    );

    await saveSession(session);
    return session;
  }

  static Future<AuthSession> _localLogin({
    required String identifier,
    required String password,
  }) async {
    final vault = await _loadVault();
    final cleanId = identifier.replaceAll('@', '').toLowerCase();
    final passwordHash = _hashPassword(password);

    final found = vault.firstWhere(
      (u) =>
          (u['email'] as String).toLowerCase() == cleanId ||
          (u['username'] as String).toLowerCase() == cleanId,
      orElse: () => {},
    );

    if (found.isEmpty || found['passwordHash'] != passwordHash) {
      throw Exception('Credenciais inválidas. Verifique seu e-mail/username e senha.');
    }

    final user = AuthUser(
      id: found['id'] as String,
      email: found['email'] as String,
      username: '@${found['username']}',
      rawUsername: found['username'] as String,
      displayName: found['displayName'] as String,
      emailVerified: found['emailVerified'] as bool? ?? true,
    );

    final session = AuthSession(
      user: user,
      accessToken: 'local-token-${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'local-refresh-${DateTime.now().millisecondsSinceEpoch}',
    );

    await saveSession(session);
    return session;
  }
}
