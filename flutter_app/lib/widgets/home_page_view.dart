import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/server.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';

class HomePageView extends StatelessWidget {
  const HomePageView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentUser = state.currentUser;
    final activeServer = state.activeServer;
    final isVoiceConnected = state.connectedVoiceChannelId != null;

    return Container(
      color: HudTheme.bgChat,
      child: Column(
        children: [
          // Top Header Bar
          _buildTopBar(context, state),

          // Main Scrollable Dashboard Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero Welcome Card
                  _buildHeroCard(context, state, currentUser),
                  const SizedBox(height: 24),

                  // Call Status Banner (if connected to voice)
                  if (isVoiceConnected) ...[
                    _buildActiveCallBanner(context, state),
                    const SizedBox(height: 24),
                  ],

                  // Two-Column Grid: Quick Channels & Online Friends
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 800;
                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildQuickChannelsCard(context, state, activeServer)),
                            const SizedBox(width: 20),
                            Expanded(child: _buildFriendsCard(context, state)),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            _buildQuickChannelsCard(context, state, activeServer),
                            const SizedBox(height: 20),
                            _buildFriendsCard(context, state),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  // System Status & Features Card
                  _buildSystemStatusCard(state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, AppState state) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: HudTheme.bgSidebar,
        border: Border(bottom: BorderSide(color: HudTheme.divider, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: HudTheme.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.home_rounded, color: HudTheme.green, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            'Página Inicial do App',
            style: TextStyle(
              color: HudTheme.textHeader,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          // Back to Active Server Button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: HudTheme.textHeader,
              side: const BorderSide(color: HudTheme.divider),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.arrow_back, size: 16, color: HudTheme.accent),
            label: Text(
              'Ir para ${state.activeServer?.name ?? 'Servidor'}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            onPressed: state.closeHomePage,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, AppState state, UserModel user) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HudTheme.bgCard,
            HudTheme.bgSidebar.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HudTheme.green.withValues(alpha: 0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // User Avatar with Ring
          Stack(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: HudTheme.bgHover,
                child: Text(
                  user.username.isNotEmpty
                      ? user.username.replaceAll('@', '').substring(0, 1).toUpperCase()
                      : 'P',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: HudTheme.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: HudTheme.bgCard, width: 3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // Greetings & Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Bem-vindo ao PapoCall, ${user.username}!',
                      style: const TextStyle(
                        color: HudTheme.textHeader,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: HudTheme.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: HudTheme.green.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        'v1.0.0c',
                        style: TextStyle(color: HudTheme.green, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Comunicação por voz de alta performance, compartilhamento de tela com economia de GPU e chat instantâneo.',
                  style: TextStyle(color: HudTheme.textMuted, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          // Action Button to Go to Channels
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 4,
            ),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Abrir Conversas', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: state.closeHomePage,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCallBanner(BuildContext context, AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: HudTheme.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HudTheme.green.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.volume_up, color: HudTheme.green, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Você está em uma chamada de voz ativa',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  'Canal: #${state.activeChannel?.name ?? state.connectedVoiceChannelId}',
                  style: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: HudTheme.green,
              backgroundColor: HudTheme.green.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.headset, size: 16),
            label: const Text('Voltar para a Call', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              state.closeHomePage();
              if (state.connectedVoiceChannelId != null) {
                state.selectChannel(state.connectedVoiceChannelId!);
              }
            },
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Desconectar da chamada',
            icon: const Icon(Icons.call_end, color: HudTheme.red, size: 20),
            onPressed: state.disconnectVoice,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChannelsCard(BuildContext context, AppState state, Server? server) {
    final channels = server?.channels ?? [];
    final voiceChannels = channels.where((c) => c.type == ChannelType.voice).toList();
    final textChannels = channels.where((c) => c.type == ChannelType.text).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HudTheme.bgSidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HudTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.explore_outlined, color: HudTheme.accent, size: 20),
              const SizedBox(width: 10),
              Text(
                'Canais do Servidor (${server?.name ?? 'PapoCall'})',
                style: const TextStyle(color: HudTheme.textHeader, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Voice Channels Section
          const Text('Salas de Voz', style: TextStyle(color: HudTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (voiceChannels.isEmpty)
            const Text('Nenhuma sala de voz disponível.', style: TextStyle(color: HudTheme.textMuted, fontSize: 13))
          else
            ...voiceChannels.map((c) {
              final isConnected = state.connectedVoiceChannelId == c.id;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isConnected ? HudTheme.green.withValues(alpha: 0.1) : HudTheme.bgCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isConnected ? HudTheme.green.withValues(alpha: 0.3) : HudTheme.divider),
                ),
                child: Row(
                  children: [
                    Icon(Icons.volume_up, color: isConnected ? HudTheme.green : HudTheme.textMuted, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.name,
                        style: TextStyle(
                          color: isConnected ? Colors.white : HudTheme.textNormal,
                          fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConnected ? HudTheme.bgHover : HudTheme.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(60, 30),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () {
                        state.selectChannel(c.id);
                        if (!isConnected) {
                          state.connectVoice(c.id);
                        }
                        state.closeHomePage();
                      },
                      child: Text(
                        isConnected ? 'Ver Sala' : 'Entrar',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 16),
          // Text Channels Section
          const Text('Canais de Chat', style: TextStyle(color: HudTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (textChannels.isEmpty)
            const Text('Nenhum canal de texto disponível.', style: TextStyle(color: HudTheme.textMuted, fontSize: 13))
          else
            ...textChannels.map((c) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: HudTheme.bgCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: HudTheme.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tag, color: HudTheme.textMuted, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.name,
                        style: const TextStyle(color: HudTheme.textNormal, fontSize: 13),
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HudTheme.accent,
                        side: const BorderSide(color: HudTheme.divider),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(60, 30),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () {
                        state.selectChannel(c.id);
                        state.closeHomePage();
                      },
                      child: const Text('Abrir Chat', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildFriendsCard(BuildContext context, AppState state) {
    final friends = state.onlineMembers;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HudTheme.bgSidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HudTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt_outlined, color: HudTheme.green, size: 20),
              const SizedBox(width: 10),
              Text(
                'Amigos & Conexões (${friends.length})',
                style: const TextStyle(color: HudTheme.textHeader, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (friends.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Column(
                children: const [
                  Icon(Icons.person_off_outlined, color: HudTheme.textMuted, size: 36),
                  SizedBox(height: 8),
                  Text(
                    'Nenhum amigo online no momento.\nConvide amigos com o link do PapoCall!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: HudTheme.textMuted, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: friends.length,
              itemBuilder: (context, index) {
                final friend = friends[index];
                final inCall = friend.currentVoiceChannelId != null;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: HudTheme.bgCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: HudTheme.divider),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: HudTheme.bgHover,
                        child: Text(
                          friend.username.replaceAll('@', '').substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              friend.username,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              inCall ? 'Em chamada (#${friend.currentVoiceChannelId})' : 'Online',
                              style: TextStyle(
                                color: inCall ? HudTheme.green : HudTheme.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (inCall)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HudTheme.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(70, 28),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          icon: const Icon(Icons.call, size: 12),
                          label: const Text('Juntar-se', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            state.connectVoice(friend.currentVoiceChannelId!);
                            state.selectChannel(friend.currentVoiceChannelId!);
                            state.closeHomePage();
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusCard(AppState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HudTheme.bgSidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HudTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.speed, color: HudTheme.accent, size: 20),
              SizedBox(width: 10),
              Text(
                'Status do Sistema & Desempenho (v1.0.0c)',
                style: TextStyle(color: HudTheme.textHeader, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatusPill(
                title: 'LiveKit Voice Engine',
                status: state.connectedVoiceChannelId != null ? 'Conectado (RTC)' : 'Pronto',
                isGood: true,
              ),
              const SizedBox(width: 12),
              _buildStatusPill(
                title: 'Rede MQTT Pub/Sub',
                status: 'Ativo (TCP 1883 / WSS)',
                isGood: true,
              ),
              const SizedBox(width: 12),
              _buildStatusPill(
                title: 'Renderização Inteligente',
                status: 'Modo Eco Streamer Ativo',
                isGood: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill({required String title, required String status, required bool isGood}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: HudTheme.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: HudTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: HudTheme.textMuted, fontSize: 11)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isGood ? HudTheme.green : HudTheme.yellow,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  status,
                  style: TextStyle(
                    color: isGood ? Colors.white : HudTheme.yellow,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
