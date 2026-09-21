import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../theme/hud_theme.dart';

class AddFriendDialog extends StatefulWidget {
  const AddFriendDialog({super.key, this.handleInicial = ''});

  /// Quando o convite nasce do mini perfil de alguém, o @ já vem preenchido: a
  /// pessoa acabou de apontar para quem queria adicionar.
  final String handleInicial;

  static Future<void> show(BuildContext context, {String handleInicial = ''}) {
    return showDialog<void>(
      context: context,
      builder: (_) => AddFriendDialog(handleInicial: handleInicial),
    );
  }

  @override
  State<AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<AddFriendDialog> {
  late final TextEditingController _handleController =
      TextEditingController(text: widget.handleInicial);
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final text = _handleController.text.trim().replaceAll('@', '').toLowerCase();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Por favor, informe a tag ou nome de usuário.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final state = context.read<AppState>();
    final error = await state.sendFriendRequest(text);

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _errorMessage = error;
        _isLoading = false;
      });
    } else {
      Navigator.of(context).pop();
      final cleanTag = text.replaceFirst(RegExp(r'^@'), '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: HudTheme.bgSidebar,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          content: Row(
            children: [
              const Icon(Icons.mark_email_read_rounded, color: HudTheme.green, size: 20),
              const SizedBox(width: 12),
              Text(
                'Solicitação de amizade enviada para @$cleanTag!',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Dialog(
      backgroundColor: HudTheme.bgSidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: min(480.0, MediaQuery.sizeOf(context).width - 64),
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
                        color: HudTheme.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.person_add_alt_1_rounded, color: HudTheme.green, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Adicionar Amigo',
                          style: TextStyle(
                            color: HudTheme.textHeader,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Conecte-se ao seu squad através do @tag',
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

            // Informação da tag do usuário atual
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: HudTheme.bgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HudTheme.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: HudTheme.accent, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
                        children: [
                          const TextSpan(text: 'Sua tag pessoal para amigos: '),
                          TextSpan(
                            text: state.currentUser.handle,
                            style: const TextStyle(
                              color: HudTheme.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Campo de Input
            const Text(
              'TAG OU NOME DE USUÁRIO',
              style: TextStyle(
                color: HudTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _handleController,
              autofocus: true,
              style: const TextStyle(color: HudTheme.textNormal),
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[@\s]')),
                LengthLimitingTextInputFormatter(32),
              ],
              onChanged: (val) {
                if (val.contains('@')) {
                  final clean = val.replaceAll('@', '').trim();
                  _handleController.value = TextEditingValue(
                    text: clean,
                    selection: TextSelection.collapsed(offset: clean.length),
                  );
                }
              },
              onSubmitted: (_) => _handleSubmit(),
              decoration: InputDecoration(
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 14, right: 4),
                  child: Text(
                    '@',
                    style: TextStyle(
                      color: HudTheme.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 0),
                hintText: 'tag_do_amigo (ex: feps)',
                hintStyle: const TextStyle(color: HudTheme.textMuted),
                filled: true,
                fillColor: HudTheme.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: HudTheme.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: HudTheme.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar', style: TextStyle(color: HudTheme.textMuted)),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HudTheme.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _isLoading ? null : _handleSubmit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Enviar Solicitação', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
