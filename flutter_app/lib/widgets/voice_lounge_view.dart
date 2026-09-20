import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:livekit_client/livekit_client.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import '../utils/voice_feedback.dart';
import 'screen_share_dialog.dart';

class VoiceLoungeView extends StatelessWidget {
  const VoiceLoungeView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final channel = state.activeChannel;
    final isConnected = state.connectedVoiceChannelId == channel?.id;
    final hasActiveScreenShare = isConnected && state.activeScreenShareTrack != null;

    // Quem está na chamada é o que o LiveKit diz, não o que a presença do
    // MQTT anunciou: ela chega atrasada, é sobrescrita por outros servidores e
    // era o motivo de uma sala com duas pessoas mostrar um único cartão.
    final channelMembers = isConnected
        ? (state.ocupantesDaChamada.isEmpty
            ? [state.currentUser]
            : state.ocupantesDaChamada)
        : [
            for (final m in state.onlineMembers)
              if (m.currentVoiceChannelId == channel?.id) m,
          ];

    return Expanded(
      child: Container(
        color: HudTheme.bgChat,
        child: Column(
          children: [
            // Voice Header Bar
            _buildHeader(state, channel?.name, isConnected, hasActiveScreenShare),

            // Voice Main Stage (Screen Share or Member Cards Grid)
            Expanded(
              child: isConnected
                  ? (hasActiveScreenShare
                      ? (state.isWatchingScreenShare
                          ? _buildScreenShareStage(context, state, channelMembers)
                          : _buildParticipantsGrid(state, channelMembers, hasMinimizedStream: true))
                      : _buildParticipantsGrid(state, channelMembers))
                  : _buildDisconnectedPrompt(context, state, channel?.id),
            ),

            // Modern Centered Floating Call Dock (When Connected)
            if (isConnected)
              _buildFloatingDock(context, state),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
      AppState state, String? channelName, bool isConnected, bool hasActiveScreenShare) {
    final isConnecting = state.isConnectingVoice;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: HudTheme.divider, width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.volume_up, color: HudTheme.green, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              channelName ?? 'Sala de Voz',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HudTheme.textHeader,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 16, color: HudTheme.divider),
          const SizedBox(width: 12),

          // Connection Quality Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isConnected
                  ? HudTheme.green.withValues(alpha: 0.15)
                  : (isConnecting ? HudTheme.blurple.withValues(alpha: 0.15) : HudTheme.bgHover),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isConnected
                    ? HudTheme.green.withValues(alpha: 0.4)
                    : (isConnecting ? HudTheme.accent.withValues(alpha: 0.4) : HudTheme.divider),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isConnected ? Icons.network_cell : Icons.sync,
                  color: isConnected ? HudTheme.green : (isConnecting ? HudTheme.accent : HudTheme.textMuted),
                  size: 13,
                ),
                const SizedBox(width: 5),
                Text(
                  // Latência medida pelo próprio SDK, não um rótulo decorativo:
                  // "64 kbps" estava na tela mesmo com a chamada caída.
                  isConnected
                      ? (state.voicePingMs > 0
                          ? 'RTC • ${state.voicePingMs} ms'
                          : 'RTC conectado')
                      : (isConnecting ? 'Conectando...' : 'Desconectado'),
                  style: TextStyle(
                    color: isConnected ? HudTheme.green : (isConnecting ? HudTheme.accent : HudTheme.textMuted),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          if (hasActiveScreenShare) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: HudTheme.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HudTheme.red.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record, color: HudTheme.red, size: 10),
                  SizedBox(width: 4),
                  Text(
                    'AO VIVO',
                    style: TextStyle(
                      color: HudTheme.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildParticipantsGrid(AppState state, List<UserModel> channelMembers, {bool hasMinimizedStream = false}) {
    return Column(
      children: [
        if (hasMinimizedStream)
          Container(
            margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: HudTheme.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: HudTheme.accent.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: HudTheme.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.live_tv, color: HudTheme.accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transmissão ao vivo: ${state.activeScreenSharePresenter ?? "Participante"}',
                        style: const TextStyle(color: HudTheme.textHeader, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Clique para entrar e assistir a transmissão em tela cheia',
                        style: TextStyle(color: HudTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HudTheme.accent,
                    foregroundColor: HudTheme.bgProfile,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('Entrar na Tela', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () => state.setWatchingScreenShare(true),
                ),
              ],
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final count = channelMembers.length;
                // Quantas colunas cabem de verdade: com o critério só pelo
                // número de pessoas, uma janela estreita ganhava três cartões de
                // 16:9 espremidos e uma larga ficava com um único ocupante do
                // lado errado da tela.
                final colunas = count <= 1
                    ? 1
                    : (constraints.maxWidth / 300).floor().clamp(1, count > 4 ? 3 : 2);

                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: min(
                        constraints.maxWidth,
                        count == 1 ? 640 : (count <= 4 ? 960 : 1200),
                      ),
                    ),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: colunas,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 16 / 9,
                      ),
                      itemCount: channelMembers.length,
                      itemBuilder: (context, index) {
                        final member = channelMembers[index];
                        return _ParticipantCard(
                          user: member,
                          isSelf: member.id == state.currentUser.id,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScreenShareStage(BuildContext context, AppState state, List<UserModel> channelMembers) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          // Top Presenter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: HudTheme.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: HudTheme.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.screen_share, color: HudTheme.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  state.isScreenSharing
                      ? 'Você está compartilhando a tela'
                      : 'Tela de ${state.activeScreenSharePresenter ?? "Participante"}',
                  style: const TextStyle(
                    color: HudTheme.textHeader,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (state.isScreenSharing) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: state.isWindowFocused
                          ? HudTheme.green.withValues(alpha: 0.15)
                          : Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: state.isWindowFocused ? HudTheme.green : Colors.amber,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          state.isWindowFocused ? Icons.remove_red_eye : Icons.bolt,
                          size: 13,
                          color: state.isWindowFocused ? HudTheme.green : Colors.amber,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          state.isWindowFocused
                              ? 'Prévia Ativa (Foco)'
                              : 'Modo Eco (Sem Foco)',
                          style: TextStyle(
                            color: state.isWindowFocused ? HudTheme.green : Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (state.isScreenSharing)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: HudTheme.red,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    icon: const Icon(Icons.stop_screen_share, size: 16),
                    label: const Text('Parar Compartilhamento', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: state.stopScreenShare,
                  )
                else
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: HudTheme.textMuted,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.fullscreen_exit, size: 16),
                    label: const Text('Sair da Tela', style: TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: () => state.setWatchingScreenShare(false),
                  ),
              ],
            ),
          ),

          // Center Screen Video View
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HudTheme.divider),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: state.shouldRenderScreenShare
                    ? VideoTrackRenderer(
                        state.activeScreenShareTrack!,
                        fit: VideoViewFit.contain,
                      )
                    : _buildStreamerEcoPlaceholder(context, state),
              ),
            ),
          ),

          // Bottom Participants Strip
          Container(
            height: 64,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: HudTheme.bgCard.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: HudTheme.divider.withValues(alpha: 0.5)),
            ),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              itemCount: channelMembers.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final user = channelMembers[index];
                final isSelf = user.id == state.currentUser.id;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: HudTheme.bgChat,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: user.isSpeaking ? HudTheme.green : HudTheme.divider,
                      width: user.isSpeaking ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: user.isSpeaking ? HudTheme.green : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: user.isSpeaking
                              ? [
                                  BoxShadow(
                                    color: HudTheme.green.withValues(alpha: 0.7),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: isSelf ? HudTheme.blurple : HudTheme.bgHover,
                          child: Text(
                            user.initials,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isSelf ? '${user.username} (Você)' : user.username,
                        style: const TextStyle(
                          color: HudTheme.textHeader,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (user.isMuted) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.mic_off, size: 14, color: HudTheme.red),
                      ],
                      if (user.isScreenSharing) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.screen_share, size: 14, color: HudTheme.accent),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamerEcoPlaceholder(BuildContext context, AppState state) {
    return Container(
      color: const Color(0xFF090C12),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: HudTheme.bgSidebar,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: HudTheme.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: HudTheme.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: HudTheme.green.withValues(alpha: 0.6), width: 2),
                ),
                child: const Icon(
                  Icons.screen_share,
                  color: HudTheme.green,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Transmissão Ao Vivo Ativa',
                style: TextStyle(
                  color: HudTheme.textHeader,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: HudTheme.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record, color: HudTheme.green, size: 10),
                    SizedBox(width: 6),
                    Text(
                      'Transmitindo normalmente para os amigos na sala',
                      style: TextStyle(color: HudTheme.green, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'A prévia de vídeo local foi pausada automaticamente enquanto você usa outro programa para liberar 100% da GPU e CPU para seus jogos e aplicativos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: HudTheme.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Basta clicar de volta na janela do PapoCall para a prévia reaparecer instantaneamente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: HudTheme.textNormal,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: HudTheme.accent,
                  side: const BorderSide(color: HudTheme.accent),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
                label: const Text('Forçar exibição da prévia agora'),
                onPressed: state.toggleForceRenderOwnStream,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingDock(BuildContext context, AppState state) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F22),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF2E333D), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Screen Share Button
          _ModernDockButton(
            icon: state.isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
            tooltip: state.isScreenSharing
                ? 'Parar Compartilhamento de Tela'
                : 'Compartilhar Tela ou Janela',
            isActive: state.isScreenSharing,
            activeColor: HudTheme.accent,
            isDestructive: state.isScreenSharing,
            onPressed: () => _handleScreenShareToggle(context, state),
          ),
          const SizedBox(width: 8),

          // Microphone Button
          _ModernDockButton(
            icon: state.currentUser.isMuted ? Icons.mic_off : Icons.mic,
            tooltip: state.currentUser.isMuted ? 'Desmutar Microfone' : 'Mutar Microfone',
            isActive: !state.currentUser.isMuted,
            activeColor: state.currentUser.isSpeaking ? HudTheme.green : HudTheme.textNormal,
            isDestructive: state.currentUser.isMuted,
            isSpeakingGlow: state.currentUser.isSpeaking,
            onPressed: state.toggleMute,
          ),
          const SizedBox(width: 8),

          // Headset Button
          _ModernDockButton(
            icon: state.currentUser.isDeafened ? Icons.headset_off : Icons.headset,
            tooltip: state.currentUser.isDeafened ? 'Desensurdecer' : 'Ensurdecer',
            isActive: !state.currentUser.isDeafened,
            activeColor: HudTheme.textNormal,
            isDestructive: state.currentUser.isDeafened,
            onPressed: state.toggleDeafen,
          ),
          const SizedBox(width: 12),

          // Vertical Separator
          Container(
            width: 1,
            height: 24,
            color: const Color(0xFF353945),
          ),
          const SizedBox(width: 12),

          // Disconnect Call Button (Red Circle)
          _ModernDockButton(
            icon: Icons.call_end,
            tooltip: 'Desconectar da Chamada',
            isCallEnd: true,
            onPressed: state.disconnectVoice,
          ),
        ],
      ),
    );
  }

  Future<void> _handleScreenShareToggle(BuildContext context, AppState state) async {
    if (state.isScreenSharing) {
      await state.stopScreenShare();
      return;
    }

    try {
      final escolha = await ScreenShareDialog.show(context);

      if (escolha != null) {
        final success = await state.startScreenShare(
          escolha.sourceId,
          width: escolha.width,
          height: escolha.height,
          fps: escolha.fps,
        );
        if (!success && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível iniciar o compartilhamento de tela.'),
              backgroundColor: HudTheme.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao abrir diálogo de seleção de tela: $e');
    }
  }

  Widget _buildDisconnectedPrompt(BuildContext context, AppState state, String? channelId) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: HudTheme.bgCard,
            shape: BoxShape.circle,
            border: Border.all(color: HudTheme.divider),
          ),
          child: const Icon(Icons.headset, size: 54, color: HudTheme.textMuted),
        ),
        const SizedBox(height: 20),
        Text(
          state.isConnectingVoice
              ? 'Conectando ao LiveKit Voice Engine...'
              : 'Você não está nesta sala de voz',
          style: TextStyle(
            color: HudTheme.textHeader.withValues(alpha: 0.9),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          state.isConnectingVoice
              ? 'Negociando SDP e codecs de baixa latência Opus/WebRTC'
              : 'Clique abaixo para entrar na conferência e conversar em tempo real',
          style: const TextStyle(color: HudTheme.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 24),
        if (state.isConnectingVoice)
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: HudTheme.green,
            ),
          )
        else
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.green,
              foregroundColor: Colors.white,
              elevation: 4,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.volume_up, size: 20),
            label: const Text('Entrar na Chamada de Voz', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            onPressed: () async {
              if (channelId == null || state.isConnectingVoice) return;
              final messenger = ScaffoldMessenger.of(context);
              reportVoiceJoinError(messenger, await state.connectVoice(channelId));
            },
          ),
      ],
    );
  }
}

class _ParticipantCard extends StatefulWidget {
  final UserModel user;
  final bool isSelf;

  const _ParticipantCard({
    required this.user,
    required this.isSelf,
  });

  @override
  State<_ParticipantCard> createState() => _ParticipantCardState();
}

class _ParticipantCardState extends State<_ParticipantCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isSpeaking = user.isSpeaking;

    Color borderColor = HudTheme.divider;
    double borderWidth = 1.0;
    if (isSpeaking) {
      borderColor = HudTheme.green;
      borderWidth = 2.5;
    } else if (_isHovered) {
      borderColor = const Color(0xFF4E5058);
      borderWidth = 1.5;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1F22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: isSpeaking
              ? [
                  BoxShadow(
                    color: HudTheme.green.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : (_isHovered
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            children: [
              // Center Avatar with Speaking Halo
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSpeaking ? HudTheme.green : Colors.transparent,
                      width: 3.5,
                    ),
                    boxShadow: isSpeaking
                        ? [
                            BoxShadow(
                              color: HudTheme.green.withValues(alpha: 0.8),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: HudTheme.green.withValues(alpha: 0.4),
                              blurRadius: 28,
                              spreadRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                  child: CircleAvatar(
                    radius: 38,
                    backgroundColor: widget.isSelf ? HudTheme.blurple : const Color(0xFF2B2D31),
                    child: Text(
                      user.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),

              // Top-right Live Badge
              if (user.isScreenSharing)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: HudTheme.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.screen_share, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'AO VIVO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Bottom-left Translucent Participant Name & Status Pill
              Positioned(
                bottom: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (user.isMuted) ...[
                        const Icon(Icons.mic_off, color: HudTheme.red, size: 14),
                        const SizedBox(width: 6),
                      ],
                      if (user.isDeafened) ...[
                        const Icon(Icons.headset_off, color: HudTheme.red, size: 14),
                        const SizedBox(width: 6),
                      ],
                      if (isSpeaking && !user.isMuted) ...[
                        const Icon(Icons.graphic_eq, color: HudTheme.green, size: 14),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        widget.isSelf ? '${user.username} (Você)' : user.username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModernDockButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;
  final Color? activeColor;
  final bool isDestructive;
  final bool isSpeakingGlow;
  final bool isCallEnd;

  const _ModernDockButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
    this.activeColor,
    this.isDestructive = false,
    this.isSpeakingGlow = false,
    this.isCallEnd = false,
  });

  @override
  State<_ModernDockButton> createState() => _ModernDockButtonState();
}

class _ModernDockButtonState extends State<_ModernDockButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color iconColor;

    if (widget.isCallEnd) {
      bg = _isHovered ? const Color(0xFFF23F43) : const Color(0xFFDA373C);
      iconColor = Colors.white;
    } else if (widget.isDestructive) {
      bg = _isHovered
          ? HudTheme.red.withValues(alpha: 0.3)
          : HudTheme.red.withValues(alpha: 0.18);
      iconColor = HudTheme.red;
    } else if (widget.isActive) {
      bg = _isHovered ? const Color(0xFF3F444E) : const Color(0xFF35373C);
      iconColor = widget.activeColor ?? Colors.white;
    } else {
      bg = _isHovered ? const Color(0xFF3F444E) : const Color(0xFF2B2D31);
      iconColor = _isHovered ? Colors.white : const Color(0xFFB5BAC1);
    }

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: widget.isSpeakingGlow
                  ? [
                      BoxShadow(
                        color: HudTheme.green.withValues(alpha: 0.6),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : (_isHovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null),
            ),
            child: Icon(
              widget.icon,
              color: iconColor,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

