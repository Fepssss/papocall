import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:livekit_client/livekit_client.dart';
import '../models/server.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import '../utils/voice_feedback.dart';
import 'acao_compartilhar_tela.dart';
import 'member_context_menu.dart';
import 'anel_de_fala.dart';
import 'modals/live_settings_dialog.dart';
import 'retrato_usuario.dart';

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

    // Na tela cheia a barra do canal e o dock de mutar saem de cena: o palco é
    // a janela inteira, e os controles voltam a existir quando se sai dela.
    final telaCheia = isConnected &&
        hasActiveScreenShare &&
        state.isWatchingScreenShare &&
        state.modoDeExibicao == ModoDeExibicao.telaCheia;

    return Expanded(
      child: Container(
        color: HudTheme.bgChat,
        child: Column(
          children: [
            // Voice Header Bar
            if (!telaCheia) _buildHeader(state, channel?.name, isConnected, hasActiveScreenShare),

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
            if (isConnected && !telaCheia)
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
                          servidor: state.servidorDoCanal(state.connectedVoiceChannelId),
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

  /// O palco da transmissão nos três modos de exibição.
  ///
  /// `normal` empilha barra, vídeo e faixa de participantes. `teatro` deixa o
  /// vídeo crescer até onde der e põe a faixa por cima dele. `telaCheia` toma a
  /// janela inteira — o painel esquerdo e a barra de membros saem no `MainScreen`
  /// — e os controles viram duas ilhas flutuantes, porque sem elas não haveria
  /// como sair de onde a pessoa acabou de entrar.
  Widget _buildScreenShareStage(BuildContext context, AppState state, List<UserModel> channelMembers) {
    final barra = _buildLiveBar(context, state);
    final faixa = _buildParticipantStrip(state, channelMembers);
    final palco = _buildPalco(context, state);

    if (state.modoDeExibicao == ModoDeExibicao.telaCheia) {
      return Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.black, child: palco)),
          Positioned(top: 10, left: 16, right: 16, child: barra),
          Positioned(bottom: 10, left: 16, right: 16, child: faixa),
        ],
      );
    }

    if (state.modoDeExibicao == ModoDeExibicao.teatro) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            barra,
            const SizedBox(height: 8),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: Container(color: Colors.black, child: palco)),
                  Positioned(bottom: 8, left: 8, right: 8, child: faixa),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          barra,
          const SizedBox(height: 8),
          Expanded(child: Container(color: Colors.black, child: palco)),
          const SizedBox(height: 8),
          faixa,
        ],
      ),
    );
  }

  Widget _buildPalco(BuildContext context, AppState state) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: state.shouldRenderScreenShare
          ? VideoTrackRenderer(state.activeScreenShareTrack!, fit: VideoViewFit.contain)
          : _buildStreamerEcoPlaceholder(context, state),
    );
  }

  /// Barra de cima da live: quem transmite configura e para; quem assiste regula
  /// o volume e escolhe como quer ver.
  Widget _buildLiveBar(BuildContext context, AppState state) {
    final fullscreen = state.modoDeExibicao == ModoDeExibicao.telaCheia;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: fullscreen ? HudTheme.bgCard.withValues(alpha: 0.92) : HudTheme.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HudTheme.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.screen_share, color: HudTheme.accent, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              state.isScreenSharing
                  ? 'Você está compartilhando a tela'
                  : 'Tela de ${state.activeScreenSharePresenter ?? "Participante"}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HudTheme.textHeader,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Quem assiste ouve a transmissão pela mesma saída do resto da call,
          // então o controle só aparece quando a faixa de áudio existe de fato.
          if (!state.isScreenSharing && state.liveComAudio) ...[
            const Icon(Icons.volume_down_rounded, color: HudTheme.textMuted, size: 16),
            SizedBox(
              width: 110,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  activeTrackColor: HudTheme.green,
                  inactiveTrackColor: HudTheme.bgHover,
                  thumbColor: HudTheme.green,
                  overlayColor: HudTheme.green.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: state.volumeDaLive,
                  onChanged: state.ajustarVolumeDaLive,
                  onChangeEnd: (v) => state.definirVolumeDaLive(v),
                ),
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${(state.volumeDaLive * 100).round()}%',
                style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
              ),
            ),
            const SizedBox(width: 6),
          ],

          const Spacer(),

          if (state.isScreenSharing) ...[
            const _ChipFoco(),
            const SizedBox(width: 10),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: HudTheme.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Configurar transmissão', style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () => LiveSettingsDialog.show(context),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: HudTheme.red,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              icon: const Icon(Icons.stop_screen_share, size: 16),
              label: const Text('Parar', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: state.stopScreenShare,
            ),
          ] else ...[
            _ModoButton(
              icone: state.modoDeExibicao == ModoDeExibicao.teatro
                  ? Icons.crop_din_rounded
                  : Icons.theater_comedy_outlined,
              tooltip: state.modoDeExibicao == ModoDeExibicao.teatro
                  ? 'Sair do modo teatro'
                  : 'Modo teatro',
              ativo: state.modoDeExibicao == ModoDeExibicao.teatro,
              onPressed: () => state.definirModoDeExibicao(
                state.modoDeExibicao == ModoDeExibicao.teatro
                    ? ModoDeExibicao.normal
                    : ModoDeExibicao.teatro,
              ),
            ),
            const SizedBox(width: 6),
            _ModoButton(
              icone: state.modoDeExibicao == ModoDeExibicao.telaCheia
                  ? Icons.fullscreen_exit
                  : Icons.fullscreen,
              tooltip: state.modoDeExibicao == ModoDeExibicao.telaCheia
                  ? 'Sair da tela cheia (Esc)'
                  : 'Tela cheia',
              ativo: fullscreen,
              onPressed: () => state.definirModoDeExibicao(
                fullscreen ? ModoDeExibicao.normal : ModoDeExibicao.telaCheia,
              ),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: HudTheme.textMuted,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              icon: const Icon(Icons.visibility_off_outlined, size: 16),
              label: const Text('Sair da Tela', style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () => state.setWatchingScreenShare(false),
            ),
          ],
        ],
      ),
    );
  }

  /// A faixa de quem está na sala, a mesma nos três modos.
  Widget _buildParticipantStrip(AppState state, List<UserModel> channelMembers) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: HudTheme.bgCard.withValues(alpha: 0.9),
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
          final servidor = state.servidorDoCanal(state.connectedVoiceChannelId);
          final pill = Container(
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
                AnelDeFala(
                  falando: user.isSpeaking,
                  child: RetratoUsuario(
                    avatar: user.avatar,
                    iniciais: user.initials,
                    raio: 12,
                    corQuandoSemFoto: isSelf ? HudTheme.blurple : HudTheme.bgHover,
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
                if (user.isCameraOn) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.videocam_rounded, size: 14, color: HudTheme.green),
                ],
                if (user.isScreenSharing) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.screen_share, size: 14, color: HudTheme.accent),
                ],
              ],
            ),
          );
          // Botão direito no nome de quem está na sala, inclusive no meu: sobre a
          // própria pessoa o menu vem com silenciar e ensurdecer, que é o que a
          // foto do Discord mostra.
          if (servidor == null) return pill;
          return GestureDetector(
            onSecondaryTapUp: (detalhes) => VoiceMemberMenu.show(
              context,
              servidor,
              user,
              detalhes.globalPosition,
              naChamada: true,
            ),
            child: pill,
          );
        },
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
            onPressed: () => alternarCompartilhamentoDeTela(context, state),
          ),
          const SizedBox(width: 8),

          // Camera Button
          _ModernDockButton(
            icon: state.cameraAtiva ? Icons.videocam : Icons.videocam_off,
            tooltip: state.cameraAtiva ? 'Desligar câmera' : 'Ligar câmera',
            isActive: state.cameraAtiva,
            activeColor: HudTheme.green,
            isDestructive: !state.cameraAtiva,
            // O motivo vem do Windows, traduzido: sem isto a pessoa clicava e
            // nada acontecia, sem saber se era permissão, câmera ocupada ou
            // falta de câmera.
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              reportVoiceJoinError(messenger, await state.alternarCamera());
            },
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

  /// O servidor do canal onde a pessoa está: é o que o menu do botão direito
  /// precisa para saber o que se pode fazer com aquele membro.
  final Server? servidor;

  const _ParticipantCard({
    required this.user,
    required this.isSelf,
    this.servidor,
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

    // O vídeo é buscado na hora, e não guardado no `UserModel`: a faixa pertence
    // ao LiveKit, vive enquanto a publicação existe, e um cartão que segurasse
    // uma referência morta desenharia o último quadro de alguém que já desligou
    // a câmera. "Desativar vídeo" no menu do botão direito cai no mesmo caminho:
    // a faixa existe, mas eu escolhi não ver.
    final state = context.read<AppState>();
    final video = user.isCameraOn && !state.videoOcultoDe(user.username)
        ? state.cameraDe(user.username)
        : null;

    Color borderColor = HudTheme.divider;
    double borderWidth = 1.0;
    if (isSpeaking) {
      borderColor = HudTheme.green;
      borderWidth = 2.5;
    } else if (_isHovered) {
      borderColor = const Color(0xFF4E5058);
      borderWidth = 1.5;
    }

    // Botão direito no cartão de quem está na sala — inclusive no meu, que é o
    // que a foto do Discord mostra: sobre a própria pessoa o menu vem com
    // silenciar e ensurdecer, e sem as linhas de amizade ou gestão.
    Widget cartao = MouseRegion(
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
              // O vídeo da pessoa, quando ela está publicando. Espelhado só na
              // própria prévia: é o que se espera de um autorretrato, e quem
              // olha de fora tem de ver a cena como ela é.
              if (video != null)
                Positioned.fill(
                  child: Transform.scale(
                    scaleX: widget.isSelf ? -1 : 1,
                    child: VideoTrackRenderer(video, fit: VideoViewFit.cover),
                  ),
                ),

              // Center Avatar with Speaking Halo
              if (video == null)
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
                    child: RetratoUsuario(
                      avatar: user.avatar,
                      iniciais: user.initials,
                      raio: 38,
                      corQuandoSemFoto: widget.isSelf ? HudTheme.blurple : const Color(0xFF2B2D31),
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

    final servidor = widget.servidor;
    if (servidor == null) return cartao;
    return GestureDetector(
      onSecondaryTapUp: (detalhes) => VoiceMemberMenu.show(
        context,
        servidor,
        user,
        detalhes.globalPosition,
        naChamada: true,
      ),
      child: cartao,
    );
  }
}

/// Botao quadrado de modo de exibicao da live: teatro e tela cheia.
class _ModoButton extends StatefulWidget {
  const _ModoButton({
    required this.icone,
    required this.tooltip,
    required this.ativo,
    required this.onPressed,
  });

  final IconData icone;
  final String tooltip;
  final bool ativo;
  final VoidCallback onPressed;

  @override
  State<_ModoButton> createState() => _ModoButtonState();
}

class _ModoButtonState extends State<_ModoButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: widget.ativo
                  ? HudTheme.accent.withValues(alpha: 0.2)
                  : (_hover ? HudTheme.bgHover : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.ativo ? HudTheme.accent : HudTheme.divider,
              ),
            ),
            child: Icon(
              widget.icone,
              size: 16,
              color: widget.ativo ? HudTheme.accent : HudTheme.textNormal,
            ),
          ),
        ),
      ),
    );
  }
}

/// O aviso de que a previa de quem transmite depende do foco da janela.
class _ChipFoco extends StatelessWidget {
  const _ChipFoco();

  @override
  Widget build(BuildContext context) {
    final emFoco = context.watch<AppState>().isWindowFocused;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: emFoco ? HudTheme.green.withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: emFoco ? HudTheme.green : Colors.amber),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            emFoco ? Icons.remove_red_eye : Icons.bolt,
            size: 13,
            color: emFoco ? HudTheme.green : Colors.amber,
          ),
          const SizedBox(width: 5),
          Text(
            emFoco ? 'Prévia Ativa (Foco)' : 'Modo Eco (Sem Foco)',
            style: TextStyle(
              color: emFoco ? HudTheme.green : Colors.amber,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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

