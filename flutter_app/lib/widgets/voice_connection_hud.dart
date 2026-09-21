import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'acao_compartilhar_tela.dart';
import 'modals/live_settings_dialog.dart';

/// A barra de voz no pé do painel esquerdo.
///
/// Duas linhas: a de cima diz onde você está e quão rápido, a de baixo traz os
/// controles da chamada. Os botões são os que o aplicativo tem de verdade —
/// compartilhar tela, configurar a transmissão enquanto ela está no ar, mutar e
/// ensurdecer. O que não existe (câmera, "melhoria de voz") não ganha botão
/// só porque a referência tinha.
class VoiceConnectionHud extends StatelessWidget {
  const VoiceConnectionHud({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isConnecting = state.isConnectingVoice && state.connectedVoiceChannelId == null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: HudTheme.bgHover,
        border: Border(
          top: BorderSide(color: HudTheme.divider, width: 1),
          bottom: BorderSide(color: HudTheme.divider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LinhaDeStatus(state: state, isConnecting: isConnecting),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BotaoDeVoz(
                icone: state.isScreenSharing
                    ? Icons.stop_screen_share_rounded
                    : Icons.screen_share_rounded,
                tooltip: state.isScreenSharing
                    ? 'Parar compartilhamento de tela'
                    : 'Compartilhar tela ou janela',
                cor: state.isScreenSharing ? HudTheme.red : HudTheme.textNormal,
                fundo: state.isScreenSharing ? HudTheme.red.withValues(alpha: 0.16) : null,
                onPressed: () => alternarCompartilhamentoDeTela(context, state),
              ),
              if (state.isScreenSharing)
                _BotaoDeVoz(
                  icone: Icons.tune_rounded,
                  tooltip: 'Configurar a transmissão',
                  cor: HudTheme.accent,
                  onPressed: () => LiveSettingsDialog.show(context),
                ),
              _BotaoDeVoz(
                icone: state.currentUser.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                tooltip: state.currentUser.isMuted ? 'Desmutar microfone' : 'Mutar microfone',
                cor: state.currentUser.isMuted
                    ? HudTheme.red
                    : (state.currentUser.isSpeaking ? HudTheme.green : HudTheme.textNormal),
                fundo: state.currentUser.isMuted ? HudTheme.red.withValues(alpha: 0.16) : null,
                onPressed: state.toggleMute,
              ),
              _BotaoDeVoz(
                icone: state.currentUser.isDeafened
                    ? Icons.headset_off_rounded
                    : Icons.headset_rounded,
                tooltip: state.currentUser.isDeafened ? 'Voltar a ouvir a sala' : 'Ensurdecer',
                cor: state.currentUser.isDeafened ? HudTheme.red : HudTheme.textNormal,
                fundo: state.currentUser.isDeafened ? HudTheme.red.withValues(alpha: 0.16) : null,
                onPressed: state.toggleDeafen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinhaDeStatus extends StatelessWidget {
  const _LinhaDeStatus({required this.state, required this.isConnecting});

  final AppState state;
  final bool isConnecting;

  /// Onde a pessoa está: o servidor e o canal que realmente carregam a
  /// conexão de voz, não o servidor que está aberto na tela — eles podem
  /// ser diferentes depois de trocar de aba no meio de uma chamada.
  (String, String) _ondeEstou() {
    final idDoCanal = state.connectedVoiceChannelId;
    if (idDoCanal != null) {
      for (final srv in state.servers) {
        for (final c in srv.channels) {
          if (c.id == idDoCanal) return (srv.name, c.name);
        }
      }
    }
    if (isConnecting && state.activeServer != null) {
      final canal = state.activeChannel;
      return (state.activeServer!.name, canal?.name ?? 'Sala de Voz');
    }
    return ('PapoCall', 'Sala de Voz');
  }

  @override
  Widget build(BuildContext context) {
    final (servidor, canal) = _ondeEstou();
    final corEstado = isConnecting ? HudTheme.accent : HudTheme.green;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: corEstado.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: corEstado.withValues(alpha: 0.35)),
          ),
          child: Icon(
            isConnecting ? Icons.sync : Icons.wifi_tethering_rounded,
            color: corEstado,
            size: 16,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isConnecting ? 'Conectando...' : 'Voz conectada',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: corEstado,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$servidor / $canal',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        _IndicadorDeTransmissao(state: state),
        const SizedBox(width: 4),
        _BotaoDeSair(onPressed: state.disconnectVoice),
      ],
    );
  }
}

/// O ícone de ondas: acende enquanto o seu microfone está sendo ouvido, e o
/// tooltip traz a latência medida pelo próprio SDK.
class _IndicadorDeTransmissao extends StatelessWidget {
  const _IndicadorDeTransmissao({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final falando = state.currentUser.isSpeaking;
    final mutado = state.currentUser.isMuted;
    final cor = mutado ? HudTheme.red : (falando ? HudTheme.green : HudTheme.textMuted);

    return Tooltip(
      message: mutado
          ? 'Microfone mutado — ninguém está ouvindo você'
          : (state.voicePingMs > 0
              ? 'Sua transmissão: ${falando ? 'no ar' : 'silenciosa'}\n'
                  'Latência: ${state.voicePingMs} ms · ${state.voiceConnectionQuality}'
              : 'Medindo a latência com o servidor...'),
      waitDuration: const Duration(milliseconds: 200),
      child: Icon(Icons.graphic_eq_rounded, size: 18, color: cor),
    );
  }
}

class _BotaoDeVoz extends StatefulWidget {
  const _BotaoDeVoz({
    required this.icone,
    required this.tooltip,
    required this.cor,
    required this.onPressed,
    this.fundo,
  });

  final IconData icone;
  final String tooltip;
  final Color cor;
  final Color? fundo;
  final VoidCallback onPressed;

  @override
  State<_BotaoDeVoz> createState() => _BotaoDeVozState();
}

class _BotaoDeVozState extends State<_BotaoDeVoz> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 56,
            height: 38,
            decoration: BoxDecoration(
              color: widget.fundo ?? (_hover ? HudTheme.bgActive : HudTheme.bgCard),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _hover ? widget.cor : HudTheme.divider),
            ),
            child: Icon(widget.icone, size: 18, color: widget.cor),
          ),
        ),
      ),
    );
  }
}

class _BotaoDeSair extends StatefulWidget {
  const _BotaoDeSair({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_BotaoDeSair> createState() => _BotaoDeSairState();
}

class _BotaoDeSairState extends State<_BotaoDeSair> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Desconectar da voz',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _hover ? HudTheme.red.withValues(alpha: 0.2) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.call_end_rounded,
              size: 18,
              color: _hover ? HudTheme.red : HudTheme.textNormal,
            ),
          ),
        ),
      ),
    );
  }
}
