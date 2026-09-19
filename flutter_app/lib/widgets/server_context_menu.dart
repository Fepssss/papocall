import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/role.dart';
import '../models/server.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'modals/manage_roles_dialog.dart';
import 'modals/server_invite_dialog.dart';
import 'modals/settings_modal.dart';

/// Menu de contexto da barra de servidores, aberto pelo botão direito sobre o
/// ícone de um servidor.
///
/// É desenhado do zero em vez de usar o [showMenu] do Material para que a
/// superfície, a tipografia e os separadores continuem sendo os do HUD — o menu
/// padrão puxa o tema Material e destoaria do resto da janela.
class ServerContextMenu {
  static const double _menuWidth = 268;

  /// Usa uma rota própria em vez de [showDialog]: o dialog padrão centraliza o
  /// conteúdo dentro de um [Dialog] e escurece o fundo, o que deslocaria o menu
  /// do ponto do clique e o faria nascer sobre uma cortina preta.
  static Future<void> show(BuildContext context, Server server, Offset globalPosition) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Opções do servidor',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, _) => _ServerContextMenu(server: server, anchor: globalPosition),
    );
  }
}

class _ServerContextMenu extends StatelessWidget {
  const _ServerContextMenu({required this.server, required this.anchor});

  final Server server;
  final Offset anchor;

  Future<void> _andThen(BuildContext ctx, Future<void> Function() action) async {
    Navigator.of(ctx).pop();
    await action();
  }

  /// Mantém o menu inteiro dentro da janela: perto da borda direita ou inferior,
  /// ele nasceria parcialmente fora da tela e ficaria inutilizável.
  Offset _origin(Size screen, {required int items, required int dividers}) {
    const margin = 8.0;
    final estimatedHeight = 26 + items * 34 + dividers * 9 + 16;
    var dx = anchor.dx;
    var dy = anchor.dy;
    if (dx + ServerContextMenu._menuWidth + margin > screen.width) {
      dx = screen.width - ServerContextMenu._menuWidth - margin;
    }
    if (dy + estimatedHeight + margin > screen.height) {
      dy = screen.height - estimatedHeight - margin;
    }
    return Offset(dx < margin ? margin : dx, dy < margin ? margin : dy);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final screen = MediaQuery.of(context).size;
    final isOwner = server.isOwnedBy(state.currentUser.id);
    final canManageRoles = state.can(server.id, Permissions.manageRoles);

    final rows = <Widget>[
      const _MenuDivider(),
      _MenuItem(
        label: 'Marcar como lida',
        icon: Icons.done_all_rounded,
        onTap: () => _andThen(context, () async => state.markServerRead(server.id)),
      ),
      // Convidar não é uma permissão: quem está no servidor pode trazer gente.
      _MenuItem(
        label: 'Convidar para o servidor',
        icon: Icons.person_add_alt_rounded,
        onTap: () => _andThen(context, () => ServerInviteDialog.show(context, server)),
      ),
      _MenuItem(
        label: state.isServerMuted(server.id) ? 'Não silenciar' : 'Silenciar',
        icon: state.isServerMuted(server.id)
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        trailing: state.isServerMuted(server.id) ? const _Checkmark() : null,
        onTap: () => _andThen(context, () async => state.toggleServerMuted(server.id)),
      ),
      if (canManageRoles) ...[
        const _MenuDivider(),
        _MenuItem(
          label: 'Cargos e permissões',
          icon: Icons.admin_panel_settings_outlined,
          trailing: const _Chevron(),
          onTap: () => _andThen(context, () => ManageRolesDialog.show(context, server)),
        ),
      ],
      const _MenuDivider(),
      _MenuItem(
        label: 'Config. de notificação',
        icon: Icons.tune_rounded,
        trailing: const _Chevron(),
        onTap: () => _andThen(context, () => _openSettings(context, SettingsTab.notifications)),
      ),
      _MenuItem(
        label: 'Config. de privacidade',
        icon: Icons.privacy_tip_outlined,
        trailing: const _Chevron(),
        onTap: () => _andThen(context, () => _openSettings(context, SettingsTab.privacy)),
      ),
      const _MenuDivider(),
      // Sair tira só este usuário. Excluir para todos é outra coisa, e só o Dono
      // vê a opção: apaga o servidor na máquina de cada membro e limpa os
      // tópicos retidos dele no broker.
      _MenuItem(
        label: 'Sair do servidor',
        icon: Icons.logout_rounded,
        onTap: () => _andThen(context, () => _confirmLeave(context, state, server)),
      ),
      if (isOwner)
        _MenuItem(
          label: 'Excluir servidor para todos',
          icon: Icons.delete_forever_rounded,
          destructive: true,
          onTap: () => _andThen(context, () => _confirmDestroy(context, state, server)),
        ),
    ];

    final origin = _origin(
      screen,
      items: rows.whereType<_MenuItem>().length,
      dividers: rows.whereType<_MenuDivider>().length,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: origin.dx,
          top: origin.dy,
          child: Material(
            elevation: 0,
            color: Colors.transparent,
            child: Container(
              width: ServerContextMenu._menuWidth,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: HudTheme.bgSidebar,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: HudTheme.divider),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                    child: Text(
                      server.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HudTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  ...rows,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openSettings(BuildContext context, SettingsTab tab) {
    return showDialog<void>(
      context: context,
      builder: (_) => SettingsModal(initialTab: tab),
    );
  }

  Future<void> _confirmLeave(BuildContext context, AppState state, Server server) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.bgSidebar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: HudTheme.divider),
        ),
        title: const Text('Sair do servidor',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'Você vai sair de "${server.name}" e deixará de receber as mensagens dele. '
          'O servidor continua existindo para os outros membros e para voltar você '
          'precisará de um novo convite.',
          style: const TextStyle(color: HudTheme.textNormal, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: HudTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.bgActive,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await state.deleteServer(server.id);
            },
            child: const Text(
              'Confirmar',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// A exclusão permanente não tem volta: apaga o servidor na máquina de cada
  /// membro e limpa os tópicos retidos dele. Por isso pede o nome digitado, a
  /// mesma barra que separa um clique distraído de uma decisão tomada.
  Future<void> _confirmDestroy(BuildContext context, AppState state, Server server) {
    // Sem controlador: a caixa existe só enquanto este dialog está aberto, e um
    // TextEditingController aqui nasceria sem nunca ser descartado.
    var digitado = '';
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.bgSidebar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: HudTheme.red.withValues(alpha: 0.5)),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: HudTheme.red, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Excluir servidor para todos',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${server.name}" será apagado na máquina de todos os ${server.memberIds.length} '
              'membros, junto com o histórico, os canais e os cargos. Quem estiver '
              'conectado recebe o aviso na hora; quem estiver offline apaga ao voltar. '
              'Não existe recuperação.',
              style: const TextStyle(color: HudTheme.textNormal, fontSize: 13),
            ),
            const SizedBox(height: 14),
            const Text(
              'DIGITE O NOME DO SERVIDOR PARA CONFIRMAR',
              style: TextStyle(
                color: HudTheme.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              onChanged: (v) => digitado = v,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: server.name,
                hintStyle: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
                filled: true,
                fillColor: HudTheme.bgCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: HudTheme.divider),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: HudTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (digitado.trim() != server.name.trim()) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('O nome digitado não confere.'),
                    backgroundColor: HudTheme.red,
                  ),
                );
                return;
              }
              Navigator.of(ctx).pop();
              await state.destroyServer(server.id);
            },
            child: const Text(
              'Excluir definitivamente',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.destructive ? HudTheme.red : HudTheme.textNormal;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 34,
          color: _hover ? HudTheme.bgActive : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(widget.icon, size: 15, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 9,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      child: const Divider(color: HudTheme.divider, height: 9, thickness: 1),
    );
  }
}

class _Checkmark extends StatelessWidget {
  const _Checkmark();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.check_rounded, size: 16, color: HudTheme.green);
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.chevron_right_rounded, size: 16, color: HudTheme.textMuted);
  }
}
