import 'package:flutter/material.dart';
import '../theme/hud_theme.dart';

/// Mostra o motivo de uma entrada malsucedida em canal de voz.
///
/// O HUD de voz só aparece enquanto há conexão, então sem isto a falha era
/// invisível: o ícone voltava para desconectado sem dizer por quê.
///
/// Recebe o messenger já capturado porque quem chama costuma fechar a tela
/// atual antes de aguardar a conexão, e aí o BuildContext pode já estar morto.
void reportVoiceJoinError(ScaffoldMessengerState messenger, String? erro) {
  if (erro == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(erro),
      backgroundColor: HudTheme.red,
    ),
  );
}
