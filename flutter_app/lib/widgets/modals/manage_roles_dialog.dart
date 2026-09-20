import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/role.dart';
import '../../models/server.dart';
import '../../models/user_model.dart';
import '../../providers/app_state.dart';
import '../../theme/hud_theme.dart';

/// Tela de cargos do servidor: cria, renomeia, recolore, dá permissões e
/// atribui cargos a membros.
///
/// Tudo aqui é espelhado no que o botão direito de um membro faz — as duas
/// entradas chamam os mesmos métodos de [AppState], para que nenhuma delas
/// consiga fazer algo que a outra não pode.
class ManageRolesDialog extends StatefulWidget {
  const ManageRolesDialog({super.key, required this.server});

  final Server server;

  static Future<void> show(BuildContext context, Server server) {
    return showDialog(
      context: context,
      builder: (_) => ManageRolesDialog(server: server),
    );
  }

  @override
  State<ManageRolesDialog> createState() => _ManageRolesDialogState();
}

class _ManageRolesDialogState extends State<ManageRolesDialog> {
  static const List<Map<String, String>> _palette = [
    {'hex': '22C55E', 'name': 'Verde'},
    {'hex': '38BDF8', 'name': 'Azul'},
    {'hex': '8B5CF6', 'name': 'Roxo'},
    {'hex': 'EF4444', 'name': 'Vermelho'},
    {'hex': 'F59E0B', 'name': 'Âmbar'},
    {'hex': 'EC4899', 'name': 'Rosa'},
  ];

  String? _selectedRoleId;

  /// Rascunho do painel de edição. Só é gravado no estado ao tocar "Salvar",
  /// para que uma troca acidental de checkbox não se propague aos outros.
  final TextEditingController _nameController = TextEditingController();
  String _draftColorHex = '22C55E';
  final Set<String> _draftPermissions = {};

  Server get _server => widget.server;

  /// Uma cor de cargo pode vir de outra versão ou de um campo livre; nunca deve
  /// derrubar a interface por não conseguir ler o texto.
  Color _colorOf(String hex) {
    try {
      return Color(int.parse('0xFF$hex'));
    } catch (_) {
      return HudTheme.green;
    }
  }

  @override
  void initState() {
    super.initState();
    final roles = _server.roles;
    if (roles.isNotEmpty) _select(roles.first);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _select(ServerRole role) {
    setState(() {
      _selectedRoleId = role.id;
      _nameController.text = role.name;
      _draftColorHex = role.colorHex;
      _draftPermissions
        ..clear()
        ..addAll(role.permissions);
    });
  }

  ServerRole? get _selectedRole {
    final id = _selectedRoleId;
    if (id == null) return null;
    for (final r in _server.roles) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> _save() async {
    final role = _selectedRole;
    if (role == null) return;
    final ok = await context.read<AppState>().updateRole(
          _server.id,
          role.id,
          name: _nameController.text,
          colorHex: _draftColorHex,
          permissions: {..._draftPermissions},
        );
    if (!mounted) return;
    _toast(ok, ok ? 'Cargo atualizado.' : 'Você não tem esses poderes para conceder.');
  }

  Future<void> _create() async {
    final state = context.read<AppState>();
    final ok = await state.createRole(
      _server.id,
      name: 'Novo cargo',
      colorHex: '22C55E',
      permissions: {},
    );
    if (!mounted) return;
    if (ok) {
      final created = state.rolesOf(_server.id).last;
      _select(created);
    } else {
      _toast(false, 'Sem a permissão Gerenciar cargos.');
    }
  }

  Future<void> _delete(ServerRole role) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.bgSidebar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: HudTheme.divider),
        ),
        title: const Text('Excluir cargo',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Quem tem "${role.name}" volta a ser Membro comum. Isso vale para todos '
          'os participantes do servidor.',
          style: const TextStyle(color: HudTheme.textNormal, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: HudTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: HudTheme.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await context.read<AppState>().deleteRole(_server.id, role.id);
    if (!mounted) return;
    setState(() {
      if (_selectedRoleId == role.id) _selectedRoleId = null;
    });
    if (_selectedRole == null) {
      final remaining = _server.roles;
      if (remaining.isNotEmpty) _select(remaining.first);
    }
    if (!ok) _toast(false, 'Falha ao excluir.');
  }

  Future<void> _assign(String userId, String? roleId) async {
    final ok = await context.read<AppState>().assignRole(_server.id, userId, roleId);
    if (!mounted) return;
    if (!ok) _toast(false, 'Você não pode conceder esse cargo.');
  }

  void _toast(bool ok, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: HudTheme.bgSidebar,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
                color: ok ? HudTheme.green : HudTheme.red, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final role = _selectedRole;
    final canManage = state.can(_server.id, Permissions.manageRoles);
    final members = _members(state);

    return Dialog(
      backgroundColor: HudTheme.bgSidebar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: HudTheme.divider),
      ),
      child: SizedBox(
        width: min(760.0, MediaQuery.sizeOf(context).width - 64),
        height: min(560.0, MediaQuery.sizeOf(context).height - 96),
        child: Column(
          children: [
            _header(canManage),
            const Divider(color: HudTheme.divider, height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 230,
                    child: _rolesList(state, canManage),
                  ),
                  Container(width: 1, color: HudTheme.divider),
                  Expanded(child: _editor(state, role, canManage)),
                  Container(width: 1, color: HudTheme.divider),
                  SizedBox(width: 240, child: _membersPanel(state, members)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(bool canManage) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: HudTheme.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.admin_panel_settings_rounded, color: HudTheme.green, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cargos de ${_server.name}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Nome, cor e permissões se propagam para todo o servidor.',
                  style: TextStyle(color: HudTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (!canManage)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                'Somente leitura',
                style: TextStyle(color: HudTheme.yellow, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close, color: HudTheme.textMuted, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _rolesList(AppState state, bool canManage) {
    final roles = state.rolesOf(_server.id);
    return Column(
      children: [
        if (canManage)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: HudTheme.bgActive,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: _create,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Novo cargo',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: roles.length,
            itemBuilder: (_, i) {
              final r = roles[i];
              final selected = r.id == _selectedRoleId;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _select(r),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? HudTheme.bgActive : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: r.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          r.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? Colors.white : HudTheme.textNormal,
                            fontSize: 12.5,
                            fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${r.permissions.length}',
                        style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _editor(AppState state, ServerRole? role, bool canManage) {
    if (role == null) {
      return const Center(
        child: Text(
          'Escolha um cargo na lista.',
          style: TextStyle(color: HudTheme.textMuted, fontSize: 12),
        ),
      );
    }

    final editable = canManage && state.canEditRole(_server.id, role.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      children: [
        Text(
          'NOME DO CARGO',
          style: _labelStyle(),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _nameController,
          enabled: editable,
          maxLength: 24,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: _inputDecoration('ex: Staff, Veteran...'),
        ),
        const SizedBox(height: 14),
        Text('COR DO CARGO', style: _labelStyle()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: _palette.map((c) {
            final color = _colorOf(c['hex']!);
            final selected = _draftColorHex == c['hex'];
            return GestureDetector(
              onTap: editable ? () => setState(() => _draftColorHex = c['hex']!) : null,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        Text('PERMISSÕES', style: _labelStyle()),
        const SizedBox(height: 6),
        ...Permissions.all.map((p) {
          // Conceder o que não se tem é o caminho mais curto para um golpe de
          // estado dentro do servidor: a caixa aparece desabilitada.
          final mine = state.can(_server.id, p.key);
          final checked = _draftPermissions.contains(p.key);
          return CheckboxListTile(
            value: checked,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: _colorOf(_draftColorHex),
            onChanged: (editable && mine)
                ? (v) => setState(() {
                      if (v == true) {
                        _draftPermissions.add(p.key);
                      } else {
                        _draftPermissions.remove(p.key);
                      }
                    })
                : null,
            title: Text(
              p.label,
              style: TextStyle(
                color: (editable && mine) ? HudTheme.textHeader : HudTheme.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              mine ? p.description : '${p.description} · Você não tem essa permissão.',
              style: const TextStyle(color: HudTheme.textMuted, fontSize: 10.5),
            ),
          );
        }),
        const SizedBox(height: 12),
        if (editable)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: HudTheme.red,
                    side: const BorderSide(color: HudTheme.divider),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _delete(role),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Excluir'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HudTheme.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _save,
                  child: const Text('Salvar alterações',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: HudTheme.bgCard,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Este cargo tem poderes que você não possui, então não pode ser editado.',
              style: TextStyle(color: HudTheme.textMuted, fontSize: 11.5),
            ),
          ),
      ],
    );
  }

  Widget _membersPanel(AppState state, List<UserModel> members) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Text('MEMBROS — ${members.length}', style: _labelStyle()),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: members.length,
            itemBuilder: (_, i) {
              final m = members[i];
              final roleName = state.roleNameFor(_server.id, m.id);
              final roleColor = state.roleColorFor(_server.id, m.id) ?? HudTheme.textMuted;
              final assignable = state.can(_server.id, Permissions.manageRoles) &&
                  !_server.isOwnedBy(m.id) &&
                  m.id != state.currentUser.id;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    m.displayNameOrUsername,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: HudTheme.textHeader, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(roleName,
                      style: TextStyle(
                          color: roleColor, fontSize: 10.5, fontWeight: FontWeight.bold)),
                  trailing: assignable
                      ? PopupMenuButton<String>(
                          tooltip: 'Atribuir cargo',
                          color: HudTheme.bgSidebar,
                          icon: const Icon(Icons.swap_horiz_rounded,
                              size: 16, color: HudTheme.textMuted),
                          onSelected: (value) => _assign(m.id, value.isEmpty ? null : value),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: '',
                              child: Text('Nenhum (Membro)',
                                  style: TextStyle(color: HudTheme.textNormal, fontSize: 12.5)),
                            ),
                            ..._server.roles.map(
                              (r) => PopupMenuItem(
                                value: r.id,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration:
                                          BoxDecoration(color: r.color, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(r.name,
                                        style: const TextStyle(
                                            color: HudTheme.textNormal, fontSize: 12.5)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<UserModel> _members(AppState state) {
    final groups = state.getServerMembersGrouped(_server.id);
    return [...groups['online'] ?? [], ...groups['offline'] ?? []];
  }

  TextStyle _labelStyle() => const TextStyle(
        color: HudTheme.textMuted,
        fontSize: 10.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
        counterText: '',
        filled: true,
        fillColor: HudTheme.bgCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: HudTheme.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: HudTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: HudTheme.green, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: HudTheme.borderSubtle),
        ),
      );
}
