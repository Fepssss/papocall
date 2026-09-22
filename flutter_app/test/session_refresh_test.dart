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
      noRefresh: (tentativa) => tentativa == 1
          // 10061 = conexão recusada: ninguém atendeu a porta, o corpo do pedido
          // não saiu desta máquina e o token continua inteiro lá fora.
          ? SocketException('conexão recusada', osError: OSError('ninguém escutando', 10061))
          : null,
      corpoNoRefresh: _renovou,
    );
    final state = AppState()..currentSession = _sessao();

    expect(await state.renewSession(), isNull);
    final renovada = await state.renewSession();

    expect(_contar(trajeto, 'POST /auth/refresh'), 2);
    expect(renovada?.refreshToken, 'renovacao-2');
  });

  // Depois de a conexão existir, o corte já não é "nada saiu daqui": o backend
  // pode ter girado o token antes de a linha cair, e o reenvio é o que ele lê
  // como reuso — com a revogação de todas as sessões da conta.
  test('conexão cortada no meio do pedido não é reenviada', () async {
    final trajeto = _instalarBackend(
      noRefresh: (_) => SocketException('reset', osError: OSError('fora do ar', 10054)),
    );
    final state = AppState()
      ..currentSession = _sessao()
      ..isAuthenticated = true;
    await AuthService.saveSession(_sessao());

    expect(await state.renewSession(), isNull);
    expect(await state.renewSession(), isNull);

    expect(_contar(trajeto, 'POST /auth/refresh'), 1);
    expect(state.isAuthenticated, isTrue);
    expect(await AuthService.loadSession(), isNotNull);
  });

  // Descrever por qualquer 4xx foi o que fez gente perder a sessão por um código
  // que não tinha nada a ver com o token. Só os três de token morto derrubam o
  // login; o resto fica na dúvida, que não reenvia e não apaga.
  test('recusa com código que não fala do token mantém o login', () async {
    final trajeto = _instalarBackend(
      corpoNoRefresh:
          '{"success":false,"error":{"code":"VALIDATION_ERROR","message":"campo desconhecido"}}',
      statusNoRefresh: 400,
    );
    final state = AppState()
      ..currentSession = _sessao()
      ..isAuthenticated = true;
    await AuthService.saveSession(_sessao());

    expect(await state.renewSession(), isNull);
    expect(await state.renewSession(), isNull);

    expect(_contar(trajeto, 'POST /auth/refresh'), 1);
    expect(state.isAuthenticated, isTrue);
    expect(await AuthService.loadSession(), isNotNull);
  });

  for (final codigo in [
    'INVALID_REFRESH_TOKEN',
    'TOKEN_REUSE_DETECTED',
    'REFRESH_TOKEN_EXPIRED',
  ]) {
    test('o código $codigo é recusa de token e encerra o login', () async {
      _instalarBackend(
        corpoNoRefresh:
            '{"success":false,"error":{"code":"$codigo","message":"faça login de novo"}}',
        statusNoRefresh: 401,
      );
      final state = AppState()
        ..currentSession = _sessao()
        ..isAuthenticated = true;
      await AuthService.saveSession(_sessao());

      expect(await state.renewSession(), isNull);
      for (var i = 0; i < 200 && (state.isAuthenticated || await AuthService.loadSession() != null); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(state.isAuthenticated, isFalse);
      expect(await AuthService.loadSession(), isNull);
    });
  }

  // O logout apaga também o identificador guardado para pré-preencher a tela de
  // login: sair e deixar o e-mail da conta na tela para o próximo que abrir o
  // aplicativo é meio logout.
  test('sair leva o último identificador junto', () async {
    await AuthService.saveLastIdentifier('feps@exemplo.com');
    expect(await AuthService.loadLastIdentifier(), 'feps@exemplo.com');
    await AuthService.saveSession(_sessao());

    await AuthService.clearSession(motivo: 'teste');

    expect(await AuthService.loadLastIdentifier(), isEmpty);
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
