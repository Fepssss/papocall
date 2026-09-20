import 'dart:io';

/// Raiz dos dados locais do PapoCall (`%APPDATA%\PapoCall`) e dos arquivos
/// dentro dela, com override para os testes.
///
/// Existe num único lugar porque cada serviço que montasse o próprio caminho a
/// partir de `APPDATA` continuaria escrevendo na instalação real do usuário
/// mesmo com `AppState.dataRootOverride` apontando para um diretório temporário
/// — foi assim que um teste apagou o log e quase sobrescreveu a sessão gravada.
class AppPaths {
  /// Redirecionado pelas suítes de teste; nunca definido pelo app em uso.
  static String? rootOverride;

  static Directory appData() {
    final base = rootOverride ??
        Platform.environment['APPDATA'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dir = Directory('$base\\PapoCall');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static File file(String name) => File('${appData().path}\\$name');
}
