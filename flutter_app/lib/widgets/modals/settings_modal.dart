import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/app_state.dart';
import '../../theme/hud_theme.dart';

class SettingsModal extends StatefulWidget {
  const SettingsModal({super.key});

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  late TextEditingController _displayNameController;
  late TextEditingController _usernameController;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _displayNameController = TextEditingController(text: state.currentUser.displayName);
    _usernameController = TextEditingController(text: state.currentUser.username);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;

    return Dialog(
      backgroundColor: HudTheme.bgSidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Configurações de Usuário',
                  style: TextStyle(
                    color: HudTheme.textHeader,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: HudTheme.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Profile Preview
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: HudTheme.bgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HudTheme.divider),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: HudTheme.blurple,
                    child: Text(
                      user.initials,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayNameOrUsername,
                          style: const TextStyle(
                            color: HudTheme.textHeader,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${user.handle}${state.currentSession != null ? "  •  ${state.currentSession!.user.email}" : ""}',
                          style: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Display Name Input
            const Text(
              'NOME DE EXIBIÇÃO',
              style: TextStyle(
                color: HudTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _displayNameController,
              style: const TextStyle(color: HudTheme.textNormal),
              decoration: InputDecoration(
                hintText: 'Como os outros verão você (ex: Felipe)',
                hintStyle: const TextStyle(color: HudTheme.textMuted),
                filled: true,
                fillColor: HudTheme.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 16),

            // Handle / Username Input
            const Text(
              'NOME DE USUÁRIO / TAG (IDENTIFICADOR ÚNICO)',
              style: TextStyle(
                color: HudTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _usernameController,
              style: const TextStyle(color: HudTheme.textNormal),
              decoration: InputDecoration(
                prefixText: '@',
                prefixStyle: const TextStyle(color: HudTheme.green, fontWeight: FontWeight.bold),
                hintText: 'tag_do_usuario (para adicionar amigos)',
                hintStyle: const TextStyle(color: HudTheme.textMuted),
                filled: true,
                fillColor: HudTheme.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 20),

            // Status Selector
            const Text(
              'STATUS DE PRESENÇA',
              style: TextStyle(
                color: HudTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildStatusOption(state, UserStatus.online, 'Online', HudTheme.statusOnline),
                const SizedBox(width: 8),
                _buildStatusOption(state, UserStatus.idle, 'Ausente', HudTheme.statusIdle),
                const SizedBox(width: 8),
                _buildStatusOption(state, UserStatus.dnd, 'Não Perturbe', HudTheme.statusDnd),
              ],
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Sair da Conta'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await state.logout();
                  },
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar', style: TextStyle(color: HudTheme.textMuted)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HudTheme.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      onPressed: () async {
                        await state.setDisplayName(_displayNameController.text);
                        await state.setUsername(_usernameController.text);
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: HudTheme.bgSidebar,
                            content: Text('Configurações de perfil salvas com sucesso!'),
                          ),
                        );
                      },
                      child: const Text('Salvar Alterações'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOption(AppState state, UserStatus status, String label, Color color) {
    final isSelected = state.currentUser.status == status;

    return Expanded(
      child: InkWell(
        onTap: () => state.setStatus(status),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? HudTheme.bgActive : HudTheme.bgCard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? HudTheme.textHeader : HudTheme.textMuted,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
