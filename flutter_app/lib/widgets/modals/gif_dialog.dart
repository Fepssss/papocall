import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme/hud_theme.dart';

/// Escolha do GIF que vai para o chat.
///
/// O botão já existia, mas mandava sempre o mesmo endereço fixo de
/// media.giphy.com — que hoje responde 404, e o resultado na tela era
/// "[GIF não carregado]". Não há busca de galeria embutida no aplicativo: o
/// que existe aqui é honesto, a pessoa cola o link do próprio GIF e vê a
/// imagem antes de decidir mandar. Se ela não carrega, o botão de enviar não
/// abre.
class GifDialog extends StatefulWidget {
  const GifDialog({super.key});

  /// Devolve o endereço confirmado, ou null se a pessoa desistiu.
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => const GifDialog(),
    );
  }

  @override
  State<GifDialog> createState() => _GifDialogState();
}

class _GifDialogState extends State<GifDialog> {
  final TextEditingController _campo = TextEditingController();
  Timer? _antecipe;
  String _endereco = '';
  bool _carregou = false;
  bool _falhou = false;

  @override
  void initState() {
    super.initState();
    _campo.addListener(_marcarVerificacao);
  }

  @override
  void dispose() {
    _antecipe?.cancel();
    _campo.dispose();
    super.dispose();
  }

  /// Digitar endereço é feito de um jeito desajeitado: cada tecla reinicia a
  /// checagem, e ela só vai ao ar meia segunda depois da última.
  void _marcarVerificacao() {
    _antecipe?.cancel();
    setState(() {
      _carregou = false;
      _falhou = false;
    });
    _antecipe = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _endereco = _campo.text.trim());
    });
  }

  bool get _enderecoValido =>
      _endereco.isNotEmpty &&
      (_endereco.startsWith('http://') || _endereco.startsWith('https://'));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: HudTheme.bgSidebar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HudTheme.divider),
      ),
      title: const Text(
        'Enviar um GIF',
        style: TextStyle(color: HudTheme.textHeader, fontWeight: FontWeight.bold, fontSize: 16),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _campo,
              autofocus: true,
              style: const TextStyle(color: HudTheme.textNormal, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Endereço do GIF (giphy, tenor, o que for)',
                hintStyle: TextStyle(color: HudTheme.textMuted, fontSize: 13),
                filled: true,
                fillColor: HudTheme.bgInput,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: HudTheme.divider),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HudTheme.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: _previa(),
            ),
            const SizedBox(height: 8),
            Text(
              _legenda(),
              style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar', style: TextStyle(color: HudTheme.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: HudTheme.green),
          onPressed: _carregou ? () => Navigator.of(context).pop(_endereco) : null,
          child: const Text('Enviar GIF', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  String _legenda() {
    if (!_enderecoValido) return 'Cole um endereço http(s) para ver a prévia.';
    if (_falhou) return 'Essa imagem não carregou. Confira o endereço.';
    if (_carregou) return 'Pronta para enviar.';
    return 'Carregando a prévia...';
  }

  Widget _previa() {
    if (!_enderecoValido) {
      return const Center(
        child: Icon(Icons.gif_box_outlined, color: HudTheme.divider, size: 40),
      );
    }
    return Image.network(
      _endereco,
      fit: BoxFit.contain,
      frameBuilder: (_, child, frame, _) {
        if (frame != null && !_carregou && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _carregou = true);
          });
        }
        return child;
      },
      errorBuilder: (_, _, _) {
        if (!_falhou && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _falhou = true);
          });
        }
        return const Center(
          child: Icon(Icons.broken_image_outlined, color: HudTheme.red, size: 36),
        );
      },
    );
  }
}
