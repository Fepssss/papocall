import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'modals/server_invite_dialog.dart';

class ChannelsSidebar extends StatelessWidget {
  const ChannelsSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final srv = state.activeServer;

    final textChannels = srv?.channels.where((c) => c.type == ChannelType.text).toList() ?? [];
    final voiceChannels = srv?.channels.where((c) => c.type == ChannelType.voice).toList() ?? [];

    return Container(
      color: HudTheme.bgSidebar,
      child: Column(
        children: [
          // Server Header
          InkWell(
            onTap: () {
              if (srv != null) {
                ServerInviteDialog.show(context, srv);
              }
            },
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: HudTheme.divider, width: 1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipOval(
                          child: Image.asset('assets/logo.png', width: 24, height: 24),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            srv?.name ?? 'PapoCall',
                            style: const TextStyle(
                              color: HudTheme.textHeader,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_add_alt_1_rounded, color: HudTheme.green, size: 18),
                    tooltip: 'Convidar Amigos',
                    splashRadius: 18,
                    onPressed: () {
                      if (srv != null) {
                        ServerInviteDialog.show(context, srv);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // Channels List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                // Text Channels Category
                _buildCategoryHeader('CANAIS DE TEXTO'),
                ...textChannels.map((c) => _buildChannelItem(context, c, state)),
                const SizedBox(height: 16),
                // Voice Channels Category
                _buildCategoryHeader('CANAIS DE VOZ'),
                ...voiceChannels.map((c) => _buildChannelItem(context, c, state)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: HudTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildChannelItem(BuildContext context, Channel channel, AppState state) {
    final isText = channel.type == ChannelType.text;
    final isSelected = state.activeChannelId == channel.id;
    final isConnected = state.connectedVoiceChannelId == channel.id;

    // Usuários atualmente dentro desta sala de voz
    final voiceUsers = <UserModel>[];
    if (!isText) {
      if (isConnected) {
        voiceUsers.add(state.currentUser);
      }
      for (final m in state.onlineMembers) {
        if (m.currentVoiceChannelId == channel.id && !voiceUsers.any((u) => u.id == m.id)) {
          voiceUsers.add(m);
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChannelRow(
            channel: channel,
            isText: isText,
            isSelected: isSelected,
            isConnected: isConnected,
            onTap: () {
              state.selectChannel(channel.id);
              if (!isText) {
                if (state.connectedVoiceChannelId != channel.id && !state.isConnectingVoice) {
                  state.connectVoice(channel.id);
                }
              }
            },
          ),

          // Membros conectados na call (aparecem identados abaixo do nome do canal)
          if (!isText && voiceUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: voiceUsers.map((user) => _VoiceUserRow(user: user, isSelf: user.id == state.currentUser.id)).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatefulWidget {
  final Channel channel;
  final bool isText;
  final bool isSelected;
  final bool isConnected;
  final VoidCallback onTap;

  const _ChannelRow({
    required this.channel,
    required this.isText,
    required this.isSelected,
    required this.isConnected,
    required this.onTap,
  });

  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isSelected
        ? HudTheme.bgActive
        : (_isHovered ? HudTheme.bgHover : Colors.transparent);

    final iconColor = widget.isConnected
        ? HudTheme.green
        : (widget.isSelected || _isHovered ? HudTheme.textHeader : HudTheme.textMuted);

    final textColor = widget.isConnected
        ? HudTheme.green
        : (widget.isSelected || _isHovered ? HudTheme.textHeader : HudTheme.textNormal);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                widget.isText ? Icons.tag : Icons.volume_up,
                size: 18,
                color: iconColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.channel.name,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: (widget.isSelected || widget.isConnected) ? FontWeight.bold : FontWeight.w500,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!widget.isText && widget.isConnected)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: HudTheme.green,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceUserRow extends StatefulWidget {
  final UserModel user;
  final bool isSelf;

  const _VoiceUserRow({
    required this.user,
    required this.isSelf,
  });

  @override
  State<_VoiceUserRow> createState() => _VoiceUserRowState();
}

class _VoiceUserRowState extends State<_VoiceUserRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = _isHovered
        ? HudTheme.bgHover
        : (widget.isSelf ? HudTheme.bgCard.withValues(alpha: 0.4) : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: widget.isSelf ? HudTheme.blurple : HudTheme.bgHover,
              child: Text(
                widget.user.initials,
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.isSelf ? '${widget.user.username} (Você)' : widget.user.username,
                style: TextStyle(
                  color: (widget.isSelf || _isHovered) ? HudTheme.textHeader : HudTheme.textNormal,
                  fontWeight: widget.isSelf ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.user.isMuted)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.mic_off, size: 13, color: HudTheme.red),
              ),
            if (widget.user.isDeafened)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.headset_off, size: 13, color: HudTheme.red),
              ),
            if (widget.user.isScreenSharing)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.screen_share, size: 13, color: HudTheme.accent),
              ),
          ],
        ),
      ),
    );
  }
}
