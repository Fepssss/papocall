import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../theme/hud_theme.dart';

/// Caixa de atualização: mostra o que há de novo e faz o download na frente
/// de quem pediu.
///
/// Nada aqui é decorativo — o botão só aparece quando existe um instalador
/// conferido para baixar, e o progresso é o do download real.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const UpdateDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final manifesto = state.atualizacaoDisponivel;
    final emChamada = state.connectedVoiceChannelId != null;

    return Dialog(
      backgroundColor: HudTheme.bgSidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: min(460.0, MediaQuery.sizeOf(context).width - 64),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: HudTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.system_update_alt_rounded,
                      color: HudTheme.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manifesto == null
                            ? 'Atualizações'
                            : 'Atualização v${manifesto.version} disponível',
                        style: const TextStyle(
                          color: HudTheme.textHeader,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Versão instalada: v${HudTheme.appVersion}',
                        style: const TextStyle(
                            color: HudTheme.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: HudTheme.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (manifesto != null && manifesto.notes.trim().isNotEmpty) ...[
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: HudTheme.bgInput,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: HudTheme.divider),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    manifesto.notes.trim(),
                    style: const TextStyle(
                        color: HudTheme.textNormal, fontSize: 13, height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (emChamada) ...[
              const _Aviso(
                icone: Icons.call_rounded,
                texto:
                    'Você está em uma chamada de voz. Saia da sala antes de '
                    'atualizar: reiniciar o aplicativo no meio da chamada '
                    'derruba a sala para todo mundo.',
              ),
              const SizedBox(height: 16),
            ],

            if (state.erroAoVerificarAtualizacao != null) ...[
              _Aviso(
                icone: Icons.error_outline_rounded,
                texto: state.erroAoVerificarAtualizacao!,
              ),
              const SizedBox(height: 16),
            ],

            if (state.baixandoAtualizacao) ...[
              _BarraDeProgresso(fracao: state.progressoDoDownload),
              const SizedBox(height: 16),
            ],

            if (manifesto == null && !state.verificandoAtualizacao)
              const Text(
                'O aplicativo está na versão mais recente. Uma novidade aparece '
                'aqui sozinha, na próxima abertura.',
                style: TextStyle(
                    color: HudTheme.textMuted, fontSize: 13, height: 1.5),
              ),

            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Depois',
                    style: TextStyle(color: HudTheme.textMuted, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HudTheme.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: HudTheme.bgCard,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: state.verificandoAtualizacao || state.baixandoAtualizacao
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white70),
                        )
                      : const Icon(Icons.download_rounded, size: 16),
                  label: Text(
                    state.baixandoAtualizacao
                        ? 'Baixando...'
                        : (manifesto == null
                            ? 'Verificar novamente'
                            : 'Atualizar e reiniciar'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: (state.verificandoAtualizacao ||
                          state.baixandoAtualizacao ||
                          emChamada)
                      ? null
                      : () {
                          if (manifesto == null) {
                            state.verificarAtualizacao();
                          } else {
                            state.baixarEInstalarAtualizacao();
                          }
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icone;
  final String texto;

  const _Aviso({required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: HudTheme.yellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: HudTheme.yellow.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: HudTheme.yellow),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                  color: Color(0xFFE5E7EB), fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarraDeProgresso extends StatelessWidget {
  final double? fracao;

  const _BarraDeProgresso({required this.fracao});

  @override
  Widget build(BuildContext context) {
    final percentual = fracao == null ? 0 : (fracao! * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: fracao,
          minHeight: 6,
          backgroundColor: HudTheme.bgCard,
          valueColor: const AlwaysStoppedAnimation(HudTheme.green),
        ),
        const SizedBox(height: 8),
        Text(
          fracao == null || fracao! < 1
              ? 'Baixando o instalador: $percentual%'
              : 'Instalador conferido. Reiniciando o aplicativo...',
          style: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}
