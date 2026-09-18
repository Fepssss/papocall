import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';

class VoiceConnectionHud extends StatelessWidget {
  const VoiceConnectionHud({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final channel = state.servers
        .expand((s) => s.channels)
        .firstWhere(
          (c) => c.id == state.connectedVoiceChannelId,
          orElse: () => Channel(id: '', name: 'Sala de Voz', type: ChannelType.voice),
        );

    final isConnecting = state.isConnectingVoice && state.connectedVoiceChannelId == null;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: HudTheme.bgHover,
        border: Border(
          top: BorderSide(color: HudTheme.divider, width: 1),
          bottom: BorderSide(color: HudTheme.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Connection Status Icon
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: (isConnecting ? HudTheme.accent : HudTheme.green).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isConnecting ? Icons.sync : Icons.signal_cellular_alt,
              color: isConnecting ? HudTheme.accent : HudTheme.green,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),

          // Status & Channel Name
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isConnecting ? 'Conectando...' : 'Voz Conectada',
                      style: TextStyle(
                        color: isConnecting ? HudTheme.accent : HudTheme.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '/ RTC HD',
                      style: TextStyle(color: HudTheme.textMuted, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                _VoiceChannelLink(
                  channelName: channel.name,
                  onTap: () {
                    if (state.connectedVoiceChannelId != null) {
                      state.selectChannel(state.connectedVoiceChannelId!);
                    }
                  },
                ),
              ],
            ),
          ),

          // Disconnect Button
          _VoiceDisconnectButton(onPressed: state.disconnectVoice),
        ],
      ),
    );
  }
}

class _VoiceChannelLink extends StatefulWidget {
  final String channelName;
  final VoidCallback onTap;

  const _VoiceChannelLink({required this.channelName, required this.onTap});

  @override
  State<_VoiceChannelLink> createState() => _VoiceChannelLinkState();
}

class _VoiceChannelLinkState extends State<_VoiceChannelLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          '${widget.channelName} / PapoCall',
          style: TextStyle(
            color: _isHovered ? Colors.white : HudTheme.textMuted,
            fontSize: 11,
            decoration: _isHovered ? TextDecoration.underline : TextDecoration.none,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _VoiceDisconnectButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _VoiceDisconnectButton({required this.onPressed});

  @override
  State<_VoiceDisconnectButton> createState() => _VoiceDisconnectButtonState();
}

class _VoiceDisconnectButtonState extends State<_VoiceDisconnectButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Desconectar da Voz',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _isHovered ? HudTheme.red.withValues(alpha: 0.2) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.call_end,
              size: 18,
              color: _isHovered ? HudTheme.red : HudTheme.textNormal,
            ),
          ),
        ),
      ),
    );
  }
}
