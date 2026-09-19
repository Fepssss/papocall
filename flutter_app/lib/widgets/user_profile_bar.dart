import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'modals/settings_modal.dart';

class UserProfileBar extends StatelessWidget {
  const UserProfileBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;

    Color statusColor;
    switch (user.status) {
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

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: HudTheme.bgProfile,
        border: Border(
          top: BorderSide(color: HudTheme.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Avatar with status dot and username (hoverable)
          Expanded(
            child: _UserInfoSection(user: user, statusColor: statusColor),
          ),

          // Audio & Settings Controls
          IconButton(
            icon: Icon(
              user.isMuted ? Icons.mic_off : Icons.mic,
              size: 18,
              color: user.isMuted ? HudTheme.red : HudTheme.textNormal,
            ),
            tooltip: user.isMuted ? 'Desmutar' : 'Mutar',
            onPressed: state.toggleMute,
            splashRadius: 18,
          ),
          IconButton(
            icon: Icon(
              user.isDeafened ? Icons.headset_off : Icons.headset,
              size: 18,
              color: user.isDeafened ? HudTheme.red : HudTheme.textNormal,
            ),
            tooltip: user.isDeafened ? 'Desensurdecer' : 'Ensurdecer',
            onPressed: state.toggleDeafen,
            splashRadius: 18,
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 18, color: HudTheme.textNormal),
            tooltip: 'Configurações de Usuário',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const SettingsModal(),
            ),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }
}

class _UserInfoSection extends StatefulWidget {
  final UserModel user;
  final Color statusColor;

  const _UserInfoSection({required this.user, required this.statusColor});

  @override
  State<_UserInfoSection> createState() => _UserInfoSectionState();
}

class _UserInfoSectionState extends State<_UserInfoSection> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final statusText = widget.user.status == UserStatus.online
        ? 'Online'
        : widget.user.status == UserStatus.idle
            ? 'Ausente'
            : widget.user.status == UserStatus.dnd
                ? 'Não Perturbe'
                : 'Offline';

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => showDialog(
        context: context,
        builder: (_) => const SettingsModal(),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                    backgroundColor: HudTheme.blurple,
                    child: Text(
                      widget.user.initials,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: widget.statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: HudTheme.bgProfile, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.displayNameOrUsername,
                      style: TextStyle(
                        color: _isHovered ? Colors.white : HudTheme.textHeader,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${widget.user.handle}  •  $statusText',
                      style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
