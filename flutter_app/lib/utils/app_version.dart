/// Versão deste executável, escrita aqui e só aqui.
///
/// O `installer/build_installer.ps1` lê exatamente esta linha para numerar o
/// setup.iss, o instalador e o `version.json` que o atualizador consulta. Assim
/// o número que o aplicativo carrega é sempre o número do pacote que o originou.
const String kAppVersionLabel = '1.8.0';

/// Versão do aplicativo como três números: `MAJOR.MINOR.PATCH`.
///
/// Não é decorativo: o atualizador precisa responder "a versão do servidor é
/// mais nova que a minha?" comparando números. Enquanto a versão teve letra no
/// fim (`1.0.0s`), isso não tinha ordem — `z` viria depois de `aa`, e uma
/// comparação por texto diria o contrário.
///
/// - MAJOR: mudança estrutural que não conversa com a versão anterior
///   (protocolo MQTT, formato do que está no disco, contrato da API).
/// - MINOR: recurso novo visível para quem usa.
/// - PATCH: correção ou melhoria sem recurso novo.
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;

  const AppVersion(this.major, this.minor, this.patch);

  /// A versão deste executável, lida de [kAppVersionLabel].
  ///
  /// Se um dia a constante deixar de ser um `MAJOR.MINOR.PATCH` válido, o
  /// resultado é 0.0.0: o atualizador passa a oferecer qualquer versão do
  /// servidor, o que é alto demais para passar despercebido — e nunca oferece
  /// uma atualização inexistente.
  static AppVersion get atual =>
      tryParse(kAppVersionLabel) ?? const AppVersion(0, 0, 0);

  /// Interpreta `1.2.3`. Devolve null para qualquer outra forma — inclusive as
  /// versões com letra que o projeto usava antes da v1.1.0.
  static AppVersion? tryParse(String texto) {
    final partes = texto.trim().split('.');
    if (partes.length != 3) return null;
    final numeros = <int>[];
    for (final parte in partes) {
      final n = int.tryParse(parte);
      if (n == null || n < 0) return null;
      numeros.add(n);
    }
    return AppVersion(numeros[0], numeros[1], numeros[2]);
  }

  @override
  int compareTo(AppVersion outro) {
    if (major != outro.major) return major.compareTo(outro.major);
    if (minor != outro.minor) return minor.compareTo(outro.minor);
    return patch.compareTo(outro.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
