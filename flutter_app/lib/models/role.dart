import 'dart:ui';

/// Permissões que um cargo pode conceder.
///
/// Cada chave corresponde a uma ação real da interface e do protocolo. Não
/// existe permissão decorativa: se uma chave está aqui, há um ponto do código
/// que a consulta antes de deixar o usuário agir.
class RolePermission {
  const RolePermission(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;
}

class Permissions {
  /// Criar e apagar canais do servidor.
  static const String manageChannels = 'gerenciar_canais';

  /// Dar e tirar cargos de outros membros.
  static const String manageRoles = 'gerenciar_cargos';

  /// Renomear o servidor, mudar a cor e excluí-lo de vez.
  static const String manageServer = 'gerenciar_servidor';

  /// Remover um membro do servidor.
  static const String kickMembers = 'expulsar_membros';

  /// Apagar mensagens de qualquer autor.
  static const String manageMessages = 'apagar_mensagens';

  static const List<RolePermission> all = [
    RolePermission(manageChannels, 'Gerenciar canais', 'Criar e apagar os canais do servidor.'),
    RolePermission(manageRoles, 'Gerenciar cargos', 'Dar e tirar cargos de outros membros.'),
    RolePermission(manageServer, 'Gerenciar servidor', 'Renomear, mudar a cor e excluir o servidor em definitivo.'),
    RolePermission(kickMembers, 'Expulsar membros', 'Remover um membro do servidor.'),
    RolePermission(manageMessages, 'Apagar mensagens', 'Apagar mensagens de qualquer autor.'),
  ];
}

/// Um cargo do servidor: nome e cor próprios, mais o conjunto de permissões.
///
/// O Dono não é um cargo daqui — é o `ownerId` do servidor, e tem tudo por
/// definição. Ele não pode ser rebaixado nem removido por outro cargo.
class ServerRole {
  ServerRole({
    required this.id,
    required this.name,
    required this.colorHex,
    Set<String>? permissions,
  }) : permissions = permissions ?? <String>{};

  final String id;
  String name;
  String colorHex;
  final Set<String> permissions;

  bool has(String permission) => permissions.contains(permission);

  Color get color => Color(_tryParseColor(colorHex));

  static int _tryParseColor(String hex) {
    try {
      return int.parse('0xFF$hex');
    } catch (_) {
      return 0xFF22C55E;
    }
  }

  factory ServerRole.fromJson(Map<String, dynamic> json) => ServerRole(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Cargo',
        colorHex: json['colorHex'] as String? ?? '22C55E',
        permissions: ((json['permissions'] as List<dynamic>?) ?? const [])
            .map((p) => p.toString())
            .toSet(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorHex': colorHex,
        'permissions': permissions.toList(),
      };

  ServerRole copyWith({String? name, String? colorHex, Set<String>? permissions}) => ServerRole(
        id: id,
        name: name ?? this.name,
        colorHex: colorHex ?? this.colorHex,
        permissions: permissions ?? this.permissions,
      );

  /// Cargos com os quais todo servidor já nasce. São editáveis: o Dono pode
  /// trocar o nome, a cor e as permissões de cada um.
  static List<ServerRole> defaults() => [
        ServerRole(
          id: 'role-admin',
          name: 'Administrador',
          colorHex: '8B5CF6',
          permissions: {
            Permissions.manageChannels,
            Permissions.manageRoles,
            Permissions.manageServer,
            Permissions.kickMembers,
            Permissions.manageMessages,
          },
        ),
        ServerRole(
          id: 'role-mod',
          name: 'Moderador',
          colorHex: '38BDF8',
          permissions: {
            Permissions.manageChannels,
            Permissions.kickMembers,
            Permissions.manageMessages,
          },
        ),
      ];
}
