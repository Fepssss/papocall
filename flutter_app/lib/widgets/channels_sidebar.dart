import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/role.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import '../utils/voice_feedback.dart';
import 'anel_de_fala.dart';
import 'channel_context_menu.dart';

class ChannelsSidebar extends StatelessWidget {
  const ChannelsSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final srv = state.activeServer;
    final canManage = srv != null && state.can(srv.id, Permissions.manageChannels);

    final textChannels = srv?.channels.where((c) => c.type == ChannelType.text).toList() ?? [];
    final voiceChannels = srv?.channels.where((c) => c.type == ChannelType.voice).toList() ?? [];

    return Container(
      color: HudTheme.bgSidebar,
      child: Column(
        children: [
          // Server Header
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: HudTheme.divider, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
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
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HudTheme.textHeader,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.keyboard_arrow_down, color: HudTheme.textNormal),
              ],
            ),
          ),

          // Enquanto a estrutura real do servidor não chega pela rede, os canais
          // mostrados são um esqueleto provisório. Entrar numa sala de voz
          // agora significa entrar sozinho numa sala que os outros membros não
          // enxergam, então o usuário precisa saber que ainda falta sincronizar.
          if (srv != null && !srv.isSynced)
            Container(
              width: double.infinity,
              color: HudTheme.bgSidebar,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: const Row(
                children: [
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: HudTheme.textMuted),
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Sincronizando canais com os outros membros...',
                      style: TextStyle(color: HudTheme.textMuted, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),

          // Channels List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                // Text Channels Category
                _buildCategoryHeader(context, state, srv?.id ?? '', 'CANAIS DE TEXTO',
                    canManage: canManage, type: ChannelType.text),
                ...textChannels.map((c) => _buildChannelItem(context, c, state, canManage)),
                const SizedBox(height: 16),
                // Voice Channels Category
                _buildCategoryHeader(context, state, srv?.id ?? '', 'CANAIS DE VOZ',
                    canManage: canManage, type: ChannelType.voice),
                ...voiceChannels.map((c) => _buildChannelItem(context, c, state, canManage)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(
    BuildContext context,
    AppState state,
    String serverId,
    String title, {
    required bool canManage,
    required ChannelType type,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: HudTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Criar canal é a única ação nova que a barra oferece, e ela só aparece
          // para quem tem 'gerenciar_canais'.
          if (canManage)
            GestureDetector(
              onTap: () => _promptNewChannel(context, state, serverId, type),
              child: const Tooltip(
                message: 'Criar canal',
                child: Icon(Icons.add_rounded, size: 16, color: HudTheme.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _promptNewChannel(
    BuildContext context,
    AppState state,
    String serverId,
    ChannelType type,
  ) async {
    final name = await _ChannelNameDialog.show(context, type);
    if (name == null || name.trim().isEmpty) return;
    final ok = await state.addChannel(serverId, name: name, type: type);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível criar o canal — ele já existe ou é o último.'),
          backgroundColor: HudTheme.red,
        ),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppState state,
    String serverId,
    Channel channel,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.bgSidebar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: HudTheme.divider),
        ),
        title: Text(
          channel.type == ChannelType.text
              ? 'Apagar #${channel.name}'
              : 'Apagar "${channel.name}"',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'O canal some para todos os membros do servidor. As mensagens que ele guarda '
          'continuam no computador de cada um até serem sincronizadas de novo.',
          style: TextStyle(color: HudTheme.textNormal, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: HudTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: HudTheme.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Apagar',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await state.deleteChannel(serverId, channel.id);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Um servidor precisa manter ao menos um canal.'),
          backgroundColor: HudTheme.red,
        ),
      );
    }
  }

  Widget _buildChannelItem(
      BuildContext context, Channel channel, AppState state, bool canManage) {
    final isText = channel.type == ChannelType.text;
    final isSelected = state.activeChannelId == channel.id;
    final isConnected = state.connectedVoiceChannelId == channel.id;

    // Usuários atualmente dentro desta sala de voz.
    //
    // Na sala em que estamos, a lista vem do LiveKit — ele é quem sabe quem
    // entrou e saiu. Para as demais salas só resta a presença anunciada pelo
    // broker, que é aproximada e atrasada.
    final voiceUsers = <UserModel>[];
    if (!isText) {
      if (isConnected) {
        voiceUsers.addAll(state.ocupantesDaChamada.isEmpty
            ? [state.currentUser]
            : state.ocupantesDaChamada);
      } else {
        for (final m in state.onlineMembers) {
          if (m.currentVoiceChannelId == channel.id &&
              !voiceUsers.any((u) => u.id == m.id)) {
            voiceUsers.add(m);
          }
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
            canDelete: canManage,
            mentionCount: isText ? state.mentionCountFor(channel.id) : 0,
            onDelete: () => _confirmDelete(context, state, state.activeServerId, channel),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              state.selectChannel(channel.id);
              if (isText) return;
              if (state.connectedVoiceChannelId == channel.id || state.isConnectingVoice) return;
              reportVoiceJoinError(messenger, await state.connectVoice(channel.id));
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
  final bool canDelete;
  final int mentionCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChannelRow({
    required this.channel,
    required this.isText,
    required this.isSelected,
    required this.isConnected,
    required this.canDelete,
    required this.mentionCount,
    required this.onTap,
    required this.onDelete,
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
        onSecondaryTapDown: (down) => ChannelContextMenu.show(
          context,
          channel: widget.channel,
          globalPosition: down.globalPosition,
          canDelete: widget.canDelete,
          onDelete: widget.onDelete,
        ),
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
                    color: widget.mentionCount > 0 ? HudTheme.textHeader : textColor,
                    fontWeight: (widget.isSelected || widget.isConnected || widget.mentionCount > 0)
                        ? FontWeight.bold
                        : FontWeight.w500,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Quantas mensagens ainda não lidas deste canal marcam o usuário.
              if (widget.mentionCount > 0) ...[
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: HudTheme.green,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    widget.mentionCount > 99 ? '99+' : '${widget.mentionCount}',
                    style: const TextStyle(
                      color: Color(0xFF0B0E14),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              if (!widget.isText && widget.isConnected)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: HudTheme.green,
                    shape: BoxShape.circle,
                  ),
                ),
              // Lixeira no hover só dos canais de texto. Numa sala de voz o
              // clique serve para entrar, e o ícone vermelho ficava no meio do
              // caminho; apagar sala de voz continua possível pelo botão direito.
              if (widget.canDelete && widget.isText && _isHovered)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    child: const Tooltip(
                      message: 'Apagar canal',
                      child: Icon(Icons.delete_outline_rounded, size: 15, color: HudTheme.red),
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
            AnelDeFala(
              falando: widget.user.isSpeaking,
              child: CircleAvatar(
                radius: 11,
                backgroundColor: widget.isSelf ? HudTheme.blurple : HudTheme.bgHover,
                child: Text(
                  widget.user.initials,
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.isSelf ? '${widget.user.username} (Você)' : widget.user.username,
                style: TextStyle(
                  // O nome acompanha o anel: na lista estreita é a letra verde
                  // que se percebe primeiro, antes do brilho em volta do círculo.
                  color: widget.user.isSpeaking
                      ? HudTheme.green
                      : ((widget.isSelf || _isHovered) ? HudTheme.textHeader : HudTheme.textNormal),
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

/// Caixa mínima de criação de canal: um nome e o tipo, que já vem da seção em
/// que o "+" foi clicado.
class _ChannelNameDialog extends StatefulWidget {
  const _ChannelNameDialog({required this.type});

  final ChannelType type;

  static Future<String?> show(BuildContext context, ChannelType type) {
    return showDialog<String>(
      context: context,
      builder: (_) => _ChannelNameDialog(type: type),
    );
  }

  @override
  State<_ChannelNameDialog> createState() => _ChannelNameDialogState();
}

class _ChannelNameDialogState extends State<_ChannelNameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isText = widget.type == ChannelType.text;
    return AlertDialog(
      backgroundColor: HudTheme.bgSidebar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: HudTheme.divider),
      ),
      title: Text(
        isText ? 'Novo canal de texto' : 'Novo canal de voz',
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: min(320.0, MediaQuery.sizeOf(context).width - 96),
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 24,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          onSubmitted: (v) => Navigator.of(context).pop(v),
          decoration: InputDecoration(
            hintText: isText ? 'ex: táticas, clipes...' : 'ex: Sala Alfa...',
            hintStyle: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
            counterText: '',
            filled: true,
            fillColor: HudTheme.bgCard,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: HudTheme.divider),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar', style: TextStyle(color: HudTheme.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: HudTheme.green),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Criar',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
