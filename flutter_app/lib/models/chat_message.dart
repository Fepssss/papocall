class ChatMessage {
  final String id;
  final String authorId;
  final String author;
  final String authorAvatar;
  final String text;
  final String timestamp;
  final String? gifUrl;
  final String? replyToAuthor;
  final String? replyToText;
  final bool isSystem;

  ChatMessage({
    required this.id,
    required this.authorId,
    required this.author,
    this.authorAvatar = '',
    required this.text,
    required this.timestamp,
    this.gifUrl,
    this.replyToAuthor,
    this.replyToText,
    this.isSystem = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      authorId: json['authorId'] as String? ?? '',
      author: json['author'] as String? ?? 'Usuário',
      authorAvatar: json['authorAvatar'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
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
      'authorAvatar': authorAvatar,
      'text': text,
      'timestamp': timestamp,
      'gifUrl': gifUrl,
      'replyToAuthor': replyToAuthor,
      'replyToText': replyToText,
      'isSystem': isSystem,
    };
  }
}
