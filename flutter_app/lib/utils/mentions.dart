/// Marcações de usuário no chat (`@fulano`).
///
/// A marcação vive no próprio texto da mensagem, e não numa lista paralela no
/// envelope: assim ela continua funcionando no histórico recebido de outro
/// membro, em mensagens de versões anteriores e em qualquer cópia do texto,
/// sem depender de metadado que possa se perder pelo caminho.
library;

/// Regras iguais às do backend para @username: 3 a 20 caracteres, apenas
/// letras, números e underscore.
///
/// As duas fronteiras não são enfeite:
/// - `(?<![A-Za-z0-9_@])` impede que um e-mail (`fulano@dominio.com`) ou um
///   `@@` vire marcação;
/// - `(?![A-Za-z0-9_])` impede que um @ longo demais seja aceito pelos seus 20
///   primeiros caracteres. Sem ela, `@nomeexageradamentelongo` marcaria
///   `@nomeexageradamentelon` — isto é, outra pessoa, ou ninguém.
final RegExp mentionPattern =
    RegExp(r'(?<![A-Za-z0-9_@])@([A-Za-z0-9_]{3,20})(?![A-Za-z0-9_])');

/// Os padrões ficam fora das funções: [mentionQueryAt] e [normalizeHandle]
/// rodam a cada tecla digitada no campo de mensagem e cada varredura de não
/// lidos, e compilar a expressão dentro do laço criava uma expressão nova por
/// caractere percorrido.
final RegExp arrobaInicial = RegExp(r'^@');
final RegExp caractereDeHandle = RegExp('[A-Za-z0-9_]');
final RegExp caractereAntesDeArroba = RegExp('[A-Za-z0-9_@]');

/// Normaliza um @ para a forma usada em comparações: minúsculo e sem o arroba.
String normalizeHandle(String raw) =>
    raw.trim().replaceFirst(arrobaInicial, '').toLowerCase();

/// Extrai, em minúsculas e sem repetição, todos os @ citados em [text].
Set<String> extractMentions(String text) {
  if (text.isEmpty || !text.contains('@')) return const {};
  return mentionPattern
      .allMatches(text)
      .map((m) => m.group(1)!.toLowerCase())
      .toSet();
}

/// Indica se [text] marca [username].
bool mentionsUser(String text, String username) {
  final alvo = normalizeHandle(username);
  if (alvo.isEmpty) return false;
  return extractMentions(text).contains(alvo);
}

/// Um trecho de texto já classificado para renderização.
class MentionSegment {
  final String text;

  /// O @ citado, em minúsculas, quando este trecho é uma marcação.
  final String? handle;

  /// Verdadeiro quando a marcação aponta para quem está lendo.
  final bool isSelf;

  const MentionSegment(this.text, {this.handle, this.isSelf = false});

  bool get isMention => handle != null;
}

/// Quebra [text] em trechos comuns e marcações, para a interface pintar cada um
/// do seu jeito.
///
/// [knownHandles] limita o destaque a quem realmente existe no contexto do
/// leitor (membros do servidor e amigos): sem isso, qualquer `@qualquercoisa`
/// ganharia aparência de marcação válida e daria a impressão de que alguém foi
/// avisado quando não foi. [selfHandle] recebe o destaque mais forte.
List<MentionSegment> splitMentions(
  String text, {
  required Set<String> knownHandles,
  required String selfHandle,
}) {
  if (text.isEmpty) return const [];

  final eu = normalizeHandle(selfHandle);
  final segmentos = <MentionSegment>[];
  var cursor = 0;

  for (final match in mentionPattern.allMatches(text)) {
    final handle = match.group(1)!.toLowerCase();
    final reconhecido = handle == eu || knownHandles.contains(handle);
    if (!reconhecido) continue;

    if (match.start > cursor) {
      segmentos.add(MentionSegment(text.substring(cursor, match.start)));
    }
    segmentos.add(MentionSegment(
      text.substring(match.start, match.end),
      handle: handle,
      isSelf: handle == eu,
    ));
    cursor = match.end;
  }

  if (cursor < text.length) {
    segmentos.add(MentionSegment(text.substring(cursor)));
  }
  return segmentos;
}

/// Localiza a marcação sendo digitada imediatamente antes do cursor.
///
/// Retorna null quando o cursor não está logo após um `@parcial`, que é o caso
/// em que o autocompletar não deve aparecer.
MentionQuery? mentionQueryAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;

  var i = cursor - 1;
  while (i >= 0) {
    final c = text[i];
    if (c == '@') break;
    if (!caractereDeHandle.hasMatch(c)) return null;
    i--;
  }
  if (i < 0 || text[i] != '@') return null;

  // Evita disparar dentro de um e-mail ou de um @@.
  if (i > 0 && caractereAntesDeArroba.hasMatch(text[i - 1])) return null;

  final parcial = text.substring(i + 1, cursor);
  if (parcial.length > 20) return null;

  return MentionQuery(start: i, end: cursor, term: parcial.toLowerCase());
}

class MentionQuery {
  /// Posição do '@' no texto.
  final int start;

  /// Posição do cursor (fim do trecho já digitado).
  final int end;

  /// O que foi digitado depois do '@', em minúsculas.
  final String term;

  const MentionQuery({required this.start, required this.end, required this.term});
}
