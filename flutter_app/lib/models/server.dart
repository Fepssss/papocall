import 'channel.dart';

class Server {
  final String id;
  final String name;
  final String icon;
  final String description;
  final String inviteCode;
  final String ownerId;
  final String colorHex;
  final bool isCustom;
  final List<Channel> channels;

  Server({
    required this.id,
    required this.name,
    this.icon = '',
    this.description = '',
    required this.inviteCode,
    this.ownerId = '',
    this.colorHex = '22C55E',
    this.isCustom = false,
    required this.channels,
  });

  factory Server.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'] as List<dynamic>? ?? [];
    return Server(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Servidor',
      icon: json['icon'] as String? ?? '',
      description: json['description'] as String? ?? '',
      inviteCode: json['inviteCode'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      colorHex: json['colorHex'] as String? ?? '22C55E',
      isCustom: json['isCustom'] as bool? ?? false,
      channels: rawChannels.map((c) => Channel.fromJson(c as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'description': description,
      'inviteCode': inviteCode,
      'ownerId': ownerId,
      'colorHex': colorHex,
      'isCustom': isCustom,
      'channels': channels.map((c) => c.toJson()).toList(),
    };
  }
}
