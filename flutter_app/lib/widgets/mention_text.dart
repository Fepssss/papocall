import 'package:flutter/material.dart';
import '../theme/hud_theme.dart';
import '../utils/mentions.dart';

/// Texto de mensagem com as marcações `@fulano` pintadas.
///
/// Só recebe destaque o @ de alguém que existe no contexto do leitor
/// ([knownHandles]): um `@qualquercoisa` continua texto comum, para que a
/// aparência de marcação nunca sugira que alguém foi avisado quando não foi.
class MentionText extends StatelessWidget {
  final String text;
  final Set<String> knownHandles;
  final String selfHandle;
  final TextStyle baseStyle;

  const MentionText({
    super.key,
    required this.text,
    required this.knownHandles,
    required this.selfHandle,
    required this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final segmentos = splitMentions(
      text,
      knownHandles: knownHandles,
      selfHandle: selfHandle,
    );

    // Sem nenhuma marcação reconhecida, um Text simples evita montar spans à toa
    // numa lista que pode ter centenas de mensagens.
    if (segmentos.length <= 1 && (segmentos.isEmpty || !segmentos.first.isMention)) {
      return Text(text, style: baseStyle);
    }

    return Text.rich(
      TextSpan(
        children: [
          for (final s in segmentos)
            if (!s.isMention)
              TextSpan(text: s.text, style: baseStyle)
            else
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _MentionChip(label: s.text, isSelf: s.isSelf),
              ),
        ],
      ),
      style: baseStyle,
    );
  }
}

class _MentionChip extends StatelessWidget {
  final String label;
  final bool isSelf;

  const _MentionChip({required this.label, required this.isSelf});

  @override
  Widget build(BuildContext context) {
    final cor = isSelf ? HudTheme.green : HudTheme.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: isSelf ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: cor,
          fontSize: 14,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
