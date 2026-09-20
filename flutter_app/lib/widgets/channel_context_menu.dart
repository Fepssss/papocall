import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../theme/hud_theme.dart';

/// Menu do botão direito sobre um canal da barra lateral.
///
/// É aqui que vive o "apagar" de um canal de voz: a lixeira no hover ficou só
/// nos canais de texto, porque numa sala de voz o clique já serve para entrar e
/// o ícone vermelho aparecia no meio do caminho de quem só queria conversar.
class ChannelContextMenu {
  static const double _menuWidth = 216;

  static Future<void> show(
    BuildContext context, {
    required Channel channel,
    required Offset globalPosition,
    required bool canDelete,
    required VoidCallback onDelete,
  }) {
    if (!canDelete) return Future.value();

    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Opções do canal',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, _) => _ChannelContextMenu(
        channel: channel,
        anchor: globalPosition,
        onDelete: onDelete,
      ),
    );
  }
}

class _ChannelContextMenu extends StatelessWidget {
  const _ChannelContextMenu({
    required this.channel,
    required this.anchor,
    required this.onDelete,
  });

  final Channel channel;
  final Offset anchor;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    const estimatedHeight = 30.0 + 32.0 + 16.0;
    final origin = _origin(screen, estimatedHeight);

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: origin.dx,
          top: origin.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: ChannelContextMenu._menuWidth,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                    child: Text(
                      channel.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HudTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  _ChannelMenuItem(
                    label: 'Apagar canal',
                    icon: Icons.delete_outline_rounded,
                    color: HudTheme.red,
                    onTap: () {
                      Navigator.of(context).pop();
                      onDelete();
                    },
                  ),
                ],
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
    if (dx + ChannelContextMenu._menuWidth + margin > screen.width) {
      dx = screen.width - ChannelContextMenu._menuWidth - margin;
    }
    if (dy + height + margin > screen.height) {
      dy = screen.height - height - margin;
    }
    return Offset(dx < margin ? margin : dx, dy < margin ? margin : dy);
  }
}

class _ChannelMenuItem extends StatefulWidget {
  const _ChannelMenuItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ChannelMenuItem> createState() => _ChannelMenuItemState();
}

class _ChannelMenuItemState extends State<_ChannelMenuItem> {
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
              Icon(widget.icon, size: 15, color: widget.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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
