import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/services/auth_service.dart';
import 'package:papocall/utils/app_paths.dart';

import 'app_sandbox.dart';

String _b64(Map<String, dynamic> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

String _jwt(Map<String, dynamic> payload) =>
    '${_b64({'alg': 'RS256'})}.${_b64(payload)}.assinatura';

/// A claim `exp` do JWT é em segundos, como o backend emite.
int _daquiA(int minutos) =>
    DateTime.now().add(Duration(minutes: minutos)).millisecondsSinceEpoch ~/ 1000;

AuthSession _sessao({
  String accessToken = 'acesso',
  String refreshToken = 'renovacao',
}) {
  return AuthSession(
    user: AuthUser(
      id: 'u1',
      email: 'feps@exemplo.com',
      username: '@feps',
      rawUsername: 'feps',
      displayName: 'Feps',
      emailVerified: true,
    ),
    accessToken: accessToken,
    refreshToken: refreshToken,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  // O login tem de sobreviver: foi a sessão que sumiu do disco que fez o
  // usuário acreditar que a conta dele tinha deixado de existir.
  test('a sessão é gravada e lida de volta do disco', () async {
    await AuthService.saveSession(_sessao(accessToken: _jwt({'exp': _daquiA(15)})));

    final lida = await AuthService.loadSession();

    expect(lida, isNotNull);
    expect(lida!.user.rawUsername, 'feps');
    expect(lida.refreshToken, 'renovacao');
  });

  test('a sessão fica dentro da raiz em vigor, nunca na pasta real', () async {
    await AuthService.saveSession(_sessao());

    final arquivo = File(AppPaths.file('session.dat').path);
    expect(arquivo.path, contains('papocall-teste'));
    expect(await arquivo.exists(), isTrue);
  });

  test('clearSession apaga a sessão gravada', () async {
    await AuthService.saveSession(_sessao());
    expect(await AuthService.loadSession(), isNotNull);

    await AuthService.clearSession(motivo: 'teste');

    expect(await AuthService.loadSession(), isNull);
  });

  test('o @ usado no login fica gravado para o próximo acesso', () async {
    await AuthService.saveLastIdentifier('  feps@exemplo.com  ');

    expect(await AuthService.loadLastIdentifier(), 'feps@exemplo.com');
  });

  test('a validade do access token vem da claim exp do JWT', () {
    expect(AuthService.accessTokenValid(_jwt({'exp': _daquiA(15)})), isTrue);
    expect(AuthService.accessTokenValid(_jwt({'exp': _daquiA(-1)})), isFalse);
    // Menos de 2 minutos de sobra: renova antes de usar, não depois de falhar.
    final emTrintaSegundos = DateTime.now()
            .add(const Duration(seconds: 30))
            .millisecondsSinceEpoch ~/
        1000;
    expect(
      AuthService.accessTokenValid(_jwt({'exp': emTrintaSegundos})),
      isFalse,
    );
    expect(AuthService.accessTokenValid(''), isFalse);
    // Sem como ler a expiração: deixa a requisição acontecer normalmente.
    expect(AuthService.accessTokenValid('nao-e-um-jwt'), isTrue);
  });

  test('sessão sem refresh token é recusada, não renovada às cegas', () async {
    final resultado = await AuthService.refreshSession(_sessao(refreshToken: ''));

    expect(resultado.outcome, RefreshOutcome.rejected);
    expect(resultado.session, isNull);
  });
}
