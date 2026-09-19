import 'channel.dart';
import 'role.dart';

class Server {
  final String id;
  String name;
  String icon;
  String description;
  String inviteCode;
  String ownerId;
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

  /// Cargos definidos neste servidor. O Dono não aparece aqui: ele é o
  /// [ownerId] e tem todas as permissões por definição.
  final List<ServerRole> roles;

  /// Cargo de cada membro, por ID de usuário. Quem não está no mapa é
  /// simplesmente Membro, sem permissões extras.
  final Map<String, String> memberRoles;

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
    List<ServerRole>? roles,
    Map<String, String>? memberRoles,
  })  : memberIds = memberIds ?? [],
        roles = roles ?? [],
        memberRoles = memberRoles ?? {};

  bool isOwnedBy(String userId) => ownerId.isNotEmpty && ownerId == userId;

  ServerRole? roleOf(String userId) {
    final roleId = memberRoles[userId];
    if (roleId == null) return null;
    for (final role in roles) {
      if (role.id == roleId) return role;
    }
    return null;
  }

  /// A permissão manda, mas o Dono manda mais: ele nunca fica de fora da
  /// própria administração por um cargo mal atribuído.
  bool hasPermission(String userId, String permission) {
    if (isOwnedBy(userId)) return true;
    return roleOf(userId)?.has(permission) ?? false;
  }

  /// Impede escalar privilégios: ninguém entrega a outro um cargo que tenha
  /// uma permissão que o próprio usuário não tem.
  bool canGrantRole(ServerRole role, String granterId) {
    if (isOwnedBy(granterId)) return true;
    for (final permission in role.permissions) {
      if (!hasPermission(granterId, permission)) return false;
    }
    return true;
  }

  factory Server.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'] as List<dynamic>? ?? [];
    final rawMembers = (json['memberIds'] as List<dynamic>?)?.map((m) => m.toString()).toList() ?? [];
    final rawRoles = json['roles'] as List<dynamic>? ?? [];
    final rawMemberRoles = (json['memberRoles'] as Map<String, dynamic>?)?.map(
          (key, value) => MapEntry(key, value.toString()),
        ) ??
        <String, String>{};
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
      roles: rawRoles.map((r) => ServerRole.fromJson(r as Map<String, dynamic>)).toList(),
      memberRoles: rawMemberRoles,
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
      'roles': roles.map((r) => r.toJson()).toList(),
      'memberRoles': memberRoles,
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

  /// Adota a tabela de cargos. Chamada apenas para publicação vinda do Dono:
  /// um membro qualquer não pode se auto-promover escrevendo o próprio cargo
  /// na estrutura que circula pelo broker.
  void adoptRoles({
    required List<ServerRole> newRoles,
    required Map<String, String> newMemberRoles,
  }) {
    roles
      ..clear()
      ..addAll(newRoles);
    memberRoles
      ..clear()
      ..addAll(newMemberRoles);
    // Um membro que saiu e voltou pode ter ficado com cargo órfão de um cargo
    // que o Dono apagou entretempo.
    memberRoles.removeWhere((_, roleId) => !roles.any((r) => r.id == roleId));
  }
}
