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

  /// Revisão da estrutura (nome, cor, canais), incrementada a cada alteração.
  ///
  /// Serve para ordenar atualizações concorrentes vindas de membros diferentes:
  /// só uma revisão maior substitui a estrutura local.
  int revision;

  /// Indica se esta estrutura é a real do servidor ou apenas um esqueleto
  /// provisório criado ao entrar por convite, enquanto a estrutura verdadeira
  /// não chega pela rede. Um esqueleto nunca é propagado aos outros membros —
  /// era exatamente isso que fazia cada participante acabar com um conjunto de
  /// canais diferente e, como o nome da sala de voz é o ID do canal, entrar em
  /// salas do LiveKit distintas dentro do "mesmo" servidor.
  bool isSynced;

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
    this.revision = 1,
    this.isSynced = true,
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
      revision: json['revision'] as int? ?? 1,
      // Servidores gravados por versões anteriores não tinham o conceito de
      // sincronização; tratá-los como sincronizados manteria os canais
      // inventados pelo convite. Eles são remarcados para sincronizar de novo.
      isSynced: json['isSynced'] as bool? ?? false,
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
      'revision': revision,
      'isSynced': isSynced,
    };
  }

  /// Substitui a estrutura local pela recebida da rede, preservando o que é
  /// estritamente local (código de convite e lista de membros já conhecidos).
  void adoptStructure({
    required String newName,
    required String newDescription,
    required String newColorHex,
    required List<Channel> newChannels,
    required int newRevision,
  }) {
    name = newName;
    description = newDescription;
    colorHex = newColorHex;
    channels
      ..clear()
      ..addAll(newChannels);
    revision = newRevision;
    isSynced = true;
  }
}
