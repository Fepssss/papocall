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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: HudTheme.bgHover,
        border: Border(
          top: BorderSide(color: HudTheme.divider, width: 1),
          bottom: BorderSide(color: HudTheme.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Connection Status Icon (Símbolo de Wi-Fi verde com Tooltip de Ping)
          Tooltip(
            message: isConnecting
                ? 'Conectando ao servidor LiveKit RTC...'
                : (state.voicePingMs > 0
                    ? 'Latência (Ping): ${state.voicePingMs} ms\nQualidade: ${state.voiceConnectionQuality}\nServidor: LiveKit Cloud RTC HD\nCodec: Opus 48kHz HD\nCriptografia: WebRTC DTLS-SRTP'
                    : 'Voz Conectada\nMedindo latência com o servidor...'),
            decoration: BoxDecoration(
              color: const Color(0xFF0F131D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: HudTheme.green.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              height: 1.45,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            waitDuration: const Duration(milliseconds: 150),
            child: MouseRegion(
              cursor: SystemMouseCursors.help,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (isConnecting ? HudTheme.accent : HudTheme.green).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (isConnecting ? HudTheme.accent : HudTheme.green).withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  isConnecting ? Icons.sync : Icons.wifi,
                  color: isConnecting ? HudTheme.accent : HudTheme.green,
                  size: 16,
                ),
              ),
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
                    Flexible(
                      child: Text(
                        isConnecting ? 'Conectando...' : 'Voz Conectada',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isConnecting ? HudTheme.accent : HudTheme.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state.voicePingMs > 0 ? '${state.voicePingMs}ms' : '/ RTC HD',
                      style: TextStyle(
                        color: state.voicePingMs > 0 ? HudTheme.green : HudTheme.textMuted,
                        fontSize: 10,
                        fontWeight: state.voicePingMs > 0 ? FontWeight.bold : FontWeight.normal,
                      ),
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
