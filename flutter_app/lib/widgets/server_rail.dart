import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'modals/create_server_dialog.dart';
import 'server_context_menu.dart';

class ServerRail extends StatelessWidget {
  const ServerRail({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      width: 72,
      color: HudTheme.bgServerRail,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Botão no topo esquerdo da aba de servidores: Início & Amigos (em tela cheia)
          _buildServerIcon(
            isActive: state.isHomePageActive,
            title: 'Início & Amigos',
            initials: 'H',
            iconData: Icons.people_alt_rounded,
            onTap: state.toggleHomePage,
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: HudTheme.divider, height: 2),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: state.servers.length,
              itemBuilder: (context, index) {
                final srv = state.servers[index];
                final isActive = !state.isHomePageActive && srv.id == state.activeServerId;
                Color? srvColor;
                if (srv.colorHex.isNotEmpty) {
                  try {
                    srvColor = Color(int.parse('0xFF${srv.colorHex}'));
                  } catch (_) {}
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildServerIcon(
                    isActive: isActive,
                    title: srv.name,
                    initials: srv.name.length >= 2 ? srv.name.substring(0, 2).toUpperCase() : srv.name.toUpperCase(),
                    assetLogo: (index == 0 && !srv.isCustom) ? 'assets/logo.png' : null,
                    customColor: srvColor,
                    mentionCount: state.mentionCountForServer(srv.id),
                    onTap: () => state.selectServer(srv.id),
                    onSecondaryTap: (offset) => ServerContextMenu.show(context, srv, offset),
                  ),
                );
              },
            ),
          ),
          // Add Server Button
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: HudTheme.bgSidebar,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, color: HudTheme.green),
                  tooltip: 'Criar Novo Servidor',
                  onPressed: () => CreateServerDialog.show(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerIcon({
    required bool isActive,
    required String title,
    required String initials,
    required VoidCallback onTap,
    String? assetLogo,
    IconData? iconData,
    Color? customColor,
    int mentionCount = 0,
    void Function(Offset position)? onSecondaryTap,
  }) {
    return _ServerRailItem(
      isActive: isActive,
      title: title,
      initials: initials,
      onTap: onTap,
      assetLogo: assetLogo,
      iconData: iconData,
      customColor: customColor,
      mentionCount: mentionCount,
      onSecondaryTap: onSecondaryTap,
    );
  }
}

class _ServerRailItem extends StatefulWidget {
  final bool isActive;
  final String title;
  final String initials;
  final VoidCallback onTap;
  final String? assetLogo;
  final IconData? iconData;
  final Color? customColor;
  final int mentionCount;

  /// Abre o menu de contexto do servidor no ponto exato do clique com o botão
  /// direito. Nulo no ícone de Início, que não representa um servidor.
  final void Function(Offset position)? onSecondaryTap;

  const _ServerRailItem({
    required this.isActive,
    required this.title,
    required this.initials,
    required this.onTap,
    this.assetLogo,
    this.iconData,
    this.customColor,
    this.mentionCount = 0,
    this.onSecondaryTap,
  });

  @override
  State<_ServerRailItem> createState() => _ServerRailItemState();
}

class _ServerRailItemState extends State<_ServerRailItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final showPill = widget.isActive || _isHovered;
    final pillHeight = widget.isActive ? 40.0 : (_isHovered ? 20.0 : 0.0);
    final borderRadius = (widget.isActive || _isHovered) ? 16.0 : 24.0;
    final accent = widget.customColor ?? HudTheme.green;
    final bgColor = widget.isActive
        ? accent.withValues(alpha: 0.85)
        : (_isHovered ? HudTheme.bgActive : HudTheme.bgSidebar);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: widget.title,
        preferBelow: false,
        verticalOffset: 0,
        margin: const EdgeInsets.only(left: 60),
        child: Row(
          children: [
            // Active / Hover Indicator Pill
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 4,
              height: pillHeight,
              decoration: BoxDecoration(
                color: showPill ? Colors.white : Colors.transparent,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
              ),
            ),
            const SizedBox(width: 6),

            // Server Icon
            GestureDetector(
              onTap: widget.onTap,
              onSecondaryTapUp: widget.onSecondaryTap == null
                  ? null
                  : (details) => widget.onSecondaryTap!(details.globalPosition),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(borderRadius),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: HudTheme.green.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                alignment: Alignment.center,
                child: widget.iconData != null
                    ? Icon(widget.iconData, color: Colors.white, size: 24)
                    : (widget.assetLogo != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(borderRadius - 2),
                            child: Image.asset(widget.assetLogo!, width: 34, height: 34, fit: BoxFit.contain),
                          )
                        : Text(
                            widget.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          )),
                  ),

                  // Marcações não lidas do servidor inteiro, para o usuário
                  // notar que foi citado num canal que não está aberto.
                  if (widget.mentionCount > 0)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 18),
                        decoration: BoxDecoration(
                          color: HudTheme.green,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: HudTheme.bgServerRail, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          widget.mentionCount > 99 ? '99+' : '${widget.mentionCount}',
                          style: const TextStyle(
                            color: Color(0xFF0B0E14),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
