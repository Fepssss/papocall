class ChatMessage {
  final String id;
  final String authorId;
  final String author;
  final String authorDisplayName;
  final String authorUsername;
  final String authorAvatar;
  final String text;

  /// Rótulo pronto para exibição (ex.: 'Hoje às 14:32').
  final String timestamp;

  /// Momento do envio em milissegundos desde a época.
  ///
  /// [timestamp] é texto formatado e não serve para ordenar nem para comparar:
  /// é este campo que permite intercalar o histórico recebido de outros membros
  /// com o que já está em disco, e saber o que chegou depois da última leitura.
  /// Mensagens gravadas antes da v1.0.0n não o têm e chegam como 0 — são
  /// renumeradas na carga, de modo que permanecem na ordem original e antes de
  /// qualquer mensagem com data real.
  int sentAt;

  final String? gifUrl;
  final String? replyToAuthor;
  final String? replyToText;
  final bool isSystem;

  ChatMessage({
    required this.id,
    required this.authorId,
    required this.author,
    String? authorDisplayName,
    String? authorUsername,
    this.authorAvatar = '',
    required this.text,
    required this.timestamp,
    int? sentAt,
    this.gifUrl,
    this.replyToAuthor,
    this.replyToText,
    this.isSystem = false,
  })  : sentAt = sentAt ?? DateTime.now().millisecondsSinceEpoch,
        authorDisplayName = (authorDisplayName != null && authorDisplayName.trim().isNotEmpty)
            ? authorDisplayName.trim()
            : author,
        authorUsername = (authorUsername != null && authorUsername.trim().isNotEmpty)
            ? (authorUsername.startsWith('@') ? authorUsername.trim() : '@${authorUsername.trim()}')
            : '';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawAuthor = json['author'] as String? ?? 'Usuário';
    return ChatMessage(
      id: json['id'] as String? ?? '',
      authorId: json['authorId'] as String? ?? '',
      author: rawAuthor,
      authorDisplayName: json['authorDisplayName'] as String? ?? rawAuthor,
      authorUsername: json['authorUsername'] as String? ?? '',
      authorAvatar: json['authorAvatar'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      // 0 marca "sem data conhecida" (mensagem anterior à v1.0.0n). Usar a hora
      // atual aqui jogaria toda mensagem antiga para o fim da conversa a cada
      // carregamento.
      sentAt: json['sentAt'] as int? ?? 0,
      gifUrl: json['gifUrl'] as String?,
      replyToAuthor: json['replyToAuthor'] as String?,
      replyToText: json['replyToText'] as String?,
      isSystem: json['isSystem'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorId': authorId,
      'author': author,
      'authorDisplayName': authorDisplayName,
      'authorUsername': authorUsername,
      'authorAvatar': authorAvatar,
      'text': text,
      'timestamp': timestamp,
      'sentAt': sentAt,
      'gifUrl': gifUrl,
      'replyToAuthor': replyToAuthor,
      'replyToText': replyToText,
      'isSystem': isSystem,
    };
  }
}
