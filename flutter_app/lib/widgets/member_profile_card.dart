import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/role.dart';
import '../models/server.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'member_context_menu.dart';
import 'modals/add_friend_dialog.dart';
import 'retrato_usuario.dart';

/// O mini perfil de alguém do servidor.
///
/// Abre no clique sobre a pessoa na lista de membros e mostra apenas o que
/// existe de verdade hoje: quem ela é, o cargo que tem neste servidor, se está
/// em algum canal de voz, quando foi vista por último e em quantos servidores
/// dela esta máquina também participa. Amigos em comum, biografia e "cargo em
/// outro servidor" não existem no modelo, então não aparecem aqui — inventar
/// num cartão do tamanho deste é como o aplicativo ganha a confiança de volta.
class MemberProfileCard {
  static const double _largura = 300;

  static Future<void> show(
    BuildContext context,
    Server server,
    UserModel member,
    Offset globalPosition,
  ) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Perfil de ${member.displayNameOrUsername}',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, _) => _MemberProfileCard(
        parentContext: context,
        server: server,
        member: member,
        anchor: globalPosition,
      ),
    );
  }
}

class _MemberProfileCard extends StatelessWidget {
  const _MemberProfileCard({
    required this.parentContext,
    required this.server,
    required this.member,
    required this.anchor,
  });

  final BuildContext parentContext;
  final Server server;
  final UserModel member;
  final Offset anchor;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isSelf = member.id == state.currentUser.id;
    final ehAmigo = state.friends.any((f) => f.id == member.id);
    final tela = MediaQuery.of(context).size;

    final origem = _origem(tela);

    return Stack(
      children: [
        Positioned(
          left: origem.dx,
          top: origem.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MemberProfileCard._largura,
              decoration: BoxDecoration(
                color: HudTheme.bgSidebar,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HudTheme.divider),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Cabecalho(server: server, member: member, isSelf: isSelf),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LinhaDeStatus(state: state, server: server, member: member),
                        if (!isSelf) ...[
                          const SizedBox(height: 12),
                          _Secao(rotulo: 'AÇÕES'),
                          const SizedBox(height: 6),
                          _Botoes(
                            context: context,
                            state: state,
                            member: member,
                            server: server,
                            anchor: anchor,
                            ehAmigo: ehAmigo,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// O cartão nasce ao lado do clique e, se a janela não tiver espaço para
  /// ele daquele lado, vira para o outro — nunca sai da tela.
  Offset _origem(Size tela) {
    const alturaEstimada = 320.0;
    var dx = anchor.dx + 16;
    var dy = anchor.dy - 24;
    if (dx + MemberProfileCard._largura > tela.width - 12) {
      dx = anchor.dx - MemberProfileCard._largura - 16;
    }
    if (dx < 12) dx = 12;
    if (dy + alturaEstimada > tela.height - 12) {
      dy = tela.height - alturaEstimada - 12;
    }
    if (dy < 12) dy = 12;
    return Offset(dx, dy);
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.server, required this.member, required this.isSelf});

  final Server server;
  final UserModel member;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final cor = Color(int.parse('FF${server.colorHex}', radix: 16));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 56, color: cor.withValues(alpha: 0.75)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: const Offset(0, -30),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: HudTheme.bgSidebar,
                            shape: BoxShape.circle,
                          ),
                          child: RetratoUsuario(
                            avatar: member.avatar,
                            iniciais: member.initials,
                            raio: 28,
                            corQuandoSemFoto: HudTheme.bgHover,
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _corDeStatus(member.status),
                              shape: BoxShape.circle,
                              border: Border.all(color: HudTheme.bgSidebar, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Text(
                member.displayNameOrUsername,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HudTheme.textHeader,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                member.handle,
                style: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Color _corDeStatus(UserStatus status) => switch (status) {
        UserStatus.online => HudTheme.green,
        UserStatus.idle => HudTheme.yellow,
        UserStatus.dnd => HudTheme.red,
        UserStatus.offline => HudTheme.textMuted,
      };
}

/// O que se sabe sobre a pessoa neste servidor, tudo vindo do modelo real.
class _LinhaDeStatus extends StatelessWidget {
  const _LinhaDeStatus({required this.state, required this.server, required this.member});

  final AppState state;
  final Server server;
  final UserModel member;

  @override
  Widget build(BuildContext context) {
    final cargo = server.roleOf(member.id);
    final dono = server.isOwnedBy(member.id);
    final emVoz = member.currentVoiceChannelId != null &&
        member.currentVoiceServerId == server.id;
    final canal = emVoz ? _canalDeVoz() : null;
    final emComum = state.servers
        .where((s) => s.id != server.id && s.memberIds.contains(member.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dono || cargo != null)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (dono)
                const _Chip(rotulo: 'Dono', cor: HudTheme.yellow, icone: Icons.workspace_premium),
              if (cargo != null)
                _Chip(rotulo: cargo.name, cor: cargo.color, icone: Icons.shield_outlined),
            ],
          ),
        if (emVoz) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                member.isMuted ? Icons.mic_off : Icons.graphic_eq,
                size: 14,
                color: member.isMuted ? HudTheme.red : HudTheme.green,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Em ${canal ?? 'um canal de voz'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: HudTheme.textNormal, fontSize: 12),
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 10),
          Text(
            member.status == UserStatus.offline
                ? 'Visto por último em ${_data(member.lastSeen)}'
                : 'Online agora',
            style: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
          ),
        ],
        if (emComum.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Servidores em comum: ${emComum.length}',
            style: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in emComum.take(4))
                Text(
                  s.name,
                  style: const TextStyle(color: HudTheme.textNormal, fontSize: 11),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String? _canalDeVoz() {
    for (final c in server.channels) {
      if (c.id == member.currentVoiceChannelId) return c.name;
    }
    return null;
  }

  static String _data(int milissegundos) {
    if (milissegundos <= 0) return 'data desconhecida';
    final d = DateTime.fromMillisecondsSinceEpoch(milissegundos);
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)} às ${dois(d.hour)}:${dois(d.minute)}';
  }
}

class _Botoes extends StatelessWidget {
  const _Botoes({
    required this.context,
    required this.state,
    required this.member,
    required this.server,
    required this.anchor,
    required this.ehAmigo,
  });

  final BuildContext context;
  final AppState state;
  final UserModel member;
  final Server server;
  final Offset anchor;
  final bool ehAmigo;

  @override
  Widget build(BuildContext context) {
    final podeGerir = state.can(server.id, Permissions.manageRoles) ||
        state.can(server.id, Permissions.kickMembers);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ehAmigo)
          _Botao(
            rotulo: 'Mensagem direta',
            icone: Icons.forum_outlined,
            cor: HudTheme.green,
            onPressed: () {
              Navigator.of(context).pop();
              state.openDirectChat(member.id);
            },
          )
        else
          _Botao(
            rotulo: 'Adicionar amigo',
            icone: Icons.person_add_alt_1,
            cor: HudTheme.green,
            onPressed: () {
              Navigator.of(context).pop();
              AddFriendDialog.show(context, handleInicial: member.username);
            },
          ),
        if (ehAmigo)
          _Botao(
            rotulo: 'Remover amigo',
            icone: Icons.person_remove_alt_1_outlined,
            cor: HudTheme.red,
            onPressed: () async {
              final nav = Navigator.of(context);
              final confirmou = await showDialog<bool>(
                context: nav.context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: HudTheme.bgSidebar,
                  title: const Text('Remover amigo',
                      style: TextStyle(color: HudTheme.textHeader, fontSize: 16)),
                  content: Text(
                    'Vocês deixam de se ver na lista de amigos. As mensagens trocadas continuam nos dois aparelhos.',
                    style: TextStyle(color: HudTheme.textNormal, fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Deixar como está',
                          style: TextStyle(color: HudTheme.textMuted)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Remover', style: TextStyle(color: HudTheme.red)),
                    ),
                  ],
                ),
              );
              if (confirmou != true) return;
              nav.pop();
              await state.removeFriend(member.id);
            },
          ),
        if (podeGerir)
          _Botao(
            rotulo: 'Gerenciar membro',
            icone: Icons.tune_rounded,
            cor: HudTheme.accent,
            onPressed: () {
              final nav = Navigator.of(context);
              // O menu de gestão já existe e já sabe o que a permissão permite;
              // o cartão não vai duplicar essa regra.
              nav.pop();
              MemberContextMenu.show(context, server, member, anchor);
            },
          ),
      ],
    );
  }
}

class _Botao extends StatelessWidget {
  const _Botao({
    required this.rotulo,
    required this.icone,
    required this.cor,
    required this.onPressed,
  });

  final String rotulo;
  final IconData icone;
  final Color cor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: cor,
            backgroundColor: cor.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          icon: Icon(icone, size: 16),
          label: Text(rotulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.rotulo, required this.cor, required this.icone});

  final String rotulo;
  final Color cor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 12, color: cor),
          const SizedBox(width: 5),
          Text(rotulo, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.rotulo});

  final String rotulo;

  @override
  Widget build(BuildContext context) {
    return Text(
      rotulo,
      style: const TextStyle(
        color: HudTheme.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.6,
      ),
    );
  }
}
