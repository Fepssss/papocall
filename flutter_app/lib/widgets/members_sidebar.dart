import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/server.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'member_context_menu.dart';

class MembersSidebar extends StatelessWidget {
  const MembersSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final groups = state.getServerMembersGrouped(state.activeServerId);
    final onlineMembers = groups['online'] ?? [];
    final offlineMembers = groups['offline'] ?? [];
    final server = state.serverById(state.activeServerId);
    // A barra só aparece dentro de um servidor, mas o ID ativo pode estar entre
    // uma troca e outra; sem servidor não há o que listar.
    if (server == null) return const SizedBox.shrink();

    return Container(
      width: 240,
      color: HudTheme.bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: HudTheme.divider, width: 1)),
            ),
            child: Text(
              'DISPONÍVEL — ${onlineMembers.length}',
              style: const TextStyle(
                color: HudTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              children: [
                // Membros Disponíveis / Online
                ...onlineMembers.map((m) => _MemberTile(
                      user: m,
                      server: server,
                      isSelf: m.id == state.currentUser.id,
                    )),

                // Categoria e Membros Offline (se houver)
                if (offlineMembers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      'OFFLINE — ${offlineMembers.length}',
                      style: const TextStyle(
                        color: HudTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...offlineMembers.map((m) => _MemberTile(
                        user: m,
                        server: server,
                        isSelf: m.id == state.currentUser.id,
                        isOfflineGroup: true,
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatefulWidget {
  final UserModel user;
  final Server server;
  final bool isSelf;
  final bool isOfflineGroup;

  const _MemberTile({
    required this.user,
    required this.server,
    this.isSelf = false,
    this.isOfflineGroup = false,
  });

  @override
  State<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends State<_MemberTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    switch (widget.user.status) {
      case UserStatus.online:
        statusColor = HudTheme.statusOnline;
        break;
      case UserStatus.idle:
        statusColor = HudTheme.statusIdle;
        break;
      case UserStatus.dnd:
        statusColor = HudTheme.statusDnd;
        break;
      case UserStatus.offline:
        statusColor = HudTheme.statusOffline;
        break;
    }

    final isOffline = widget.user.status == UserStatus.offline || widget.isOfflineGroup;
    final cleanHandle = widget.user.handle;

    final state = context.watch<AppState>();
    final isOwner = widget.server.isOwnedBy(widget.user.id);
    final roleName = state.roleNameFor(widget.server.id, widget.user.id);
    final roleColor = isOwner
        ? HudTheme.yellow
        : state.roleColorFor(widget.server.id, widget.user.id) ?? HudTheme.textMuted;
    // Só quem foi promovido (ou manda no servidor) tem a linha de cargo; para o
    // membro comum ela sumiria e sobraria apenas o @, como sempre foi.
    final showsRole = isOwner || (roleName != 'Membro' && roleName.isNotEmpty);

    final tileContent = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _isHovered ? HudTheme.bgHover : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: widget.isSelf
                      ? HudTheme.blurple
                      : (isOffline ? HudTheme.bgCard : HudTheme.bgHover),
                  child: Text(
                    widget.user.initials,
                    style: TextStyle(
                      color: isOffline ? HudTheme.textMuted : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isOffline ? HudTheme.statusOffline : statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: HudTheme.bgSidebar, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.user.displayNameOrUsername,
                          style: TextStyle(
                            color: _isHovered
                                ? Colors.white
                                : (isOffline ? HudTheme.textMuted : HudTheme.textHeader),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.isSelf) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: HudTheme.blurple.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'VOCÊ',
                            style: TextStyle(color: HudTheme.blurple, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 11),
                      children: [
                        if (showsRole)
                          TextSpan(
                            text: '$roleName  ',
                            style: TextStyle(
                              color: roleColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        TextSpan(
                          text: cleanHandle,
                          style: const TextStyle(color: HudTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (isOffline) {
      return GestureDetector(
        onSecondaryTapUp: (details) =>
            MemberContextMenu.show(context, widget.server, widget.user, details.globalPosition),
        child: Opacity(
          opacity: _isHovered ? 0.9 : 0.65,
          child: tileContent,
        ),
      );
    }

    return GestureDetector(
      onSecondaryTapUp: (details) =>
          MemberContextMenu.show(context, widget.server, widget.user, details.globalPosition),
      child: tileContent,
    );
  }
}
