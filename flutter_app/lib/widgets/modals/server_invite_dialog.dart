import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/server.dart';
import '../../providers/app_state.dart';
import '../../theme/hud_theme.dart';

class ServerInviteDialog extends StatefulWidget {
  final Server server;

  const ServerInviteDialog({super.key, required this.server});

  static Future<void> show(BuildContext context, Server server) {
    return showDialog<void>(
      context: context,
      builder: (_) => ServerInviteDialog(server: server),
    );
  }

  @override
  State<ServerInviteDialog> createState() => _ServerInviteDialogState();
}

class _ServerInviteDialogState extends State<ServerInviteDialog> {
  bool _isRegenerating = false;

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: HudTheme.bgSidebar,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: HudTheme.green, size: 20),
            const SizedBox(width: 12),
            Text(
              '$label copiado para a área de transferência!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _regenerateInvite() async {
    setState(() => _isRegenerating = true);
    final state = context.read<AppState>();
    await state.regenerateServerInvite(widget.server.id);
    if (!mounted) return;
    setState(() => _isRegenerating = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: HudTheme.bgSidebar,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: const Row(
          children: [
            Icon(Icons.refresh_rounded, color: HudTheme.accent, size: 20),
            SizedBox(width: 12),
            Text(
              'Novo código de convite gerado com sucesso!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentServer = state.servers.firstWhere(
      (s) => s.id == widget.server.id,
      orElse: () => widget.server,
    );
    final inviteCode = currentServer.inviteCode;
    final inviteLink = 'https://papocall.vercel.app/join/$inviteCode';

    return Dialog(
      backgroundColor: HudTheme.bgSidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: min(500.0, MediaQuery.sizeOf(context).width - 64),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: HudTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.share_rounded, color: HudTheme.accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Convidar para ${currentServer.name}',
                          style: const TextStyle(
                            color: HudTheme.textHeader,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Envie o link ou código para amigos entrarem neste servidor',
                          style: TextStyle(color: HudTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: HudTheme.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Código de Convite Direto
            const Text(
              'CÓDIGO DIRETO DO SERVIDOR',
              style: TextStyle(
                color: HudTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: HudTheme.bgInput,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HudTheme.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.vpn_key_rounded, color: HudTheme.green, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      inviteCode,
                      style: const TextStyle(
                        color: HudTheme.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HudTheme.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copiar Código', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () => _copyToClipboard(inviteCode, 'Código'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Link Completo de Convite
            const Text(
              'LINK DE CONVITE PAPOCALL',
              style: TextStyle(
                color: HudTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: HudTheme.bgInput,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HudTheme.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, color: HudTheme.accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      inviteLink,
                      style: const TextStyle(
                        color: HudTheme.textNormal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HudTheme.accent,
                      side: const BorderSide(color: HudTheme.divider),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copiar Link', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () => _copyToClipboard(inviteLink, 'Link'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Informações e Regenerar Convite
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: HudTheme.textMuted,
                  ),
                  icon: _isRegenerating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: HudTheme.textMuted),
                        )
                      : const Icon(Icons.autorenew_rounded, size: 16),
                  label: const Text('Regenerar novo código', style: TextStyle(fontSize: 12)),
                  onPressed: _isRegenerating ? null : _regenerateInvite,
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HudTheme.bgCard,
                    foregroundColor: HudTheme.textHeader,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Concluído'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
