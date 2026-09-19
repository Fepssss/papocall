import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/chat_message.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import '../utils/mentions.dart';
import 'mention_text.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  String? _lastChannelId;

  /// Estado do autocompletar de marcações.
  List<UserModel> _mentionSuggestions = const [];
  MentionQuery? _mentionQuery;
  int _mentionCursor = 0;

  /// Marca que o Enter já foi consumido para confirmar uma marcação.
  ///
  /// O Enter chega por dois caminhos independentes — o tratador de teclas e o
  /// `onSubmitted` do campo — e não há garantia de ordem entre eles. Sem esta
  /// trava, confirmar a marcação com Enter também enviaria a mensagem no mesmo
  /// toque, meio escrita.
  bool _enterConsumido = false;

  bool get _isMentioning => _mentionQuery != null && _mentionSuggestions.isNotEmpty;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _syncDraftForChannel(AppState state, String? currentChannelId) {
    if (currentChannelId != _lastChannelId) {
      if (_lastChannelId != null) {
        state.setDraft(_lastChannelId!, _textController.text);
      }
      _lastChannelId = currentChannelId;
      _closeMentions();
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

  // --- Autocompletar de marcações ----------------------------------------

  void _closeMentions() {
    if (_mentionQuery == null && _mentionSuggestions.isEmpty) return;
    setState(() {
      _mentionQuery = null;
      _mentionSuggestions = const [];
      _mentionCursor = 0;
    });
  }

  /// Recalcula a lista de sugestões a partir do que está imediatamente antes do
  /// cursor. Chamado a cada digitação e a cada mudança de seleção.
  void _refreshMentions(AppState state) {
    final selection = _textController.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _closeMentions();
      return;
    }

    final query = mentionQueryAt(_textController.text, selection.baseOffset);
    if (query == null) {
      _closeMentions();
      return;
    }

    final termo = query.term;
    final candidatos = state.mentionCandidates().where((u) {
      if (termo.isEmpty) return true;
      final handle = normalizeHandle(u.username);
      return handle.startsWith(termo) ||
          u.displayNameOrUsername.toLowerCase().contains(termo);
    }).take(8).toList();

    setState(() {
      _mentionQuery = query;
      _mentionSuggestions = candidatos;
      _mentionCursor = _mentionCursor.clamp(0, candidatos.isEmpty ? 0 : candidatos.length - 1);
    });
  }

  void _applyMention(AppState state, UserModel user) {
    final query = _mentionQuery;
    if (query == null) return;

    final handle = normalizeHandle(user.username);
    final texto = _textController.text;
    final novo = '${texto.substring(0, query.start)}@$handle ${texto.substring(query.end)}';
    final cursor = query.start + handle.length + 2; // '@' + handle + espaço

    _textController.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: cursor),
    );
    final channelId = state.activeChannelId;
    if (channelId.isNotEmpty) state.setDraft(channelId, novo);
    _closeMentions();
  }

  KeyEventResult _handleKey(AppState state, KeyEvent event) {
    if (!_isMentioning || event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() => _mentionCursor = (_mentionCursor + 1) % _mentionSuggestions.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(() => _mentionCursor =
            (_mentionCursor - 1 + _mentionSuggestions.length) % _mentionSuggestions.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _enterConsumido = true;
        // Solta a trava no fim deste ciclo: se o onSubmitted não vier, o
        // próximo Enter precisa voltar a enviar normalmente.
        WidgetsBinding.instance.addPostFrameCallback((_) => _enterConsumido = false);
        _applyMention(state, _mentionSuggestions[_mentionCursor]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        _applyMention(state, _mentionSuggestions[_mentionCursor]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _closeMentions();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleSend(AppState state) {
    // Com a lista aberta, Enter completa a marcação em vez de enviar.
    if (_isMentioning) {
      _applyMention(state, _mentionSuggestions[_mentionCursor]);
      return;
    }
    // O tratador de teclas já usou este Enter para confirmar uma marcação.
    if (_enterConsumido) {
      _enterConsumido = false;
      return;
    }

    final text = _textController.text.trim();
    final channelId = state.activeChannelId;
    if (text.isNotEmpty) {
      state.sendMessage(text);
      state.clearDraft(channelId);
      _textController.clear();
      _closeMentions();
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

    final knownHandles = state.knownMentionHandles();
    final selfHandle = normalizeHandle(state.currentUser.username);

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
              child: messages.isEmpty
                  ? _EmptyChannelHint(channelName: channel?.name ?? 'geral')
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        return _ChatMessageTile(
                          msg: msg,
                          knownHandles: knownHandles,
                          selfHandle: selfHandle,
                          isMentioningMe: msg.authorId != state.currentUser.id &&
                              !msg.isSystem &&
                              mentionsUser(msg.text, selfHandle),
                        );
                      },
                    ),
            ),

            // Lista de sugestões de marcação, logo acima do campo de mensagem.
            if (_isMentioning)
              _MentionSuggestions(
                suggestions: _mentionSuggestions,
                selectedIndex: _mentionCursor,
                onPick: (u) => _applyMention(state, u),
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
                      child: Focus(
                        onKeyEvent: (_, event) => _handleKey(state, event),
                        child: TextField(
                          controller: _textController,
                          focusNode: _inputFocus,
                          style: const TextStyle(color: HudTheme.textNormal, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Conversar em #${channel?.name ?? "geral"}  ·  use @ para marcar alguém',
                            hintStyle: const TextStyle(color: HudTheme.textMuted),
                            border: InputBorder.none,
                          ),
                          onChanged: (val) {
                            if (channel?.id != null) {
                              state.setDraft(channel!.id, val);
                            }
                            _refreshMentions(state);
                          },
                          onTap: () => _refreshMentions(state),
                          onSubmitted: (_) => _handleSend(state),
                        ),
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

class _EmptyChannelHint extends StatelessWidget {
  final String channelName;

  const _EmptyChannelHint({required this.channelName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.forum_outlined, color: HudTheme.textMuted, size: 40),
          const SizedBox(height: 12),
          Text(
            'Nada por aqui ainda em #$channelName',
            style: const TextStyle(color: HudTheme.textInteractive, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Se algum membro já conversou aqui, o histórico aparece assim que sincronizar.',
            style: TextStyle(color: HudTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MentionSuggestions extends StatelessWidget {
  final List<UserModel> suggestions;
  final int selectedIndex;
  final ValueChanged<UserModel> onPick;

  const _MentionSuggestions({
    required this.suggestions,
    required this.selectedIndex,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        color: HudTheme.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HudTheme.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'MARCAR MEMBRO  ·  ↑↓ navega, Tab ou Enter confirma',
              style: TextStyle(
                color: HudTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
          ),
          for (var i = 0; i < suggestions.length; i++)
            _MentionOption(
              user: suggestions[i],
              isSelected: i == selectedIndex,
              onTap: () => onPick(suggestions[i]),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _MentionOption extends StatelessWidget {
  final UserModel user;
  final bool isSelected;
  final VoidCallback onTap;

  const _MentionOption({required this.user, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final online = user.status != UserStatus.offline;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? HudTheme.bgActive : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: online ? HudTheme.green : HudTheme.statusOffline,
              child: Text(
                user.displayNameOrUsername.isNotEmpty
                    ? user.displayNameOrUsername[0].toUpperCase()
                    : '?',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                user.displayNameOrUsername,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HudTheme.textHeader,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '@${normalizeHandle(user.username)}',
              style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessageTile extends StatefulWidget {
  final ChatMessage msg;
  final Set<String> knownHandles;
  final String selfHandle;
  final bool isMentioningMe;

  const _ChatMessageTile({
    required this.msg,
    required this.knownHandles,
    required this.selfHandle,
    required this.isMentioningMe,
  });

  @override
  State<_ChatMessageTile> createState() => _ChatMessageTileState();
}

class _ChatMessageTileState extends State<_ChatMessageTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    final marcado = widget.isMentioningMe;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          // Mensagem que marca o leitor recebe fundo e faixa próprios, para ser
          // achada de relance ao rolar a conversa.
          color: marcado
              ? HudTheme.green.withValues(alpha: _isHovered ? 0.14 : 0.09)
              : (_isHovered ? HudTheme.bgHover.withValues(alpha: 0.5) : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
          border: marcado
              ? const Border(left: BorderSide(color: HudTheme.green, width: 2.5))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: msg.isSystem ? HudTheme.green : HudTheme.blurple,
              child: Text(
                (msg.authorDisplayName.isNotEmpty
                        ? msg.authorDisplayName[0]
                        : (msg.author.isNotEmpty ? msg.author[0] : '?'))
                    .toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        msg.authorDisplayName.isNotEmpty ? msg.authorDisplayName : msg.author,
                        style: const TextStyle(
                          color: HudTheme.textHeader,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (msg.authorUsername.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          msg.authorUsername.startsWith('@') ? msg.authorUsername : '@${msg.authorUsername}',
                          style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        msg.timestamp,
                        style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (msg.text.isNotEmpty)
                    MentionText(
                      text: msg.text,
                      knownHandles: widget.knownHandles,
                      selfHandle: widget.selfHandle,
                      baseStyle: const TextStyle(
                        color: HudTheme.textNormal,
                        fontSize: 14,
                        height: 1.3,
                      ),
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
