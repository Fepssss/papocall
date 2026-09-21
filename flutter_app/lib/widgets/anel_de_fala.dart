import 'package:flutter/material.dart';
import '../theme/hud_theme.dart';

/// O anel verde de quem está sendo ouvido.
///
/// Mora fora dos cartões da sala de voz porque a pessoa procura esse retorno
/// onde já está olhando: na lista de ocupantes embaixo do canal, na lista de
/// membros do servidor e na própria barra de perfil, no canto inferior
/// esquerdo. Um desenho só nos três lugares evita que "falando" signifique uma
/// cor diferente em cada tela.
///
/// O estado vem do `ActiveSpeakersChangedEvent` do LiveKit, não da presença
/// anunciada pelo broker: é a única fonte que sabe quem o microfone ouviu agora.
class AnelDeFala extends StatelessWidget {
  const AnelDeFala({
    super.key,
    required this.falando,
    required this.child,
    this.larguraDoAnel = 2,
  });

  final bool falando;
  final Widget child;

  /// Grossura da borda, em pixels. Nos cartões grandes o anel pede mais espaço
  /// que na lista de ocupantes, onde ele dividiria a linha com o nome.
  final double larguraDoAnel;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: EdgeInsets.all(larguraDoAnel),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: falando ? HudTheme.green : Colors.transparent,
          width: 2,
        ),
        boxShadow: falando
            ? [
                BoxShadow(
                  color: HudTheme.green.withValues(alpha: 0.65),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
