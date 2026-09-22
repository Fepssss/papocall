import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/role.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/services/auth_service.dart';

import 'app_sandbox.dart';

String _b64(Map<String, dynamic> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// JWT com `exp` lida pelo app; aqui sempre vencido, como na abertura do programa.
String _jwtVencido() =>
    '${_b64({'alg': 'RS256'})}.${_b64({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60})}.assinatura';

AuthSession _sessao({String refreshToken = 'renovacao-unica'}) => AuthSession(
      user: AuthUser(
        id: 'u1',
        email: 'feps@exemplo.com',
        username: '@feps',
        rawUsername: 'feps',
        displayName: 'Feps',
        emailVerified: true,
      ),
      accessToken: _jwtVencido(),
      refreshToken: refreshToken,
    );

/// O que o transporte falso atendeu, na ordem.
typedef Trajeto = List<String>;

/// Instala um backend de mentira. Só conhece `/health` e `/auth/refresh`;
/// qualquer outra requisição é erro, para o teste não escapar para a rede.
Trajeto _instalarBackend({
  Object? erroNoHealth,
  int statusNoHealth = 200,
  Object? Function(int tentativa)? noRefresh,
  String corpoNoRefresh = '',
  int statusNoRefresh = 200,
}) {
  final trajeto = <String>[];
  var tentativasDeRefresh = 0;
  AuthService.transporteDeTeste = () => MockClient((req) async {
        final caminho = '/${req.url.pathSegments.join('/')}';
        trajeto.add('${req.method} $caminho');
        if (caminho == '/health') {
          if (erroNoHealth != null) throw erroNoHealth;
          return http.Response('', statusNoHealth);
        }
        if (caminho == '/auth/refresh') {
          tentativasDeRefresh++;
          final erro = noRefresh?.call(tentativasDeRefresh);
          if (erro != null) throw erro;
          return http.Response(corpoNoRefresh, statusNoRefresh);
        }
        throw StateError('requisição fora do ensaio: ${req.method} $caminho');
      });
  return trajeto;
}

int _contar(Trajeto trajeto, String passo) =>
    trajeto.where((c) => c == passo).length;

const _renovou =
    '{"success":true,"data":{"accessToken":"novo-acesso","refreshToken":"renovacao-2"}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  setUp(() => AuthService.comprimirAquecimentoParaTeste(const Duration(milliseconds: 120)));
  tearDown(() => AuthService.transporteDeTeste = null);

  // O ponto de tudo: o que derrubava o login era o token de renovação viajar
  // para um Render adormecido, o cliente desistir e o reenvio cair na detecção
  // de reuso. Primeiro se prova que a casa está acordada.
  test('sem o /health respondendo, o token de renovação não sai da máquina', () async {
    final trajeto = _instalarBackend(erroNoHealth: const SocketException('sem rota'));

    final resultado = await AuthService.refreshSession(_sessao());

    expect(resultado.outcome, RefreshOutcome.transientFailure);
    expect(_contar(trajeto, 'POST /auth/refresh'), 0);
    expect(_contar(trajeto, 'GET /health'), greaterThan(0));
  });

  test('o /health é consultado antes do pedido de renovação', () async {
    final trajeto = _instalarBackend(corpoNoRefresh: _renovou);

    final resultado = await AuthService.refreshSession(_sessao());

    expect(resultado.outcome, RefreshOutcome.renewed);
    expect(trajeto.first, 'GET /health');
    expect(trajeto.last, 'POST /auth/refresh');
  });

  test('renovação bem-sucedida grava o token novo no disco', () async {
    _instalarBackend(corpoNoRefresh: _renovou);

    await AuthService.refreshSession(_sessao());

    final gravada = await AuthService.loadSession();
    expect(gravada?.refreshToken, 'renovacao-2');
  });

  // O caso que fazia a conta "desaparecer": o pedido saiu, a resposta não
  // voltou. Não há como saber se o servidor girou o token, e insistir é justo
  // o que ele pune com a revogação de tudo.
  test('envio sem resposta não reenvia o mesmo token nem apaga a sessão', () async {
    final trajeto = _instalarBackend(
      noRefresh: (_) => TimeoutException('o Render segurou e não respondeu'),
    );
    final state = AppState()
      ..currentSession = _sessao()
      ..isAuthenticated = true;
    await AuthService.saveSession(_sessao());

    expect(await state.renewSession(), isNull);
    expect(await state.renewSession(), isNull);
    expect(await state.renewSession(), isNull);

    expect(_contar(trajeto, 'POST /auth/refresh'), 1);
    // A sessão continua no disco e o usuário continua logado: quem decide sair
    // é o servidor, nunca um timeout.
    expect(state.isAuthenticated, isTrue);
    expect(await AuthService.loadSession(), isNotNull);
  });

  test('falha antes de sair permite tentar de novo na hora seguinte', () async {
    final trajeto = _instalarBackend(
      noRefresh: (tentativa) =>
          tentativa == 1 ? const SocketException('conexão caiu') : null,
      corpoNoRefresh: _renovou,
    );
    final state = AppState()..currentSession = _sessao();

    expect(await state.renewSession(), isNull);
    final renovada = await state.renewSession();

    expect(_contar(trajeto, 'POST /auth/refresh'), 2);
    expect(renovada?.refreshToken, 'renovacao-2');
  });

  test('recusa definitiva do servidor ainda encerra o login', () async {
    _instalarBackend(
      corpoNoRefresh:
          '{"success":false,"error":{"code":"TOKEN_REUSE_DETECTED","message":"sessões encerradas"}}',
      statusNoRefresh: 401,
    );
    final state = AppState()
      ..currentSession = _sessao()
      ..isAuthenticated = true;
    await AuthService.saveSession(_sessao());

    expect(await state.renewSession(), isNull);

    // O logout é agendado sem espera para não travar quem estava renovando;
    // aqui ele é acompanhado até acontecer de verdade.
    for (var i = 0; i < 200 && (state.isAuthenticated || await AuthService.loadSession() != null); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(state.isAuthenticated, isFalse);
    expect(await AuthService.loadSession(), isNull);
  });

  // A entrada na call é onde o usuário vê o problema: sem token e com a
  // renovação em dúvida, o motivo dito tem que ser o real e o que resolve.
  test('entrar na call com a renovação em dúvida diz o que fazer, sem deslogar', () async {
    final trajeto = _instalarBackend(
      noRefresh: (_) => TimeoutException('o Render segurou e não respondeu'),
    );
    final state = AppState()
      ..servers.add(_servidorComCanal())
      ..currentSession = _sessao()
      ..isAuthenticated = true;

    expect(await state.renewSession(), isNull);
    final motivo = await state.connectVoice('srv-1-v-geral');

    expect(motivo, contains('Feche e abra'));
    expect(_contar(trajeto, 'POST /auth/refresh'), 1);
    expect(state.isAuthenticated, isTrue);
  });
}

Server _servidorComCanal() => Server(
      id: 'srv-1',
      name: 'Servidor',
      inviteCode: '',
      ownerId: 'u1',
      memberIds: ['u1'],
      roles: ServerRole.defaults(),
      channels: [
        Channel(id: 'srv-1-v-geral', name: 'Sala de Voz', type: ChannelType.voice),
      ],
    );
