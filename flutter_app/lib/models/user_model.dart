enum UserStatus { online, idle, dnd, offline }

class UserModel {
  final String id;
  String username;
  String displayName;
  String avatar;
  UserStatus status;
  bool isSpeaking;
  bool isMuted;
  bool isDeafened;
  bool isScreenSharing;
  String? currentVoiceChannelId;
  String? currentVoiceServerId;
  int lastSeen;

  UserModel({
    required this.id,
    required String username,
    String? displayName,
    this.avatar = '',
    this.status = UserStatus.online,
    this.isSpeaking = false,
    this.isMuted = false,
    this.isDeafened = false,
    this.isScreenSharing = false,
    this.currentVoiceChannelId,
    this.currentVoiceServerId,
    int? lastSeen,
  })  : username = username.replaceAll('@', '').trim(),
        displayName = (displayName != null && displayName.trim().isNotEmpty)
            ? displayName.trim()
            : username.replaceAll('@', '').trim(),
        lastSeen = lastSeen ?? DateTime.now().millisecondsSinceEpoch;

  String get displayNameOrUsername {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    return username.replaceAll('@', '').trim();
  }

  String get handle {
    final clean = username.replaceAll('@', '').trim();
    return clean.isNotEmpty ? '@$clean' : '@usuario';
  }

  String get initials {
    final name = displayNameOrUsername;
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? '',
      username: (json['username'] as String? ?? 'Usuário').replaceAll('@', '').trim(),
      displayName: json['displayName'] as String? ?? json['display_name'] as String?,
      avatar: json['avatar'] as String? ?? '',
      status: UserStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => UserStatus.online,
      ),
      isMuted: json['isMuted'] as bool? ?? false,
      isDeafened: json['isDeafened'] as bool? ?? false,
      isScreenSharing: json['isScreenSharing'] as bool? ?? false,
      currentVoiceChannelId: json['currentVoiceChannelId'] as String?,
      currentVoiceServerId: json['currentVoiceServerId'] as String?,
      lastSeen: json['lastSeen'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'displayName': displayName,
      'avatar': avatar,
      'status': status.name,
      'isMuted': isMuted,
      'isDeafened': isDeafened,
      'isScreenSharing': isScreenSharing,
      'currentVoiceChannelId': currentVoiceChannelId,
      'currentVoiceServerId': currentVoiceServerId,
      'lastSeen': lastSeen,
    };
  }
}
