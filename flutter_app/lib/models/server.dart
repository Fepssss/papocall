import 'channel.dart';

class Server {
  final String id;
  String name;
  String icon;
  String description;
  String inviteCode;
  final String ownerId;
  String colorHex;
  final bool isCustom;
  final List<String> memberIds;
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
    List<String>? memberIds,
    required this.channels,
  }) : memberIds = memberIds ?? [];

  factory Server.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'] as List<dynamic>? ?? [];
    final rawMembers = (json['memberIds'] as List<dynamic>?)?.map((m) => m.toString()).toList() ?? [];
    return Server(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Servidor',
      icon: json['icon'] as String? ?? '',
      description: json['description'] as String? ?? '',
      inviteCode: json['inviteCode'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      colorHex: json['colorHex'] as String? ?? '22C55E',
      isCustom: json['isCustom'] as bool? ?? false,
      memberIds: rawMembers,
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
      'memberIds': memberIds,
      'channels': channels.map((c) => c.toJson()).toList(),
    };
  }
}
