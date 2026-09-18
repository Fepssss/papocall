import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/chat_message.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _lastChannelId;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _syncDraftForChannel(AppState state, String? currentChannelId) {
    if (currentChannelId != _lastChannelId) {
      if (_lastChannelId != null) {
        state.setDraft(_lastChannelId!, _textController.text);
      }
      _lastChannelId = currentChannelId;
      if (currentChannelId != null) {
        final draft = state.getDraft(currentChannelId);
        _textController.text = draft;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: draft.length),
        );
      } else {
        _textController.clear();
      }
    }
  }

  void _handleSend(AppState state) {
    final text = _textController.text.trim();
    final channelId = state.activeChannelId;
    if (text.isNotEmpty) {
      state.sendMessage(text);
      state.clearDraft(channelId);
      _textController.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final channel = state.activeChannel;
    final messages = state.activeMessages;

    _syncDraftForChannel(state, channel?.id);

    return Expanded(
      child: Container(
        color: HudTheme.bgChat,
        child: Column(
          children: [
            // Channel Header
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: HudTheme.divider, width: 1)),
              ),
              child: Row(
                children: [
                  Icon(
                    channel?.type == ChannelType.voice ? Icons.volume_up : Icons.tag,
                    color: HudTheme.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    channel?.name ?? 'geral',
                    style: const TextStyle(
                      color: HudTheme.textHeader,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  if (channel != null && channel.topic.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Container(width: 1, height: 16, color: HudTheme.divider),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        channel.topic,
                        style: const TextStyle(color: HudTheme.textMuted, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Messages Feed
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  return _ChatMessageTile(msg: msg);
                },
              ),
            ),

            // Chat Input Bar
            Container(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: HudTheme.bgInput,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        style: const TextStyle(color: HudTheme.textNormal, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Conversar em #${channel?.name ?? "geral"}',
                          hintStyle: const TextStyle(color: HudTheme.textMuted),
                          border: InputBorder.none,
                        ),
                        onChanged: (val) {
                          if (channel?.id != null) {
                            state.setDraft(channel!.id, val);
                          }
                        },
                        onSubmitted: (_) => _handleSend(state),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.gif_box, color: HudTheme.textMuted),
                      tooltip: 'Enviar GIF',
                      onPressed: () {
                        // Quick send popular GIF
                        state.sendMessage('', gifUrl: 'https://media.giphy.com/media/jpbnoe3UIa8TU8LM13/giphy.gif');
                        _scrollToBottom();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: HudTheme.blurple),
                      tooltip: 'Enviar Mensagem',
                      onPressed: () => _handleSend(state),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessageTile extends StatefulWidget {
  final ChatMessage msg;

  const _ChatMessageTile({required this.msg});

  @override
  State<_ChatMessageTile> createState() => _ChatMessageTileState();
}

class _ChatMessageTileState extends State<_ChatMessageTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _isHovered ? HudTheme.bgHover.withValues(alpha: 0.5) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: msg.isSystem ? HudTheme.green : HudTheme.blurple,
              child: Text(
                msg.author.isNotEmpty ? msg.author[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        msg.author,
                        style: const TextStyle(
                          color: HudTheme.textHeader,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        msg.timestamp,
                        style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (msg.text.isNotEmpty)
                    Text(
                      msg.text,
                      style: const TextStyle(color: HudTheme.textNormal, fontSize: 14, height: 1.3),
                    ),
                  if (msg.gifUrl != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        msg.gifUrl!,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Text('[GIF não carregado]', style: TextStyle(color: HudTheme.red)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

