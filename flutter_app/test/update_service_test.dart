import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papocall/services/update_service.dart';
import 'package:papocall/utils/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_sandbox.dart';

/// Instalador no único lugar de onde o aplicativo aceita baixar um binário.
const String urlBoa = 'https://papocall.vercel.app/downloads/PapoCall-Setup.exe';

Map<String, dynamic> _manifestoOk({String versao = '9.9.9', String url = urlBoa}) {
  return {
    'version': versao,
    'url': url,
    'sha256': 'a' * 64,
    'sizeBytes': 1234,
    'notes': 'Novidades.',
  };
}

String _json(Map<String, dynamic> corpo) => jsonEncode(corpo);

UpdateManifest _manifesto({String sha = ''}) {
  return UpdateManifest(
    version: const AppVersion(9, 9, 9),
    url: Uri.parse(urlBoa),
    sha256: sha.isEmpty ? 'a' * 64 : sha,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  group('AppVersion', () {
    test('interpreta MAJOR.MINOR.PATCH e recusa o resto', () {
      expect(AppVersion.tryParse('1.0.19'), const AppVersion(1, 0, 19));
      expect(AppVersion.tryParse(' 2.0.0 '), const AppVersion(2, 0, 0));
      // O sufixo de letra das versões antigas não tem ordem: é exatamente por
      // isso que ele deixou de existir.
      expect(AppVersion.tryParse('1.0.0s'), isNull);
      expect(AppVersion.tryParse('1.0'), isNull);
      expect(AppVersion.tryParse('1.0.0.0'), isNull);
      expect(AppVersion.tryParse('-1.0.0'), isNull);
      expect(AppVersion.tryParse(''), isNull);
    });

    test('compara por número, não por texto', () {
      // Em comparação de texto "1.10.0" viria antes de "1.2.0".
      final ordens = [
        '1.0.19',
        '1.1.0',
        '1.2.0',
        '1.10.0',
        '2.0.0',
        '10.0.0',
      ].map(AppVersion.tryParse).toList();
      for (var i = 0; i + 1 < ordens.length; i++) {
        expect(ordens[i]!.compareTo(ordens[i + 1]!), isNegative,
            reason: '${ordens[i]} deveria vir antes de ${ordens[i + 1]}');
      }
      expect(AppVersion.tryParse('1.1.0')!.compareTo(const AppVersion(1, 1, 0)),
          0);
    });

    test('a versão do aplicativo está em SemVer puro', () {
      // O build_installer.ps1 procura esta linha com uma expressão regular: se
      // ela mudar de forma, o instalador e o manifesto param de concordar.
      expect(AppVersion.tryParse(kAppVersionLabel), isNotNull);
      expect(kAppVersionLabel, AppVersion.atual.toString());
    });
  });

  group('analisarManifesto', () {
    test('aceita o formato que o build_installer.ps1 publica', () {
      final manifesto = UpdateService.analisarManifesto(_json(_manifestoOk()));

      expect(manifesto, isNotNull);
      expect(manifesto!.version, const AppVersion(9, 9, 9));
      expect(manifesto.sizeBytes, 1234);
      expect(manifesto.notes, 'Novidades.');
    });

    test('tolera um byte-order-mark no início do arquivo', () {
      expect(
        UpdateService.analisarManifesto('\uFEFF${_json(_manifestoOk())}'),
        isNotNull,
      );
    });

    test('recusa qualquer coisa que não seja um manifesto nosso', () {
      final corpos = {
        'texto solto': 'não é json',
        'lista': '[]',
        'sem versão': _json({'url': urlBoa, 'sha256': 'a' * 64}),
        'versão com letra': _json(_manifestoOk(versao: '1.0.0s')),
        'sha truncado': _json({..._manifestoOk(), 'sha256': 'a' * 63}),
        'sha com lixo': _json({..._manifestoOk(), 'sha256': '${'a' * 63}g'}),
        'instalador sem https':
            _json(_manifestoOk(url: 'http://papocall.vercel.app/downloads/PapoCall-Setup.exe')),
        'host estranho':
            _json(_manifestoOk(url: 'https://outronicho.example/downloads/PapoCall-Setup.exe')),
        'exe fora da rota de download':
            _json(_manifestoOk(url: 'https://papocall.vercel.app/outro/PapoCall-Setup.exe')),
        'nem é executável': _json(_manifestoOk(url: 'https://papocall.vercel.app/downloads/nota.txt')),
      };

      corpos.forEach((descricao, corpo) {
        expect(UpdateService.analisarManifesto(corpo), isNull,
            reason: 'recusa: $descricao');
      });
    });
  });

  group('verificar', () {
    MockClient respondendo(String corpo, {int status = 200}) {
      return MockClient((request) async => http.Response(corpo, status));
    }

    test('anuncia atualização quando o servidor tem número maior', () async {
      final resultado = await UpdateService.verificar(
        atual: const AppVersion(1, 1, 0),
        cliente: respondendo(_json(_manifestoOk(versao: '1.2.0'))),
      );

      expect(resultado.haAtualizacao, isTrue);
      expect(resultado.erro, isNull);
      expect(resultado.manifesto!.version, const AppVersion(1, 2, 0));
    });

    test('fica quieto quando a versão local já é a mais nova', () async {
      for (final versao in ['1.1.0', '1.0.19']) {
        final resultado = await UpdateService.verificar(
          atual: const AppVersion(1, 1, 0),
          cliente: respondendo(_json(_manifestoOk(versao: versao))),
        );

        expect(resultado.haAtualizacao, isFalse, reason: 'servidor em $versao');
        expect(resultado.erro, isNull);
      }
    });

    test('diz que não conseguiu conferir, em vez de mentir que está em dia',
        () async {
      final casos = [
        respondendo('{}', status: 503),
        respondendo('html de portal cativado'),
      ];

      for (final cliente in casos) {
        final resultado =
            await UpdateService.verificar(atual: const AppVersion(1, 1, 0), cliente: cliente);

        expect(resultado.haAtualizacao, isFalse);
        expect(resultado.erro, isNotNull);
      }
    });

    test('não deixa o cache do site esconder a versão nova', () async {
      Uri? pedido;
      final cliente = MockClient((request) async {
        pedido = request.url;
        return http.Response(_json(_manifestoOk(versao: '1.2.0')), 200);
      });

      await UpdateService.verificar(atual: const AppVersion(1, 1, 0), cliente: cliente);

      expect(pedido!.path, '/version.json');
      expect(pedido!.queryParameters['v'], '1.1.0');
    });
  });

  group('baixar', () {
    final bytes = utf8.encode('um instalador de mentirinha, mas com hash');
    final shaCorreto = sha256.convert(bytes).toString();

    MockClient entregandoInstalador() {
      return MockClient((request) async => http.Response.bytes(bytes, 200));
    }

    test('guarda o arquivo depois de conferir a soma', () async {
      final manifesto = _manifesto(sha: shaCorreto);

      final arquivo = await UpdateService.baixar(manifesto, cliente: entregandoInstalador());

      expect(arquivo.existsSync(), isTrue);
      expect(await UpdateService.sha256De(arquivo), shaCorreto);
      // Nunca na instalação do usuário: a pasta de dados em vigor é a do teste.
      expect(arquivo.path, contains('papocall-teste'));
      expect(arquivo.path, endsWith('PapoCall-9.9.9.exe'));
    });

    test('apaga o download e aborta quando o hash não bate', () async {
      final alvo = UpdateService.arquivoDoInstalador(_manifesto());

      await expectLater(
        UpdateService.baixar(_manifesto(), cliente: entregandoInstalador()),
        throwsA(isA<UpdateException>()),
      );
      expect(alvo.existsSync(), isFalse);
    });
  });

  group('entrega do instalador', () {
    test('anda por cmd /c start com console próprio (/min); sem isso nada roda', () {
      final cmd = UpdateService.comandoDoHandoff('Write-Output 1');

      expect(cmd.take(5).toList(), ['cmd.exe', '/c', 'start', '""', '/min']);
      expect(cmd, contains('powershell.exe'));
      // A janela do console não pode aparecer na cara de quem só atualizou.
      expect(cmd.sublist(5, cmd.length - 2), containsAll(['-WindowStyle', 'Hidden']));
      expect(cmd.last, 'Write-Output 1');
    });

    test('o script entregue roda de verdade', () async {
      final marcador = File(
        '${Directory.systemTemp.path}\\papocall_handoff_${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      if (marcador.existsSync()) marcador.deleteSync();

      final script = "Set-Content -Path '${marcador.path.replaceAll("'", "''")}' -Value 'ok'";
      // O roteiro completo, com o esconde-console na frente: se aquela linha
      // travar em alguma máquina, é aqui que isso aparece.
      final cmd =
          UpdateService.comandoDoHandoff(UpdateService.roteiroDeHandoff(script));
      await Process.start(cmd.first, cmd.sublist(1), mode: ProcessStartMode.detached);

      for (var i = 0; i < 30 && !marcador.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final rodou = marcador.existsSync();
      if (marcador.existsSync()) marcador.deleteSync();
      expect(rodou, isTrue, reason: 'o handoff destacado não chegou a executar o script');
    });
  });
}
