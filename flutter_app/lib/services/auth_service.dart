import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../utils/app_log.dart';
import '../utils/app_paths.dart';
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

enum RefreshOutcome {
  /// Servidor emitiu tokens novos; a sessão antiga foi substituída.
  renewed,

  /// Servidor recusou o refresh token de forma definitiva. Só nesse caso a
  /// sessão local pode ser apagada e o login refeito.
  rejected,

  /// Rede, timeout, cold start do Render, 5xx ou resposta sem JSON.
  /// A sessão continua válida: apagar por um erro momentâneo é o que fazia a
  /// conta "desaparecer" para o usuário.
  transientFailure,
}

class RefreshResult {
  final RefreshOutcome outcome;
  final AuthSession? session;
  final String reason;

  const RefreshResult._(this.outcome, this.session, this.reason);

  factory RefreshResult.renewed(AuthSession session) =>
      RefreshResult._(RefreshOutcome.renewed, session, '');
  factory RefreshResult.rejected(String reason) =>
      RefreshResult._(RefreshOutcome.rejected, null, reason);
  factory RefreshResult.transient(String reason) =>
      RefreshResult._(RefreshOutcome.transientFailure, null, reason);
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
  static const String _defaultApiUrl = 'https://papocall.onrender.com';
  static const String _apiUrlFromEnv = String.fromEnvironment('PAPOCALL_API_URL');

  static String get apiBaseUrl =>
      _apiUrlFromEnv.isNotEmpty ? _apiUrlFromEnv : _defaultApiUrl;

  static Future<File> _getLastIdentifierFile() async => AppPaths.file('last_login.txt');

  static Future<void> saveLastIdentifier(String identifier) async {
    try {
      final file = await _getLastIdentifierFile();
      await file.writeAsString(identifier.trim());
    } catch (_) {}
  }

  static Future<String> loadLastIdentifier() async {
    try {
      final file = await _getLastIdentifierFile();
      if (await file.exists()) {
        return (await file.readAsString()).trim();
      }
    } catch (_) {}
    return '';
  }

  static Future<File> _getSessionFile() async => AppPaths.file('session.dat');

  /// Salva a sessão cifrada com a DPAPI do Windows.
  ///
  /// Se a criptografia falhar, a sessão simplesmente não é persistida: gravar
  /// os tokens em texto puro como alternativa seria pior do que pedir um novo
  /// login na próxima abertura do app.
  static Future<void> saveSession(AuthSession session) async {
    try {
      final file = await _getSessionFile();
      final ok = await SecureStorage.writeEncrypted(file, jsonEncode(session.toJson()));
      if (ok) {
        AppLog.write('Auth',
            'sessão gravada para @${session.user.rawUsername} (expira ${accessTokenExpiry(session.accessToken)?.toIso8601String() ?? '?'})');
      } else {
        if (await file.exists()) {
          // O arquivo antigo guarda um refresh token já consumido: mantê-lo
          // levaria a um TOKEN_REUSE_DETECTED na próxima abertura.
          await file.delete();
        }
        AppLog.write('Auth', 'FALHA ao cifrar a sessão (DPAPI); arquivo removido');
      }
    } catch (e) {
      AppLog.write('Auth', 'FALHA ao gravar a sessão: $e');
    }
  }

  /// Carrega e decifra a sessão persistida.
  static Future<AuthSession?> loadSession() async {
    try {
      final file = await _getSessionFile();
      final content = await SecureStorage.readEncrypted(file);
      if (content == null || content.isEmpty) {
        if (!await file.exists()) {
          AppLog.write('Auth', 'nenhum session.dat em disco');
        } else {
          AppLog.write('Auth', 'session.dat ilegível (DPAPI recusou o conteúdo)');
        }
        return null;
      }
      final json = jsonDecode(content) as Map<String, dynamic>;
      final session = AuthSession.fromJson(json);
      AppLog.write('Auth',
          'sessão lida de @${session.user.rawUsername}, access token expira ${accessTokenExpiry(session.accessToken)?.toIso8601String() ?? '?'}');
      return session;
    } catch (e) {
      AppLog.write('Auth', 'FALHA ao ler a sessão: $e');
      return null;
    }
  }

  /// Apaga resquícios das versões anteriores, que gravavam tokens e hashes de
  /// senha em texto puro no disco.
  static Future<void> purgeLegacyInsecureFiles() async {
    try {
      for (final name in ['session.json', 'users_vault.json', 'livekit.json']) {
        final legacy = AppPaths.file(name);
        if (await legacy.exists()) {
          await legacy.delete();
        }
      }
    } catch (_) {}
  }

  /// Remove a sessão (logout)
  static Future<void> clearSession({String motivo = 'logout do usuário'}) async {
    try {
      final file = await _getSessionFile();
      final existia = await file.exists();
      if (existia) {
        await file.delete();
      }
      AppLog.write('Auth', 'sessão apagada ($motivo); arquivo ${existia ? 'existia' : 'não existia'}');
    } catch (e) {
      AppLog.write('Auth', 'FALHA ao apagar a sessão: $e');
    }
  }

  /// Aquece o backend em cold start (ex.: Render free) consultando /health até responder 200
  /// ou esgotar o tempo limite de espera (padrão: 60 segundos com tentativas a cada 3 segundos).
  static Future<bool> warmUpBackend({
    Duration totalTimeout = const Duration(seconds: 60),
    Duration retryInterval = const Duration(seconds: 3),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < totalTimeout) {
      try {
        final res = await http.get(Uri.parse('$apiBaseUrl/health')).timeout(
          const Duration(seconds: 4),
        );
        if (res.statusCode == 200) {
          return true;
        }
      } catch (_) {
        // Servidor ainda acordando / conectando
      }
      await Future.delayed(retryInterval);
    }
    return false;
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
      await saveLastIdentifier(email.trim().toLowerCase());
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
      await saveLastIdentifier(cleanIdentifier);
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

  /// Verifica se uma conta com este @username realmente existe.
  ///
  /// Reaproveita o endpoint de disponibilidade: um username indisponível é,
  /// por definição, um username já registrado. Sem esta checagem era possível
  /// "enviar" solicitação de amizade para qualquer texto digitado — o app
  /// confirmava o envio e a solicitação simplesmente ia para um tópico que
  /// nenhuma conta escuta.
  ///
  /// Retorna null quando o backend não responde: nesse caso a checagem é
  /// inconclusiva e não deve bloquear o usuário.
  static Future<bool?> userExists(String rawUsername) async {
    final clean = rawUsername.replaceAll('@', '').trim().toLowerCase();
    if (clean.isEmpty) return false;

    final uri = Uri.parse(
      '$apiBaseUrl/auth/username-available?username=${Uri.encodeQueryComponent(clean)}',
    );

    // Três tentativas: o backend roda em plano gratuito e hiberna após alguns
    // minutos ociosos. O cold start medido fica em torno de 25s, e uma única
    // tentativa expiraria justamente quando o serviço está acordando — o que
    // faria o app dizer "não foi possível confirmar" para uma tag que existe.
    for (var tentativa = 0; tentativa < 3; tentativa++) {
      try {
        final res = await http.get(uri).timeout(const Duration(seconds: 12));

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final data = body['data'] as Map<String, dynamic>?;
          if (data == null) return null;
          final available = data['available'];
          if (available is! bool) return null;
          return !available;
        }

        // 400 é a resposta de validação do backend: a tag está num formato que
        // nenhuma conta pode ter. Outros erros (429 de limite de consultas,
        // 5xx) não dizem nada sobre a existência da conta e ficam inconclusivos.
        if (res.statusCode == 400) return false;
      } catch (_) {
        // Tenta de novo antes de desistir.
      }
      if (tentativa < 2) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    return null;
  }

  /// 4. Renovação de Sessão via Refresh Token
  ///
  /// Distingue recusa definitiva de erro momentâneo. O backend sempre responde
  /// em JSON nos erros de autenticação; qualquer outra coisa (rede, timeout,
  /// cold start do plano gratuito, 5xx, página de proxy) não apaga a sessão.
  static Future<RefreshResult> refreshSession(AuthSession session) async {
    if (session.refreshToken.isEmpty) {
      AppLog.write('Auth', 'refresh abortado: sessão sem refresh token');
      return RefreshResult.rejected('sem refresh token');
    }

    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': session.refreshToken}),
      ).timeout(const Duration(seconds: 15));

      Map<String, dynamic>? decodificado;
      try {
        decodificado = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        AppLog.write(
            'Auth', 'refresh sem resposta JSON (HTTP ${res.statusCode})');
        return RefreshResult.transient('resposta inválida HTTP ${res.statusCode}');
      }
      final body = decodificado;

      if (res.statusCode == 200 && body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>;
        final newSession = AuthSession(
          accessToken: data['accessToken'] as String? ?? session.accessToken,
          refreshToken: data['refreshToken'] as String? ?? session.refreshToken,
          user: session.user,
        );
        await saveSession(newSession);
        AppLog.write('Auth',
            'sessão renovada para @${session.user.rawUsername}, nova expiração ${accessTokenExpiry(newSession.accessToken)?.toIso8601String() ?? 'desconhecida'}');
        return RefreshResult.renewed(newSession);
      }

      final code = (body['error']?['code'] as String?) ?? '';
      final recusado = res.statusCode >= 400 &&
          res.statusCode < 500 &&
          res.statusCode != 429 &&
          code.isNotEmpty;
      AppLog.write('Auth',
          'refresh HTTP ${res.statusCode} code=${code.isEmpty ? '-' : code}');
      return recusado
          ? RefreshResult.rejected(code)
          : RefreshResult.transient('HTTP ${res.statusCode}');
    } catch (e) {
      AppLog.write('Auth', 'refresh falhou na rede: $e');
      return RefreshResult.transient('erro de rede');
    }
  }

  /// Instante em que o access token JWT expira, lido da claim `exp`.
  ///
  /// O payload é público (o JWT já viaja na autorização da requisição); nada é
  /// decifrado aqui, apenas base64. Retorna null se o token não for um JWT
  /// legível, caso em que o chamador deve apenas tentar a requisição.
  static DateTime? accessTokenExpiry(String jwt) {
    try {
      final partes = jwt.split('.');
      if (partes.length != 3) return null;
      final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))))
          as Map<String, dynamic>;
      final exp = payload['exp'] as int?;
      if (exp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (_) {
      return null;
    }
  }

  /// True quando o access token ainda tem mais de [margem] de vida.
  static bool accessTokenValid(String jwt, {Duration margem = const Duration(minutes: 2)}) {
    if (jwt.isEmpty) return false;
    final exp = accessTokenExpiry(jwt);
    if (exp == null) return true;
    return exp.difference(DateTime.now()) > margem;
  }
}
