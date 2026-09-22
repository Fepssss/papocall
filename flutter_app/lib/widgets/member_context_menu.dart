import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/role.dart';
import '../models/server.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'member_profile_card.dart';
import 'modals/add_friend_dialog.dart';

/// Menu do botão direito sobre um membro da lista lateral.
///
/// Só mostra o que o usuário atual pode fazer de verdade com aquela pessoa:
/// atribuir cargo exige 'gerenciar_cargos' e expulsar exige
/// 'expulsar_membros'. Sem nenhuma das duas o menu não abre — um menu vazio
/// seria só mais uma janela a fechar.
class MemberContextMenu {
  static const double _menuWidth = 236;

  static Future<void> show(
    BuildContext context,
    Server server,
    UserModel member,
    Offset globalPosition,
  ) {
    final state = context.read<AppState>();
    final isSelf = member.id == state.currentUser.id;
    final isOwner = server.isOwnedBy(member.id);
    final canAssign = !isSelf && !isOwner && state.can(server.id, Permissions.manageRoles);
    final canKick = !isSelf && !isOwner && state.can(server.id, Permissions.kickMembers);
    if (!canAssign && !canKick) return Future.value();

    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Opções do membro',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      // O contexto da lista lateral sobrevive ao fechamento do menu; o contexto
      // de dentro da rota do menu não. Ele é o único com que se pode abrir o
      // diálogo de confirmação depois que o menu some.
      pageBuilder: (ctx, _, _) => _MemberContextMenu(
        parentContext: context,
        server: server,
        member: member,
        anchor: globalPosition,
        canAssign: canAssign,
        canKick: canKick,
      ),
    );
  }
}

class _MemberContextMenu extends StatelessWidget {
  const _MemberContextMenu({
    required this.parentContext,
    required this.server,
    required this.member,
    required this.anchor,
    required this.canAssign,
    required this.canKick,
  });

  final BuildContext parentContext;
  final Server server;
  final UserModel member;
  final Offset anchor;
  final bool canAssign;
  final bool canKick;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final screen = MediaQuery.of(context).size;
    final assignedId = server.memberRoles[member.id];

    final rows = <Widget>[];
    if (canAssign) {
      rows.add(const _MemberMenuLabel('CARGO DO MEMBRO'));
      rows.add(
        _MemberMenuItem(
          label: 'Nenhum (Membro)',
          color: HudTheme.textNormal,
          selected: assignedId == null,
          onTap: () => _pick(context, state, null),
        ),
      );
      for (final role in server.roles) {
        rows.add(
          _MemberMenuItem(
            label: role.name,
            color: role.color,
            selected: assignedId == role.id,
            // Só entrega o cargo quem já tem todos os poderes dele.
            enabled: state.canEditRole(server.id, role.id),
            onTap: () => _pick(context, state, role.id),
          ),
        );
      }
    }
    if (canKick) {
      if (rows.isNotEmpty) rows.add(const _MemberMenuDivider());
      rows.add(
        _MemberMenuItem(
          label: 'Expulsar do servidor',
          color: HudTheme.red,
          icon: Icons.person_off_rounded,
          onTap: () => _confirmKick(context, state),
        ),
      );
    }

    final estimatedHeight =
        (30 + rows.length * 32 + rows.whereType<_MemberMenuDivider>().length * 9 + 16).toDouble();
    final origin = _origin(screen, estimatedHeight);
    final disponivel = screen.height - origin.dy - 26;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: origin.dx,
          top: origin.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MemberContextMenu._menuWidth,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: HudTheme.bgSidebar,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: HudTheme.divider),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ConstrainedBox(
                // Mesma regra do menu da chamada: o que não cabe na janela tem de
                // rolar, não pode ficar fora do alcance do clique.
                constraints: BoxConstraints(
                    maxHeight: disponivel < 120 ? 120 : disponivel),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                        child: Text(
                          member.displayNameOrUsername,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HudTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      ...rows,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Offset _origin(Size screen, double height) {
    const margin = 8.0;
    var dx = anchor.dx;
    var dy = anchor.dy;
    if (dx + MemberContextMenu._menuWidth + margin > screen.width) {
      dx = screen.width - MemberContextMenu._menuWidth - margin;
    }
    if (dy + height + margin > screen.height) {
      dy = screen.height - height - margin;
    }
    return Offset(dx < margin ? margin : dx, dy < margin ? margin : dy);
  }

  Future<void> _pick(BuildContext context, AppState state, String? roleId) async {
    Navigator.of(context).pop();
    await state.assignRole(server.id, member.id, roleId);
  }

  Future<void> _confirmKick(BuildContext context, AppState state) async {
    Navigator.of(context).pop();
    final confirm = await showDialog<bool>(
      context: parentContext,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: HudTheme.bgSidebar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: HudTheme.divider),
        ),
        title: const Text('Expulsar do servidor',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '${member.displayNameOrUsername} perde o acesso a "${server.name}" e tem o '
          'servidor apagado da própria máquina. O histórico dele continua no computador '
          'dele; o compartimento que ele mantém no tópico do servidor é limpo.',
          style: const TextStyle(color: HudTheme.textNormal, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: HudTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: HudTheme.red),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Expulsar',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await state.kickMember(server.id, member.id);
    }
  }
}

class _MemberMenuLabel extends StatelessWidget {
  const _MemberMenuLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: HudTheme.textMuted,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _MemberMenuDivider extends StatelessWidget {
  const _MemberMenuDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 9,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      child: const Divider(color: HudTheme.divider, height: 9, thickness: 1),
    );
  }
}

class _MemberMenuItem extends StatefulWidget {
  const _MemberMenuItem({
    required this.label,
    required this.color,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
    this.icon,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;
  final IconData? icon;

  @override
  State<_MemberMenuItem> createState() => _MemberMenuItemState();
}

class _MemberMenuItemState extends State<_MemberMenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.enabled ? widget.color : HudTheme.textMuted;

    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Container(
          height: 32,
          color: _hover && widget.enabled ? HudTheme.bgActive : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 15, color: fg),
                const SizedBox(width: 10),
              ] else ...[
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: widget.enabled ? widget.color : HudTheme.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12.5,
                    fontWeight: widget.selected ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),
              if (widget.selected)
                const Icon(Icons.check_rounded, size: 15, color: HudTheme.green),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha de caixa de marcar do menu: rótulo à esquerda, quadrado à direita.
///
/// É outra linha e não o `_MemberMenuItem` com `selected`, porque ali o visto
/// fica do lado do texto e diz "esta é a opção escolhida entre várias". A caixa
/// diz "isto está ligado agora", que é o que silenciar e ocultar vídeo são.
class _MemberMenuCheck extends StatefulWidget {
  const _MemberMenuCheck({
    required this.label,
    required this.marcado,
    required this.onTap,
  });

  final String label;
  final bool marcado;
  final VoidCallback onTap;

  @override
  State<_MemberMenuCheck> createState() => _MemberMenuCheckState();
}

class _MemberMenuCheckState extends State<_MemberMenuCheck> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 32,
          color: _hover ? HudTheme.bgActive : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const SizedBox(width: 19),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HudTheme.textNormal,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: widget.marcado ? HudTheme.green : HudTheme.divider,
                    width: 1.4,
                  ),
                  color: widget.marcado ? HudTheme.green.withValues(alpha: 0.18) : null,
                ),
                child: widget.marcado
                    ? const Icon(Icons.check_rounded, size: 12, color: HudTheme.green)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Volume de uma só pessoa, no menu do botão direito.
///
/// Arrastar aplica no áudio na hora e não escreve no disco; soltar grava. É o
/// mesmo acordo do controle de volume da live, pela mesma razão: um slider
/// salvo a cada quadro pintado é I/O de disco no meio de uma conversa.
class _MemberMenuVolume extends StatelessWidget {
  const _MemberMenuVolume({
    required this.username,
    required this.state,
  });

  final String username;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final valor = state.volumeDoPar(username);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 19),
              Expanded(
                child: Text(
                  'Volume de $username',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HudTheme.textNormal,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(valor * 100).round()}%',
                style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: HudTheme.green,
              inactiveTrackColor: HudTheme.bgHover,
              thumbColor: HudTheme.green,
              overlayColor: HudTheme.green.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: valor,
              onChanged: (v) => state.ajustarVolumeDoPar(username, v),
              onChangeEnd: (v) => state.definirVolumeDoPar(username, v),
            ),
          ),
        ],
      ),
    );
  }
}

/// Menu do botão direito sobre um participante da chamada de voz.
///
/// A lista lateral de membros já tinha menu, mas ele só abria para quem pode
/// gerenciar alguém — para o resto das pessoas o botão direito na call não fazia
/// nada. Aqui a ação principal é humana: ver quem é a pessoa, chamar no
/// particular, e ajustar o que ela faz no meu ouvido e na minha tela.
///
/// Só entra linha que o aplicativo faz de verdade. Nota de amigo, apelido
/// pessoal, bloquear, ignorar, "convocar para entrar" e código de verificação
/// não existem no PapoCall — um item que não faz nada dentro de um menu de
/// contexto é a mesma coisa que um botão morto na tela. Desfazer amizade e
/// cargos moram no Perfil e em "Gerenciar membro", e este menu abre os dois em
/// vez de copiar as regras deles.
class VoiceMemberMenu {
  static const double _menuWidth = 236;

  /// [naChamada] é o que decide se as linhas de áudio e vídeo daquela pessoa
  /// aparecem: volume, silêncio e vídeo ocultado só fazem sentido para quem está
  /// na sala comigo agora. Na lista de membros do servidor o menu abre sem
  /// elas, e não com três linhas mortas. Sobre a própria pessoa, na chamada, o
  /// que aparece são os meus aparelhos — silenciar o meu microfone e ensurdecer
  /// o que eu escuto — porque o volume de mim mesmo não tem o que controlar.
  static Future<void> show(
    BuildContext context,
    Server server,
    UserModel member,
    Offset globalPosition, {
    bool naChamada = false,
  }) {
    final state = context.read<AppState>();
    // Sobre a própria pessoa não há mensagem nem gestão: sobra o perfil, e um
    // menu de uma linha só ainda é um menu — o clique direito não pode ser
    // silêncio onde a pessoa esperava uma resposta.
    final ehAuto = member.id == state.currentUser.id;

    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Opções de ${member.displayNameOrUsername}',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, _) => _VoiceMemberMenu(
        parentContext: context,
        server: server,
        member: member,
        anchor: globalPosition,
        naChamada: naChamada,
        ehAuto: ehAuto,
      ),
    );
  }
}

class _VoiceMemberMenu extends StatelessWidget {
  const _VoiceMemberMenu({
    required this.parentContext,
    required this.server,
    required this.member,
    required this.anchor,
    required this.naChamada,
    required this.ehAuto,
  });

  final BuildContext parentContext;
  final Server server;
  final UserModel member;
  final Offset anchor;
  final bool naChamada;
  final bool ehAuto;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ehAmigo = state.friends.any((f) => f.id == member.id);
    final podeGerir = !ehAuto &&
        !server.isOwnedBy(member.id) &&
        (state.can(server.id, Permissions.manageRoles) ||
            state.can(server.id, Permissions.kickMembers));

    final nome = member.username;
    // A linha de vídeo só existe quando há o que ocultar — ou quando já está
    // oculto, para a pessoa poder desfazer sem ter que esperar a câmera do
    // amigo ligar de novo.
    final linhaDeVideo = member.isCameraOn || state.videoOcultoDe(nome);

    final rows = <Widget>[
      _MemberMenuItem(
        label: 'Perfil',
        color: HudTheme.textNormal,
        icon: Icons.badge_outlined,
        onTap: () {
          Navigator.of(context).pop();
          MemberProfileCard.show(parentContext, server, member, anchor);
        },
      ),
      if (!ehAuto && ehAmigo)
        _MemberMenuItem(
          label: 'Mensagem direta',
          color: HudTheme.green,
          icon: Icons.forum_outlined,
          onTap: () {
            Navigator.of(context).pop();
            state.openDirectChat(member.id);
          },
        )
      else if (!ehAuto)
        _MemberMenuItem(
          label: 'Adicionar amigo',
          color: HudTheme.green,
          icon: Icons.person_add_alt_1,
          onTap: () {
            Navigator.of(context).pop();
            AddFriendDialog.show(parentContext, handleInicial: member.username);
          },
        ),
      // Sobre a própria pessoa, na chamada, o que se ajusta são os meus próprios
      // aparelhos: o microfone que os outros ouvem e o que eu escuto.
      if (ehAuto && naChamada) ...[
        const _MemberMenuDivider(),
        _MemberMenuCheck(
          label: 'Silenciar',
          marcado: state.currentUser.isMuted,
          onTap: state.toggleMute,
        ),
        _MemberMenuCheck(
          label: 'Ensurdecer',
          marcado: state.currentUser.isDeafened,
          onTap: state.toggleDeafen,
        ),
      ],
      if (naChamada && !ehAuto) ...[
        const _MemberMenuDivider(),
        // As três linhas abaixo ficam com o menu aberto: são estados que se
        // ajustam, não ações que se escolhem uma vez.
        _MemberMenuVolume(username: nome, state: state),
        _MemberMenuCheck(
          label: 'Silenciar',
          marcado: state.parSilenciado(nome),
          onTap: () {
            state.definirParSilenciado(nome, !state.parSilenciado(nome));
          },
        ),
        if (linhaDeVideo)
          _MemberMenuCheck(
            label: 'Desativar vídeo',
            marcado: state.videoOcultoDe(nome),
            onTap: () {
              state.definirVideoOculto(nome, !state.videoOcultoDe(nome));
            },
          ),
      ],
      if (podeGerir) ...[
        const _MemberMenuDivider(),
        _MemberMenuItem(
          label: 'Gerenciar membro',
          color: HudTheme.accent,
          icon: Icons.tune_rounded,
          onTap: () {
            Navigator.of(context).pop();
            // O menu de gestão já sabe o que a permissão permite; este não
            // duplica essa regra.
            MemberContextMenu.show(parentContext, server, member, anchor);
          },
        ),
      ],
    ];

    final altura = 46 +
        rows.fold<double>(
          0,
          (total, linha) => total +
              (linha is _MemberMenuDivider
                  ? 9
                  : linha is _MemberMenuVolume
                      ? 58
                      : 32),
        );
    final tela = MediaQuery.of(context).size;
    var dx = anchor.dx;
    var dy = anchor.dy;
    if (dx + VoiceMemberMenu._menuWidth + 8 > tela.width) {
      dx = tela.width - VoiceMemberMenu._menuWidth - 8;
    }
    if (dy + altura + 8 > tela.height) dy = tela.height - altura - 8;
    final esquerda = dx < 8 ? 8.0 : dx;
    final topo = dy < 8 ? 8.0 : dy;
    // O tanto que cabe abaixo do topo, e não o tamanho da tela: a estimativa
    // acima pode errar para baixo, e um menu que passa do pé da janela não tem
    // como ser fechado pela última linha. Descontam-se os 8 de margem e os 18
    // de forro da própria caixa.
    final calculada = tela.height - topo - 26;
    final alturaDisponivel = calculada < 120 ? 120.0 : calculada;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: esquerda,
          top: topo,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: VoiceMemberMenu._menuWidth,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: HudTheme.bgSidebar,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: HudTheme.divider),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ConstrainedBox(
                // Com o volume e as caixas o menu cresceu: sem rolagem, a última
                // linha ficava fora da tela numa janela pequena, e o que não
                // cabe na tela não existe para quem usa.
                constraints: BoxConstraints(maxHeight: alturaDisponivel),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                        child: Text(
                          member.displayNameOrUsername,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HudTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      ...rows,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
