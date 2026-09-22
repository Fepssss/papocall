import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

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

  /// A conta cujos dados vivem em [contaFile]. `null` enquanto ninguém está
  /// logado.
  ///
  /// É isto que separa uma pessoa da outra no mesmo computador. Antes da v1.10
  /// tudo era gravado solto na raiz, e criar uma conta nova ali do lado herdava
  /// os amigos, os servidores e as conversas de quem tinha saído — inclusive o
  /// par de chaves do chat privado, com o qual a conta nova assinava mensagens
  /// como se fosse a antiga.
  static String? conta;

  static Directory appData() {
    final base = rootOverride ??
        Platform.environment['APPDATA'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dir = Directory('$base\\PapoCall');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Nome da pasta de uma conta. É um resumo do id, não o id: ele chega do
  /// servidor, e montar nome de arquivo a partir de texto que vem de fora é
  /// porta para alguém escrever fora da pasta (`..\..\`, caminho absoluto).
  static String _pastaDaConta(String id) =>
      sha256.convert(utf8.encode('papocall/conta/$id')).toString().substring(0, 16);

  /// Pasta da conta atual, ou o cofre de passagem de quem está deslogado — que
  /// nunca é lido como dados de ninguém, e assim um salvamento atrasado depois
  /// de sair não sobrescreve a lista de amigos de quem saiu.
  static Directory contaDados() {
    final atual = conta;
    final dir = Directory(
      '${appData().path}\\contas\\${atual == null ? 'sem-conta' : _pastaDaConta(atual)}',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Arquivo da instalação: sessão, último login, configurações de áudio, log,
  /// downloads de atualização. Um por computador, não por conta.
  static File file(String name) => File('${appData().path}\\$name');

  /// Arquivo de uma conta: amigos, servidores, histórico, rascunhos, chaves.
  static File contaFile(String name) => File('${contaDados().path}\\$name');
}
