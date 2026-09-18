import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'channels_sidebar.dart';
import 'server_rail.dart';
import 'user_profile_bar.dart';
import 'voice_connection_hud.dart';

/// Painel esquerdo unificado que agrupa o Server Rail (72px) e os Canais (240px),
/// estendendo a barra de conexão de voz e a barra do perfil de usuário por toda
/// a largura inferior (312px), exatamente como na arquitetura do webapp.
class AppLeftPanel extends StatelessWidget {
  const AppLeftPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      width: 312,
      decoration: const BoxDecoration(
        color: HudTheme.bgSidebar,
        border: Border(
          right: BorderSide(color: HudTheme.divider, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Área Superior: Rail de Servidores (72px) + Lista de Canais (240px)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                ServerRail(),
                Expanded(child: ChannelsSidebar()),
              ],
            ),
          ),

          // HUD de Conexão de Voz estendido por toda a largura inferior (312px)
          if (state.connectedVoiceChannelId != null || state.isConnectingVoice)
            const VoiceConnectionHud(),

          // Barra de Perfil do Usuário estendida por toda a largura inferior (312px)
          const UserProfileBar(),
        ],
      ),
    );
  }
}
