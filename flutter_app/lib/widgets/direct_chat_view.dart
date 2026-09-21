import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/direct_conversation.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../services/direct_crypto.dart';
import '../theme/hud_theme.dart';

/// Conversas privadas entre duas pessoas, sem servidor no meio.
///
/// Mostra a lista de conversas em andamento ou a conversa aberta, conforme o
/// que [AppState.activeDirectPeerId] aponta.
class DirectChatSection extends StatefulWidget {
  const DirectChatSection({super.key});

  @override
  State<DirectChatSection> createState() => _DirectChatSectionState();
}

class _DirectChatSectionState extends State<DirectChatSection> {
  final TextEditingController _campo = TextEditingController();
  String? _aviso;
  String? _avisoDe;

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final peer = state.activeDirectPeer;
    if (peer == null) return _buildLista(state);
    return _buildConversa(state, peer);
  }

  // --- LISTA DE CONVERSAS ---

  Widget _buildLista(AppState state) {
    final conversas = state.directConversations;

    if (conversas.isEmpty) {
      return _CartaoBase(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
          child: Column(
            children: [
              const Icon(Icons.lock_outline_rounded, color: HudTheme.textMuted, size: 34),
              const SizedBox(height: 12),
              const Text(
                'Nenhuma conversa privada ainda.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Abra a aba Disponível e toque em Mensagem no amigo com quem quiser '
                'conversar. Só vocês dois leem o que for escrito ali.',
                textAlign: TextAlign.center,
                style: TextStyle(color: HudTheme.textMuted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    return _CartaoBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < conversas.length; i++) ...[
            if (i > 0) const Divider(color: HudTheme.divider, height: 1),
            _LinhaConversa(conversa: conversas[i]),
          ],
        ],
      ),
    );
  }

  // --- CONVERSA ABERTA ---

  Widget _buildConversa(AppState state, UserModel peer) {
    final mensagens = state.directMessages(peer.id);
    final bloqueio = state.bloqueioDeEnvioDireto(peer.id);
    // O respiro de envio não aparece como cronômetro: o botão fica mudo por um
    // instante e o texto continua no campo.
    final podeSair = bloqueio == null && state.podeEnviar;
    final impressao = state.impressaoDoPar(peer.id);

    if (_avisoDe != peer.id) {
      _aviso = null;
      _avisoDe = peer.id;
    }

    return _CartaoBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cabecalho(
            peer: peer,
            aoVoltar: state.closeDirectChat,
            aoVerChave: () => _mostrarChave(state, peer),
          ),
          const Divider(color: HudTheme.divider, height: 1),

          SizedBox(
            height: 320,
            child: mensagens.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhuma mensagem ainda. Diga algo.',
                      style: TextStyle(color: HudTheme.textMuted, fontSize: 13),
                    ),
                  )
                : SelectionArea(
                    child: ListView.builder(
                      // De cabeça para baixo: a conversa abre já no fim, sem
                      // precisar de controller de rolagem nem de bombear o
                      // deslocamento a cada mensagem que chega.
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      itemCount: mensagens.length,
                      itemBuilder: (context, index) => _Bolha(
                          mensagem: mensagens[mensagens.length - 1 - index],
                          minha: _eMinha(state, mensagens[mensagens.length - 1 - index])),
                    ),
                  ),
          ),

          if (bloqueio != null || _aviso != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _aviso ?? bloqueio!,
                style: const TextStyle(color: HudTheme.yellow, fontSize: 12, height: 1.4),
              ),
            ),

          if (impressao != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                'Cifrada ponta a ponta. Chave de ${peer.displayNameOrUsername}: $impressao',
                style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: HudTheme.bgInput,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: HudTheme.divider),
                    ),
                    child: TextField(
                      controller: _campo,
                      maxLines: 4,
                      minLines: 1,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      enabled: bloqueio == null,
                      onSubmitted: (_) => _enviar(state, peer.id),
                      decoration: InputDecoration(
                        hintText: bloqueio == null
                            ? 'Mensagem para ${peer.displayNameOrUsername}…'
                            : 'Indisponível agora',
                        hintStyle: const TextStyle(color: HudTheme.textMuted, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: podeSair ? HudTheme.green : HudTheme.bgHover,
                    foregroundColor: Colors.white,
                  ),
                  tooltip: podeSair ? 'Enviar' : 'Um instante entre uma mensagem e outra',
                  onPressed: podeSair ? () => _enviar(state, peer.id) : null,
                  icon: const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _eMinha(AppState state, ChatMessage m) =>
      !m.isSystem && m.authorId == state.currentUser.id;

  Future<void> _enviar(AppState state, String peerId) async {
    final texto = _campo.text;
    if (texto.trim().isEmpty) return;
    final erro = await state.sendDirectMessage(peerId, texto);
    if (!mounted) return;
    // O texto só sai do campo quando a mensagem saiu do aparelho: se a malha
    // estiver caída, o que a pessoa digitou não desaparece.
    if (erro == null) _campo.clear();
    setState(() {
      _aviso = erro;
      _avisoDe = peerId;
    });
  }

  Future<void> _mostrarChave(AppState state, UserModel peer) async {
    final doPar = state.chavePublicaDoPar(peer.id);
    String minha = 'indisponível';
    try {
      minha = DirectCrypto.impressao(await DirectCrypto.chavePublicaAtual());
    } catch (_) {}

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: HudTheme.bgCard,
        title: Text(
          'Chave desta conversa',
          style: TextStyle(color: HudTheme.textHeader, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: min(380.0, MediaQuery.sizeOf(context).width - 96),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Compare as duas impressões com o seu amigo por outro canal '
                '(uma ligação, um SMS, o que vocês já confiam). Se baterem, '
                'ninguém está no meio da conversa. Se forem diferentes, a chave '
                'dele mudou e vale recomeçar a conversa.',
                style: TextStyle(color: HudTheme.textNormal, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 14),
              _LinhaChave(apelido: 'A sua', valor: minha),
              const SizedBox(height: 6),
              _LinhaChave(apelido: 'A dele', valor: doPar == null ? 'desconhecida' : DirectCrypto.impressao(doPar)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar', style: TextStyle(color: HudTheme.green)),
          ),
        ],
      ),
    );
  }
}

class _LinhaChave extends StatelessWidget {
  const _LinhaChave({required this.apelido, required this.valor});

  final String apelido;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            apelido,
            style: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
          ),
        ),
        Text(
          valor,
          style: const TextStyle(
            color: HudTheme.textHeader,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _LinhaConversa extends StatelessWidget {
  const _LinhaConversa({required this.conversa});

  final ConversaDireta conversa;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final peer = conversa.peer;
    final preview = conversa.ultima.isSystem
        ? conversa.ultima.text
        : '${conversa.ultima.authorId == state.currentUser.id ? 'Você: ' : ''}${conversa.ultima.text}';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      hoverColor: HudTheme.bgHover.withValues(alpha: 0.5),
      onTap: () => state.openDirectChat(peer.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _Avatar(peer: peer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peer.displayNameOrUsername,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (conversa.naoLidas > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: HudTheme.green,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${conversa.naoLidas}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.peer,
    required this.aoVoltar,
    required this.aoVerChave,
  });

  final UserModel peer;
  final VoidCallback aoVoltar;
  final VoidCallback aoVerChave;

  @override
  Widget build(BuildContext context) {
    final online = peer.status != UserStatus.offline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Ver todas as conversas',
            splashRadius: 18,
            onPressed: aoVoltar,
            icon: const Icon(Icons.arrow_back_rounded, size: 18, color: HudTheme.textNormal),
          ),
          _Avatar(peer: peer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer.displayNameOrUsername,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  online ? peer.handle : '${peer.handle} · offline',
                  style: TextStyle(
                    color: online ? HudTheme.green : HudTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Conferir a chave da conversa',
            splashRadius: 18,
            onPressed: aoVerChave,
            icon: const Icon(Icons.verified_user_outlined, size: 18, color: HudTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.peer});

  final UserModel peer;

  @override
  Widget build(BuildContext context) {
    final offline = peer.status == UserStatus.offline;
    return Stack(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: offline ? HudTheme.bgSidebar : HudTheme.bgHover,
          child: Text(
            peer.initials,
            style: TextStyle(
              color: offline ? HudTheme.textMuted : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: switch (peer.status) {
                UserStatus.online => HudTheme.statusOnline,
                UserStatus.idle => HudTheme.statusIdle,
                UserStatus.dnd => HudTheme.statusDnd,
                UserStatus.offline => HudTheme.statusOffline,
              },
              shape: BoxShape.circle,
              border: Border.all(color: HudTheme.bgCard, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bolha extends StatelessWidget {
  const _Bolha({required this.mensagem, required this.minha});

  final ChatMessage mensagem;
  final bool minha;

  @override
  Widget build(BuildContext context) {
    if (mensagem.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            mensagem.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HudTheme.yellow,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: minha ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: minha ? HudTheme.green.withValues(alpha: 0.16) : HudTheme.bgHover,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: minha ? HudTheme.green.withValues(alpha: 0.35) : HudTheme.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SelectableText(
              mensagem.text,
              style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 2),
            Text(
              mensagem.timestamp,
              style: const TextStyle(color: HudTheme.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoBase extends StatelessWidget {
  const _CartaoBase({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HudTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HudTheme.divider),
      ),
      child: child,
    );
  }
}
