enum FriendRequestStatus { pending, accepted, rejected }

class FriendRequest {
  final String id;
  final String senderId;
  final String senderUsername;
  final String senderDisplayName;
  final String? senderAvatar;
  final String recipientUsername;
  FriendRequestStatus status;
  final int timestamp;

  FriendRequest({
    required this.id,
    required this.senderId,
    required this.senderUsername,
    required this.senderDisplayName,
    this.senderAvatar,
    required this.recipientUsername,
    this.status = FriendRequestStatus.pending,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderUsername': senderUsername,
        'senderDisplayName': senderDisplayName,
        'senderAvatar': senderAvatar,
        'recipientUsername': recipientUsername,
        'status': status.name,
        'timestamp': timestamp,
      };

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
        id: json['id'] as String? ?? 'req-${DateTime.now().millisecondsSinceEpoch}',
        senderId: json['senderId'] as String? ?? '',
        senderUsername: json['senderUsername'] as String? ?? 'usuario',
        senderDisplayName: json['senderDisplayName'] as String? ?? (json['senderUsername'] as String? ?? 'Usuário'),
        senderAvatar: json['senderAvatar'] as String?,
        recipientUsername: json['recipientUsername'] as String? ?? '',
        status: FriendRequestStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => FriendRequestStatus.pending,
        ),
        timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
}
