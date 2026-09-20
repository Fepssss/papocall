import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../theme/hud_theme.dart';

class CreateServerDialog extends StatefulWidget {
  const CreateServerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const CreateServerDialog(),
    );
  }

  @override
  State<CreateServerDialog> createState() => _CreateServerDialogState();
}

class _CreateServerDialogState extends State<CreateServerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  String _selectedColorHex = '22C55E';
  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _colors = [
    {'hex': '22C55E', 'color': Color(0xFF22C55E), 'name': 'Verde Tático'},
    {'hex': '38BDF8', 'color': Color(0xFF38BDF8), 'name': 'Azul Aço'},
    {'hex': '8B5CF6', 'color': Color(0xFF8B5CF6), 'name': 'Roxo Cyber'},
    {'hex': 'EF4444', 'color': Color(0xFFEF4444), 'name': 'Carmesim'},
    {'hex': 'F59E0B', 'color': Color(0xFFF59E0B), 'name': 'Âmbar'},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Color _getBadgeColor() {
    try {
      return Color(int.parse('0xFF$_selectedColorHex'));
    } catch (_) {
      return HudTheme.green;
    }
  }

  String _getInitials() {
    final text = _nameController.text.trim();
    if (text.isEmpty) return 'SRV';
    final parts = text.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return text.length >= 2 ? text.substring(0, 2).toUpperCase() : text.toUpperCase();
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final state = context.read<AppState>();
      await state.createServer(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        colorHex: _selectedColorHex,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: HudTheme.bgSidebar,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: HudTheme.green, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Servidor "${_nameController.text.trim()}" ativado!',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: HudTheme.red,
            content: Text('Erro ao criar servidor: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final badgeColor = _getBadgeColor();

    return Dialog(
      backgroundColor: HudTheme.bgSidebar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: HudTheme.divider, width: 1),
      ),
      child: Container(
        width: min(540.0, MediaQuery.sizeOf(context).width - 64),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
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
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.dns_rounded, color: HudTheme.green, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'CRIAR NOVO SERVIDOR',
                            style: TextStyle(
                              color: HudTheme.textHeader,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Centralize seu squad, amigos ou comunidade tática',
                            style: TextStyle(color: HudTheme.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: HudTheme.textMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Live Preview & Name Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Live Server Rail Badge Preview
                  Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: badgeColor.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _getInitials(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Ícone no HUD',
                        style: TextStyle(color: HudTheme.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),

                  // Name & Desc Input Fields
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NOME DO SERVIDOR *',
                          style: TextStyle(
                            color: HudTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nameController,
                          maxLength: 32,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          onChanged: (_) => setState(() {}),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Informe o nome do servidor';
                            }
                            if (value.trim().length < 2) {
                              return 'O nome deve ter no mínimo 2 caracteres';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'ex: Esquadrão Alpha, Dev Lounge...',
                            hintStyle: const TextStyle(color: HudTheme.textMuted, fontSize: 13),
                            counterText: '',
                            filled: true,
                            fillColor: HudTheme.bgCard,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: HudTheme.divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: HudTheme.divider),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: badgeColor, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'DESCRIÇÃO / OBJETIVO (OPCIONAL)',
                          style: TextStyle(
                            color: HudTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _descController,
                          maxLength: 80,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'ex: Canal principal para partidas e calls táticas',
                            hintStyle: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
                            counterText: '',
                            filled: true,
                            fillColor: HudTheme.bgCard,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: HudTheme.divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: HudTheme.divider),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: badgeColor, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Color Palette Picker
              const Text(
                'COR DE DESTAQUE TÁTICA',
                style: TextStyle(
                  color: HudTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: _colors.map((c) {
                  final hex = c['hex'] as String;
                  final color = c['color'] as Color;
                  final isSelected = _selectedColorHex == hex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => _selectedColorHex = hex),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [],
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 16)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Estrutura inicial fixa: sem escolha de template.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: HudTheme.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: HudTheme.divider),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.account_tree_rounded, color: HudTheme.textMuted, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Começa com #geral, #anúncios e uma Sala de Voz. Novos canais '
                        'se criam depois, de dentro do servidor.',
                        style: TextStyle(color: HudTheme.textNormal, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Bottom Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: HudTheme.textMuted,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: badgeColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 4,
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.add_task_rounded, size: 18),
                    label: Text(
                      _isSubmitting ? 'Criando...' : 'Criar Servidor',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: _isSubmitting ? null : _handleCreate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
