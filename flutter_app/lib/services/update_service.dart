import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';

import '../utils/app_log.dart';
import '../utils/app_paths.dart';
import '../utils/app_version.dart';

/// O que o servidor anuncia como sendo a versão mais nova do aplicativo.
class UpdateManifest {
  final AppVersion version;
  final Uri url;
  final String sha256;
  final int? sizeBytes;
  final String notes;

  const UpdateManifest({
    required this.version,
    required this.url,
    required this.sha256,
    this.sizeBytes,
    this.notes = '',
  });
}

/// Falha ao baixar ou conferir o instalador, em texto pronto para a tela.
class UpdateException implements Exception {
  final String mensagem;
  const UpdateException(this.mensagem);

  @override
  String toString() => mensagem;
}

/// Resultado de conferir a versão no servidor.
///
/// [manifesto] não nulo significa "há atualização". [erro] não nulo significa
/// "não deu para conferir" — as duas coisas são diferentes para quem está na
/// tela e precisam continuar diferentes.
class UpdateCheckResult {
  final UpdateManifest? manifesto;
  final String? erro;

  const UpdateCheckResult({this.manifesto, this.erro});

  bool get haAtualizacao => manifesto != null;
}

/// Atualização do aplicativo: conferir no site, baixar e instalar sozinha.
///
/// O manifesto (`public/version.json`) é escrito pelo próprio
/// `build_installer.ps1` com o SHA-256 calculado sobre o instalador recém
/// compilado, então a soma vem do arquivo que está no ar, não de alguém
/// digitando.
///
/// O instalador roda em modo silencioso e instala por usuário
/// (`PrivilegesRequired=lowest` no setup.iss), por isso não pede senha de
/// administrador nem levanta tela de UAC.
class UpdateService {
  /// Endereço do site que distribui o aplicativo. Configuração pública.
  static const String _defaultSiteUrl = 'https://papocall.vercel.app';
  static const String _siteFromEnv = String.fromEnvironment('PAPOCALL_SITE_URL');

  static String get siteBaseUrl =>
      _siteFromEnv.isNotEmpty ? _siteFromEnv : _defaultSiteUrl;

  static Uri get manifestUrl => Uri.parse('$siteBaseUrl/version.json');

  /// Construído uma vez por chamada para que o teste possa injetar o cliente.
  static Client _novoCliente() => IOClient(HttpClient()
    ..connectionTimeout = const Duration(seconds: 8));

  static Future<UpdateCheckResult> verificar({
    required AppVersion atual,
    Client? cliente,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final dono = cliente ?? _novoCliente();
    try {
      // Parametro de cache-busting: o CDN pode servir um manifesto de semanas
      // atras e o usuario nunca fica sabendo que existe versao nova.
      final uri = manifestUrl.replace(queryParameters: {'v': atual.toString()});
      final res = await dono.get(uri).timeout(timeout);
      if (res.statusCode != 200) {
        return UpdateCheckResult(
            erro: 'O servidor de atualizações respondeu ${res.statusCode}.');
      }
      final manifesto = analisarManifesto(res.body);
      if (manifesto == null) {
        return const UpdateCheckResult(
            erro: 'A resposta do servidor de atualizações não é um manifesto válido.');
      }
      if (manifesto.version.compareTo(atual) <= 0) {
        AppLog.write('Update',
            'nada a fazer: local $atual, servidor ${manifesto.version}');
        return const UpdateCheckResult();
      }
      AppLog.write('Update',
          'atualização disponível: $atual -> ${manifesto.version}');
      return UpdateCheckResult(manifesto: manifesto);
    } on TimeoutException {
      return const UpdateCheckResult(
          erro: 'O servidor de atualizações não respondeu a tempo.');
    } catch (e) {
      AppLog.write('Update', 'consulta falhou: $e');
      return const UpdateCheckResult(
          erro: 'Não foi possível conferir as atualizações agora.');
    } finally {
      if (cliente == null) dono.close();
    }
  }

  /// Interpreta o `version.json`. Devolve null em qualquer coisa que não seja
  /// um manifesto nosso, porque executar um instalador é a ação mais
  /// destrutiva que o app pode tomar por conta própria.
  static UpdateManifest? analisarManifesto(String corpo) {
    final dynamic json;
    try {
      // Um byte-order-mark no inicio do arquivo — facil de introduzir sem
      // querer por um editor — faria todo o aplicativo recusar o manifesto.
      json = jsonDecode(corpo.replaceFirst('\uFEFF', ''));
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;

    final versao = AppVersion.tryParse(json['version'] as String? ?? '');
    if (versao == null) return null;

    final sha = (json['sha256'] as String? ?? '').toLowerCase();
    if (!_eHexSha256(sha)) return null;

    final url = Uri.tryParse(json['url'] as String? ?? '');
    if (url == null || !_eInstaladorConfiavel(url)) return null;

    final tamanho = json['sizeBytes'];
    return UpdateManifest(
      version: versao,
      url: url,
      sha256: sha,
      sizeBytes: tamanho is int && tamanho > 0 ? tamanho : null,
      notes: json['notes'] as String? ?? '',
    );
  }

  /// Só um binário entregue por nós, por HTTPS, na rota de download do site.
  /// Sem isso um `version.json` adulterado poderia apontar para qualquer .exe
  /// da internet — e o app o executaria com os privilégios do usuário.
  static bool _eInstaladorConfiavel(Uri url) {
    if (url.scheme != 'https') return false;
    final esperada = Uri.parse(siteBaseUrl);
    if (url.host != esperada.host) return false;
    final caminho = url.path.toLowerCase();
    return caminho.endsWith('.exe') && caminho.contains('/downloads/');
  }

  static bool _eHexSha256(String valor) {
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(valor);
  }

  static File arquivoDoInstalador(UpdateManifest manifesto) {
    final dir = Directory('${AppPaths.appData().path}\\updates');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}\\PapoCall-${manifesto.version}.exe');
  }

  static Future<String> sha256De(File arquivo) async {
    return sha256.convert(await arquivo.readAsBytes()).toString().toLowerCase();
  }

  /// Baixa o instalador e só devolve o arquivo depois de conferir o SHA-256:
  /// se a soma não bater, o download é apagado e nada é executado.
  static Future<File> baixar(
    UpdateManifest manifesto, {
    void Function(double progresso)? onProgress,
    Client? cliente,
  }) async {
    final destino = arquivoDoInstalador(manifesto);
    if (destino.existsSync()) {
      if (await sha256De(destino) == manifesto.sha256) return destino;
      await destino.delete();
    }

    final dono = cliente ?? _novoCliente();
    try {
      final stream = await dono
          .send(Request('GET', manifesto.url))
          .timeout(const Duration(seconds: 60));
      if (stream.statusCode != 200) {
        throw UpdateException(
            'O download do instalador falhou (HTTP ${stream.statusCode}).');
      }

      final total = stream.contentLength ?? manifesto.sizeBytes ?? -1;
      final sink = destino.openWrite();
      var recebidos = 0;
      try {
        await for (final pedaco in stream.stream) {
          sink.add(pedaco);
          recebidos += pedaco.length;
          if (total > 0) onProgress?.call((recebidos / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }

      if (await sha256De(destino) != manifesto.sha256) {
        await destino.delete();
        AppLog.write('Update', 'SHA-256 divergente; download descartado');
        throw UpdateException(
            'O instalador baixado não confere com o publicado. A atualização foi abortada.');
      }
      onProgress?.call(1);
      return destino;
    } finally {
      if (cliente == null) dono.close();
    }
  }

  /// Entrega o resto ao instalador: espera este processo morrer, roda o setup
  /// em modo silencioso e reabre o PapoCall no fim.
  ///
  /// O `Start-Sleep` existe porque o executável em uso não pode ser
  /// substituído — por isso quem chama deve fechar o aplicativo logo depois.
  static Future<void> instalarEReiniciar(String caminhoDoInstalador) async {
    final exeAtual = Platform.resolvedExecutable;
    final script = 'Start-Sleep -Seconds 3; '
        "Start-Process -FilePath '${_emAspas(caminhoDoInstalador)}' "
        "-ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait; "
        "Start-Process -FilePath '${_emAspas(exeAtual)}'";

    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ],
      mode: ProcessStartMode.detached,
    );
    AppLog.write('Update', 'instalador destacado; o app vai fechar');
  }

  /// Um nome de usuário do Windows com apóstrofo (``O'Brien``) quebraria a
  /// string entre aspas do script; em PowerShell aspa simples se duplica.
  static String _emAspas(String caminho) => caminho.replaceAll("'", "''");
}
