import 'channel.dart';

class Server {
  final String id;
  final String name;
  final String icon;
  final String inviteCode;
  final List<Channel> channels;

  Server({
    required this.id,
    required this.name,
    this.icon = '',
    required this.inviteCode,
    required this.channels,
  });

  factory Server.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'] as List<dynamic>? ?? [];
    return Server(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Servidor',
      icon: json['icon'] as String? ?? '',
      inviteCode: json['inviteCode'] as String? ?? '',
      channels: rawChannels.map((c) => Channel.fromJson(c as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'inviteCode': inviteCode,
      'channels': channels.map((c) => c.toJson()).toList(),
    };
  }
}
