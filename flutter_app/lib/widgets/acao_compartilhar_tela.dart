import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'screen_share_dialog.dart';

/// Liga e desliga a transmissão de tela a partir de qualquer lugar do app.
///
/// Mora aqui e não dentro da cabine de voz porque o botão existe em dois
/// lugares: no dock flutuante da chamada e na barra de voz do painel esquerdo.
/// Copiar a regra para os dois é como ela começa a discordar de si mesma — um
/// deles esqueceria de avisar quando a transmissão não subiu, por exemplo.
Future<void> alternarCompartilhamentoDeTela(
  BuildContext context,
  AppState state,
) async {
  if (state.isScreenSharing) {
    await state.stopScreenShare();
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  try {
    final escolha = await ScreenShareDialog.show(context);
    if (escolha == null) return;

    final ok = await state.startScreenShare(
      escolha.sourceId,
      nomeDaFonte: escolha.nome,
      width: escolha.width,
      height: escolha.height,
      fps: escolha.fps,
    );
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível iniciar o compartilhamento de tela.'),
          backgroundColor: HudTheme.red,
        ),
      );
    }
  } catch (e) {
    debugPrint('Erro ao abrir diálogo de seleção de tela: $e');
  }
}
