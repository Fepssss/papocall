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
import 'modals/gif_dialog.dart';
import 'retrato_usuario.dart';

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

  /// Chaves de medição: a moldura da área do chat e o balão da última mensagem.
  /// É da diferença entre o pé uma e o pé do outro que se precisa para saber
  /// quanto puxar a conversa para baixo.
  final GlobalKey _chaveDaLista = GlobalKey(debugLabel: 'área do chat');
  final GlobalKey _chaveDoFim = GlobalKey(debugLabel: 'última mensagem');

  /// Índice da primeira mensagem ainda não vista deste canal, resolvido quando
  /// a pessoa troca de canal. `null` quer dizer "abrir no fim".
  String? _canalAncorado;
  int? _indiceAncora;

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

  /// Apagar a própria mensagem não pede confirmação; apagar a alheia sim,
  /// porque ela já chegou aos outros e o pedido de apagamento vai voltar.
  Future<void> _confirmDeleteMessage(AppState state, ChatMessage msg) async {
    final ehMinha = msg.authorId == state.currentUser.id;
    if (!ehMinha) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: HudTheme.bgSidebar,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: HudTheme.divider),
          ),
          title: const Text('Apagar mensagem',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(
            'A mensagem de ${msg.authorDisplayName.isNotEmpty ? msg.authorDisplayName : msg.author} '
            'sai do histórico de todos os membros que estiverem conectados.',
            style: const TextStyle(color: HudTheme.textNormal, fontSize: 13),
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
    }
    final channelId = state.activeChannelId;
    if (channelId.isEmpty) return;
    await state.deleteMessage(state.activeServerId, channelId, msg.id);
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
      // O texto só sai do campo quando a mensagem saiu do aparelho: no respiro
      // entre envios o que a pessoa digitou continua ali, esperando.
      if (!state.sendMessage(text)) return;
      // Quem acabou de falar quer ver a própria fala, não a marca antiga.
      state.clearDraft(channelId);
      _textController.clear();
      _closeMentions();
      _scrollToBottom();
    }
  }

  Widget _tile(
    ChatMessage msg, {
    required int indice,
    required int total,
    required Set<String> knownHandles,
    required String selfHandle,
    required AppState state,
  }) {
    return _ChatMessageTile(
      key: indice == total - 1 ? _chaveDoFim : null,
      msg: msg,
      knownHandles: knownHandles,
      selfHandle: selfHandle,
      isMentioningMe: msg.authorId != state.currentUser.id &&
          !msg.isSystem &&
          mentionsUser(msg.text, selfHandle),
      canDelete: !msg.isSystem && state.canDeleteMessage(state.activeServerId, msg),
      onDelete: () => _confirmDeleteMessage(state, msg),
    );
  }

  /// Solta a marca de leitura e cola o fim da conversa no pé da área do chat.
  void _scrollToBottom() {
    _indiceAncora = null;
    _alinharComOFim();
  }

  /// Puxa a conversa para baixo até a última mensagem encostar no pé da área
  /// do chat.
  ///
  /// O sliver da marca de leitura está no topo da tela, então o offset zero é a
  /// própria marca: tudo o que ainda não foi visto aparece a partir dela. Quando
  /// o que falta ver é curto — e quando não falta nada — é o fim da conversa que
  /// deve ficar encostado embaixo, e para isso se desce a linha da marca pela
  /// sobra de tela que ficou embaixo dela. Nunca se sobe: a marca fica sempre no
  /// lugar ou mais abaixo, nunca rolada para fora.
  void _alinharComOFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final lista = _chaveDaLista.currentContext?.findRenderObject();
      final fim = _chaveDoFim.currentContext?.findRenderObject();
      if (lista is! RenderBox || fim is! RenderBox) return;
      if (!lista.hasSize || !fim.hasSize) return;

      final peDaLista = lista.localToGlobal(Offset.zero).dy + lista.size.height;
      final peDoFim = fim.localToGlobal(Offset.zero).dy + fim.size.height;
      final sobra = peDaLista - peDoFim;
      if (sobra <= 0.5) return;

      _scrollController.jumpTo(_scrollController.position.pixels - sobra);
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

    // A posição de abertura é resolvida uma vez por canal. Depois disso a
    // pessoa manda a lista para onde quiser e o chat não se mexe mais atrás.
    if (_canalAncorado != channel?.id) {
      _canalAncorado = channel?.id;
      final aberta = state.aberturaDoCanal;
      _indiceAncora =
          (aberta != null && aberta.canal == channel?.id) ? aberta.indice : null;
      _alinharComOFim();
    }
    final marca = (_indiceAncora ?? messages.length).clamp(0, messages.length);

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
                  Flexible(
                    child: Text(
                      channel?.name ?? 'geral',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HudTheme.textHeader,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
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
            //
            // A SelectionArea abraça a lista inteira, e não cada balão: assim dá
            // para arrastar o texto de uma mensagem para dentro de outra, como
            // se copia de um documento, sem que soltar o botão no meio de uma
            // frase deixe metade da seleção para trás.
            //
            // A conversa é dividida em dois slivers na marca de leitura, e o
            // segundo é declarado o centro do `CustomScrollView` — o que coloca
            // a marca no topo da tela no offset zero, com o histórico acessível
            // acima dela e o que ainda não foi visto abaixo, sem calcular pixel
            // nenhum. O bloco antigo cresce para cima a partir da marca, então
            // ele é alimentado de trás para frente: é assim que a leitura sai em
            // ordem cronológica. Sem nada novo o bloco da marca fica vazio e o
            // `_alinharComOFim` cola a última mensagem no pé da área.
            Expanded(
              child: messages.isEmpty
                  ? _EmptyChannelHint(channelName: channel?.name ?? 'geral')
                  : SelectionArea(
                      child: CustomScrollView(
                        key: _chaveDaLista,
                        controller: _scrollController,
                        center: const ValueKey('marca-de-leitura'),
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final i = marca - 1 - index;
                                  return _tile(
                                    messages[i],
                                    indice: i,
                                    total: messages.length,
                                    knownHandles: knownHandles,
                                    selfHandle: selfHandle,
                                    state: state,
                                  );
                                },
                                childCount: marca,
                              ),
                            ),
                          ),
                          SliverPadding(
                            key: const ValueKey('marca-de-leitura'),
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final i = marca + index;
                                  return _tile(
                                    messages[i],
                                    indice: i,
                                    total: messages.length,
                                    knownHandles: knownHandles,
                                    selfHandle: selfHandle,
                                    state: state,
                                  );
                                },
                                childCount: messages.length - marca,
                              ),
                            ),
                          ),
                        ],
                      ),
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
                      onPressed: state.podeEnviar
                          ? () async {
                              final url = await GifDialog.show(context);
                              if (url == null || !mounted) return;
                              if (state.sendMessage('', gifUrl: url)) _scrollToBottom();
                            }
                          : null,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.send,
                        color: state.podeEnviar ? HudTheme.blurple : HudTheme.textMuted,
                      ),
                      tooltip: state.podeEnviar
                          ? 'Enviar Mensagem'
                          : 'Um instante entre uma mensagem e outra',
                      onPressed: state.podeEnviar ? () => _handleSend(state) : null,
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
  final bool canDelete;
  final VoidCallback onDelete;

  const _ChatMessageTile({
    super.key,
    required this.msg,
    required this.knownHandles,
    required this.selfHandle,
    required this.isMentioningMe,
    this.canDelete = false,
    required this.onDelete,
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
            RetratoUsuario(
              avatar: msg.authorAvatar,
              iniciais: (msg.authorDisplayName.isNotEmpty
                      ? msg.authorDisplayName[0]
                      : (msg.author.isNotEmpty ? msg.author[0] : '?'))
                  .toUpperCase(),
              raio: 18,
              corQuandoSemFoto: msg.isSystem ? HudTheme.green : HudTheme.blurple,
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
                      // Nome e @id têm de caber na linha; a hora, não. Ela é a
                      // última coisa a ser cortada, então sai fora do Flexible.
                      Flexible(
                        child: Text(
                          msg.authorDisplayName.isNotEmpty ? msg.authorDisplayName : msg.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HudTheme.textHeader,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (msg.authorUsername.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            msg.authorUsername.startsWith('@')
                                ? msg.authorUsername
                                : '@${msg.authorUsername}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
                          ),
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
            // A lixeira só aparece com o cursor em cima, e só para quem pode:
            // o autor da mensagem ou quem tem 'apagar_mensagens'.
            if (widget.canDelete && _isHovered)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 6),
                child: GestureDetector(
                  onTap: widget.onDelete,
                  child: const Tooltip(
                    message: 'Apagar mensagem',
                    child: Icon(Icons.delete_outline_rounded, size: 16, color: HudTheme.red),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
