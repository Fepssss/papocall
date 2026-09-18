import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';

class MembersSidebar extends StatelessWidget {
  const MembersSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final members = state.onlineMembers;
    final totalOnline = members.length + 1; // Includes currentUser

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
              'ONLINE — $totalOnline',
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
                // Current User Item
                _MemberTile(user: state.currentUser, isSelf: true),
                // Other Online Users
                ...members.map((m) => _MemberTile(user: m)),
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
  final bool isSelf;

  const _MemberTile({
    required this.user,
    this.isSelf = false,
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

    return MouseRegion(
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
                  backgroundColor: widget.isSelf ? HudTheme.blurple : HudTheme.bgHover,
                  child: Text(
                    widget.user.initials,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: statusColor,
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
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.user.username,
                          style: TextStyle(
                            color: _isHovered ? Colors.white : HudTheme.textHeader,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

