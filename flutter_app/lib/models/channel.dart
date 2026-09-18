enum ChannelType { text, voice }

class Channel {
  final String id;
  final String name;
  final ChannelType type;
  final String topic;
  final int userLimit;

  Channel({
    required this.id,
    required this.name,
    required this.type,
    this.topic = '',
    this.userLimit = 15,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'canal',
      type: json['type'] == 'voice' ? ChannelType.voice : ChannelType.text,
      topic: json['topic'] as String? ?? '',
      userLimit: json['userLimit'] as int? ?? 15,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type == ChannelType.voice ? 'voice' : 'text',
      'topic': topic,
      'userLimit': userLimit,
    };
  }
}
