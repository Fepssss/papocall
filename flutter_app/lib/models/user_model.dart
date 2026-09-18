enum UserStatus { online, idle, dnd, offline }

class UserModel {
  final String id;
  String username;
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
    required this.username,
    this.avatar = '',
    this.status = UserStatus.online,
    this.isSpeaking = false,
    this.isMuted = false,
    this.isDeafened = false,
    this.isScreenSharing = false,
    this.currentVoiceChannelId,
    this.currentVoiceServerId,
    int? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now().millisecondsSinceEpoch;

  String get initials {
    if (username.isEmpty) return '?';
    final parts = username.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return username.substring(0, username.length >= 2 ? 2 : 1).toUpperCase();
  }
}
