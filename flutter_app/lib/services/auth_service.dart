import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// O pedido nunca chegou ao backend (sem rede, TLS interrompido, backend que
  /// não acorda) ou foi barrado antes de tocar no token. O refresh token está
  /// intacto: a próxima tentativa pode enviá-lo de novo.
  transientFailure,

  /// O pedido saiu desta máquina e a resposta se perdeu. O servidor pode ter
  /// rotacionado o token sem que a resposta nova chegasse; reenviar o mesmo
  /// token é exatamente o que a detecção de reuso pune com a revogação de
  /// todas as sessões da conta. A sessão local continua no disco, mas neste
  /// processo o token não volta a ser enviado.
  uncertain,
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

  /// O pedido saiu e a resposta se perdeu: não se sabe se o token girou.
  factory RefreshResult.uncertain(String reason) =>
      RefreshResult._(RefreshOutcome.uncertain, null, reason);
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

  /// Transporte usado pelo aquecimento do backend e pela renovação de sessão.
  static http.Client Function()? _transporte;

  /// Permite ao teste encenar o cold start do Render — a conexão que é segurada,
  /// a que não abre, a que responde tarde demais — sem depender da rede real.
  /// Produção não toca aqui; o `_novoCliente()` usa o transporte padrão.
  @visibleForTesting
  static set transporteDeTeste(http.Client Function()? fabrica) =>
      _transporte = fabrica;

  static http.Client _novoCliente() => _transporte?.call() ?? http.Client();

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
  ///
  /// Vai junto o `last_login.txt`, que guarda o e-mail digitado na última
  /// entrada: apagar a sessão e deixar o identificador da conta na tela de login
  /// para quem quer que abra o aplicativo depois é meio logout.
  static Future<void> clearSession({String motivo = 'logout do usuário'}) async {
    try {
      final file = await _getSessionFile();
      final existia = await file.exists();
      if (existia) {
        await file.delete();
      }
      final identificador = await _getLastIdentifierFile();
      if (await identificador.exists()) {
        await identificador.delete();
      }
      AppLog.write('Auth', 'sessão apagada ($motivo); arquivo ${existia ? 'existia' : 'não existia'}');
    } catch (e) {
      AppLog.write('Auth', 'FALHA ao apagar a sessão: $e');
    }
  }

  /// Aquece o backend em cold start (ex.: Render free) consultando /health até responder 200
  /// ou esgotar o tempo limite de espera (padrão: 60 segundos com tentativas a cada 3 segundos).
  ///
  /// A primeira consulta é paciente de propósito: o Render segura a conexão
  /// enquanto o serviço sobe e responde justamente nela quando a casa acorda.
  /// Curta mesmo são só as tentativas seguintes, quando já se sabe que alguma
  /// coisa está errada.
  static Future<bool> warmUpBackend({
    Duration totalTimeout = const Duration(seconds: 60),
    Duration retryInterval = const Duration(seconds: 3),
  }) async {
    final cliente = _novoCliente();
    final relogio = Stopwatch()..start();
    const esperaDaPrimeira = Duration(seconds: 30);
    var primeiraConsulta = true;
    try {
      while (relogio.elapsed < totalTimeout) {
        try {
          final res = await cliente
              .get(Uri.parse('$apiBaseUrl/health'))
              .timeout(primeiraConsulta && totalTimeout > esperaDaPrimeira
                  ? esperaDaPrimeira
                  : const Duration(seconds: 4));
          if (res.statusCode == 200) {
            return true;
          }
        } catch (_) {
          // Servidor ainda acordando / conectando
        }
        primeiraConsulta = false;
        await Future.delayed(retryInterval);
      }
      return false;
    } finally {
      cliente.close();
    }
  }

  static Future<bool>? _aquecimentoEmAndamento;

  /// Quanto esperar o backend acordar antes de desistir de renovar.
  static Duration _orcamentoDeAquecimento = const Duration(seconds: 45);
  static Duration _intervaloDeTentativa = const Duration(seconds: 2);

  /// Comprime a espera do portão para o teste poder atravessá-lo sem esperar
  /// 45 segundos de mundo real. Produção não chama.
  @visibleForTesting
  static void comprimirAquecimentoParaTeste(Duration orcamento) {
    _orcamentoDeAquecimento = orcamento;
    _intervaloDeTentativa = orcamento ~/ 4;
  }

  /// Uma bateria de /health por vez, não uma por chamador.
  ///
  /// É o portão que a renovação de sessão atravessa antes de qualquer
  /// credencial sair desta máquina — ver [refreshSession].
  static Future<bool> garantirBackendAcordado({
    Duration? orcamento,
  }) {
    final emAndamento = _aquecimentoEmAndamento;
    if (emAndamento != null) return emAndamento;
    final futura = warmUpBackend(
      totalTimeout: orcamento ?? _orcamentoDeAquecimento,
      retryInterval: _intervaloDeTentativa,
    );
    _aquecimentoEmAndamento = futura;
    futura.whenComplete(() {
      if (identical(_aquecimentoEmAndamento, futura)) {
        _aquecimentoEmAndamento = null;
      }
    });
    return futura;
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

  /// Códigos que o backend emite quando aquele refresh token está morto de
  /// verdade: `INVALID_REFRESH_TOKEN` (nunca existiu), `TOKEN_REUSE_DETECTED`
  /// (já foi girado, e a conta inteira teve as sessões revogadas por isso) e
  /// `REFRESH_TOKEN_EXPIRED` (passou da validade). São os únicos que justificam
  /// apagar a sessão desta máquina e mandar fazer login de novo.
  ///
  /// A lista é fechada de propósito: qualquer outro 4xx vira dúvida, não
  /// logout. Um código que este cliente ainda não conhece — validação nova no
  /// caminho, proxy que devolve 4xx — não é evidência de token queimado.
  static const Set<String> _codigosDeTokenMorto = {
    'INVALID_REFRESH_TOKEN',
    'TOKEN_REUSE_DETECTED',
    'REFRESH_TOKEN_EXPIRED',
  };

  /// 4. Renovação de Sessão via Refresh Token
  ///
  /// Distingue três coisas que antes eram a mesma: recusa definitiva do backend,
  /// falha antes de o pedido sair, e falha depois de ele ter saído. A primeira
  /// apaga a sessão; a segunda não muda nada; a terceira é a perigosa — o
  /// backend rotaciona o token e, se receber de novo um token já consumido,
  /// revoga todas as sessões da conta. Ver [RefreshOutcome.uncertain].
  static Future<RefreshResult> refreshSession(AuthSession session) async {
    if (session.refreshToken.isEmpty) {
      AppLog.write('Auth', 'refresh abortado: sessão sem refresh token');
      return RefreshResult.rejected('sem refresh token');
    }

    // O portão: o refresh token só vai para a rua depois que o backend confirma
    // no /health que está de pé. Era mandá-lo para um serviço adormecido, ver o
    // pedido morrer no timeout do cliente e reenviar um token que o servidor já
    // tinha consumido — o logout que nenhuma senha justifica.
    if (!await garantirBackendAcordado()) {
      AppLog.write('Auth', 'refresh adiado: o backend não respondeu ao /health');
      return RefreshResult.transient('backend indisponível');
    }

    const esperaDaRenovacao = Duration(seconds: 30);
    final cliente = _novoCliente();
    try {
      final res = await cliente
          .post(
            Uri.parse('$apiBaseUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': session.refreshToken}),
          )
          .timeout(esperaDaRenovacao);
      return await _avaliarRespostaDeRefresh(res, session);
    } on TimeoutException {
      // Saiu daqui e a resposta não voltou: pode ter girado o token lá fora.
      AppLog.write('Auth',
          'refresh sem resposta em ${esperaDaRenovacao.inSeconds}s: resultado incerto');
      return RefreshResult.uncertain('tempo esgotado sem resposta');
    } on SocketException catch (e) {
      final codigo = e.osError?.errorCode ?? 0;
      if (_codigosQueNaoSaemDaqui.contains(codigo)) {
        // Nada saiu desta máquina — o token continua válido para a próxima.
        AppLog.write('Auth', 'refresh sem conexão ($codigo): o pedido não chegou a sair');
        return RefreshResult.transient('sem conexão');
      }
      // Conexão cortada no meio, reiniciada pelo outro lado, ou um código que
      // este cliente não conhece: já não dá para afirmar que o servidor não viu
      // o pedido, e o reenvio é o que queima a conta.
      AppLog.write('Auth', 'refresh com transporte interrompido ($codigo): resultado incerto');
      return RefreshResult.uncertain('conexão interrompida');
    } on HandshakeException {
      AppLog.write('Auth', 'refresh com TLS interrompido: o pedido não foi entregue');
      return RefreshResult.transient('falha no TLS');
    } catch (e) {
      // Resposta truncada, HTTP excepcionado: o pedido entrou.
      AppLog.write('Auth', 'refresh com transporte interrompido: resultado incerto ($e)');
      return RefreshResult.uncertain('conexão interrompida');
    } finally {
      cliente.close();
    }
  }

  /// Erros de soquete do Windows em que a conexão nunca chegou a existir: o
  /// corpo do pedido não foi para a rua e o refresh token não queimou.
  ///
  /// Fora desta lista o caso é dúvida, e dúvida se trata como se o pedido tenha
  /// saído — ver [refreshSession].
  static const Set<int> _codigosQueNaoSaemDaqui = {
    10061, // WSAECONNREFUSED — ninguém escutando na porta
    11001, // WSATRY_AGAIN  — o DNS não resolveu agora
    11004, // WSANO_RECOVERY — o DNS não resolve de jeito nenhum
    10051, // WSAENETUNREACH — sem rota para a rede
    10065, // WSAEHOSTUNREACH — o host não atende
  };

  /// Classifica uma resposta que chegou. Aqui o pedido foi entregue, então só
  /// resta saber se o backend respondeu "não" de forma definitiva.
  static Future<RefreshResult> _avaliarRespostaDeRefresh(
    http.Response res,
    AuthSession session,
  ) async {
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      AppLog.write('Auth', 'refresh sem resposta JSON (HTTP ${res.statusCode})');
      return RefreshResult.uncertain('resposta inválida HTTP ${res.statusCode}');
    }

    if (res.statusCode == 200 && body['success'] == true) {
      final data = body['data'];
      if (data is! Map<String, dynamic>) {
        return RefreshResult.uncertain('resposta 200 sem dados');
      }
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
    AppLog.write('Auth', 'refresh HTTP ${res.statusCode} code=${code.isEmpty ? '-' : code}');

    // 429 é o limite de tentativas batendo: nada girou lá fora e a próxima pode
    // mandar o mesmo token.
    if (res.statusCode == 429) return RefreshResult.transient('muitas tentativas');

    // Os três "nãos" que o backend sabe dar para um token de renovação e que,
    // deste lado, significam a mesma coisa: a sessão acabou e só um login novo
    // resolve. Ver [_codigosDeTokenMorto].
    if (_codigosDeTokenMorto.contains(code)) return RefreshResult.rejected(code);

    // Recusa com outro código, ou sem código nenhum, não é prova de que o token
    // esteja queimado — pode ser uma validação nova no caminho, um proxy, uma
    // regra que este cliente não conhece. Derrubar o login por especulação é o
    // jeito mais rápido de fazer alguém perder a sessão à toa; ficar na dúvida
    // para de reenviar e pede reabertura, que é a saída honesta.
    if (res.statusCode >= 400 && res.statusCode < 500) {
      return RefreshResult.uncertain('HTTP ${res.statusCode} ${code.isEmpty ? '' : code}'.trim());
    }
    // 5xx: o pedido entrou, e uma falha no meio da rotação não é distinguível
    // de uma recusa limpa. Não se reenvia.
    return RefreshResult.uncertain('HTTP ${res.statusCode}');
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
