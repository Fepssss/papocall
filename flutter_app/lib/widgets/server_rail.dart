import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';

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
          // Direct Home / PapoCall Logo
          _buildServerIcon(
            isActive: state.activeServerId == 'server-default',
            title: 'PapoCall',
            initials: 'PC',
            assetLogo: 'assets/logo.png',
            onTap: () => state.selectServer('server-default'),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: HudTheme.divider, height: 2),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: state.servers.length - 1,
              itemBuilder: (context, index) {
                final srv = state.servers[index + 1];
                final isActive = srv.id == state.activeServerId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildServerIcon(
                    isActive: isActive,
                    title: srv.name,
                    initials: srv.name.substring(0, 2).toUpperCase(),
                    onTap: () => state.selectServer(srv.id),
                  ),
                );
              },
            ),
          ),
          // Add Server Button
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: HudTheme.bgSidebar,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.add, color: HudTheme.green),
                tooltip: 'Adicionar um Servidor',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Criar Servidor em breve!')),
                  );
                },
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
  }) {
    return _ServerRailItem(
      isActive: isActive,
      title: title,
      initials: initials,
      onTap: onTap,
      assetLogo: assetLogo,
    );
  }
}

class _ServerRailItem extends StatefulWidget {
  final bool isActive;
  final String title;
  final String initials;
  final VoidCallback onTap;
  final String? assetLogo;

  const _ServerRailItem({
    required this.isActive,
    required this.title,
    required this.initials,
    required this.onTap,
    this.assetLogo,
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
    final bgColor = widget.isActive
        ? const Color(0xFF1E7E48)
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
              child: AnimatedContainer(
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
                child: widget.assetLogo != null
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
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
