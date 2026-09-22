import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../services/voice_service.dart';
import '../../theme/hud_theme.dart';

/// Os três seletores de dispositivo da aba "Voz e Áudio": microfone, saída e
/// câmera.
///
/// A escolha pega na hora (o [AppState] manda o VoiceService aplicar) e volta
/// na próxima abertura porque é gravada em settings.json.
class AudioDevicesPanel extends StatefulWidget {
  const AudioDevicesPanel({super.key});

  @override
  State<AudioDevicesPanel> createState() => _AudioDevicesPanelState();
}

class _AudioDevicesPanelState extends State<AudioDevicesPanel> {
  List<MediaDevice> _entradas = const [];
  List<MediaDevice> _saidas = const [];
  List<MediaDevice> _camaras = const [];
  bool _carregando = true;
  String? _falha;
  StreamSubscription<List<MediaDevice>>? _mudancaDeRede;

  @override
  void initState() {
    super.initState();
    recarregar();
    // Fone no USB entra e sai sem o aplicativo pedir nada. O plugin entrega a
    // lista nova nesse aviso, então é dele que a tela se atualiza.
    _mudancaDeRede = Hardware.instance.onDeviceChange.stream.listen((_) {
      if (mounted) recarregar();
    });
  }

  @override
  void dispose() {
    _mudancaDeRede?.cancel();
    super.dispose();
  }

  Future<void> recarregar() async {
    setState(() {
      _carregando = true;
      _falha = null;
    });
    try {
      final entradas = await VoiceService.listarEntradasDeAudio();
      final saidas = await VoiceService.listarSaidasDeAudio();
      // A câmera é lida numa tentativa à parte: o Windows pode negar a
      // enumeração de vídeo inteiro sem permissão, e isso não tem o direito de
      // esconder os microfones que estão funcionando.
      var camaras = const <MediaDevice>[];
      try {
        camaras = await VoiceService.listarCamaras();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _entradas = entradas;
        _saidas = saidas;
        _camaras = camaras;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _falha = 'O Windows não devolveu a lista de dispositivos.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Guardar a escolha é um passo; mandar o motor WebRTC usá-la agora é
    // outro. Sem o segundo, trocar de microfone no meio da call não trocava
    // nada até a pessoa sair e entrar de novo.
    Future<void> aplicar(Future<void> Function(String?) guardar, String? id) async {
      await guardar(id);
      await state.voiceService.aplicarDispositivosEscolhidos();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'DISPOSITIVOS DE ÁUDIO E VÍDEO',
                style: TextStyle(
                  color: HudTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _carregando ? null : recarregar,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: Text(_carregando ? 'Procurando...' : 'Procurar de novo'),
              style: TextButton.styleFrom(
                foregroundColor: HudTheme.green,
                disabledForegroundColor: HudTheme.textMuted,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
        if (_falha != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '$_falha Plugue o aparelho e toque em "Procurar de novo".',
              style: const TextStyle(color: HudTheme.red, fontSize: 12),
            ),
          ),
        _SeletorDispositivo(
          icone: Icons.mic_rounded,
          titulo: 'Entrada (microfone)',
          dispositivos: _entradas,
          valor: state.audioInputId,
          carregando: _carregando,
          onChanged: (id) => aplicar(state.definirMicrofone, id),
        ),
        const SizedBox(height: 14),
        _SeletorDispositivo(
          icone: Icons.volume_up_rounded,
          titulo: 'Saída (fone ou alto-falante)',
          dispositivos: _saidas,
          valor: state.audioOutputId,
          carregando: _carregando,
          onChanged: (id) => aplicar(state.definirSaidaDeAudio, id),
        ),
        const SizedBox(height: 14),
        _SeletorDispositivo(
          icone: Icons.videocam_rounded,
          titulo: 'Câmera',
          dispositivos: _camaras,
          valor: state.cameraId,
          carregando: _carregando,
          // Escolher câmera sem estar em call não liga nada: a captura começa
          // quando a pessoa aperta o botão de vídeo. Com a câmera no ar, a
          // escolha repassa a faixa, e o motivo de uma recusa do Windows
          // aparece em vez de virar silêncio.
          onChanged: (id) async {
            final messenger = ScaffoldMessenger.of(context);
            final motivo = await state.definirCamera(id);
            if (motivo == null) return;
            messenger.showSnackBar(
              SnackBar(content: Text(motivo), backgroundColor: HudTheme.red),
            );
          },
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _SeletorDispositivo extends StatelessWidget {
  const _SeletorDispositivo({
    required this.icone,
    required this.titulo,
    required this.dispositivos,
    required this.valor,
    required this.carregando,
    required this.onChanged,
  });

  final IconData icone;
  final String titulo;
  final List<MediaDevice> dispositivos;
  final String? valor;
  final bool carregando;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // O id escolhido pode ter sumido do computador desde a última vez que a
    // pessoa mexeu aqui. Mostrar um seletor vazio seria mentir sobre o estado;
    // o item reaparece assim que o dispositivo volta.
    final sumico = valor != null && !dispositivos.any((d) => d.deviceId == valor);
    final vazio = !carregando && dispositivos.isEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF222838)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 16, color: HudTheme.green),
              const SizedBox(width: 10),
              Text(
                titulo,
                style: const TextStyle(
                  color: HudTheme.textHeader,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (carregando)
            const _Aviso('Lendo os dispositivos do Windows...')
          else if (vazio)
            const _Aviso('Nenhum dispositivo deste tipo encontrado.')
          else if (sumico)
            _Aviso('O escolhido antes não está plugado agora: $valor'),
          DropdownButton<String>(
            isExpanded: true,
            value: (sumico || carregando) ? null : valor,
            hint: const Text('Padrão do sistema',
                style: TextStyle(color: HudTheme.textNormal, fontSize: 13)),
            dropdownColor: HudTheme.bgSidebar,
            iconEnabledColor: HudTheme.green,
            style: const TextStyle(color: HudTheme.textHeader, fontSize: 13),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Padrão do sistema', style: TextStyle(color: HudTheme.textMuted)),
              ),
              ...dispositivos.map(
                (d) => DropdownMenuItem<String>(
                  value: d.deviceId,
                  child: Text(d.label.isEmpty ? d.deviceId : d.label,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: carregando ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        texto,
        style: const TextStyle(color: HudTheme.textMuted, fontSize: 11.5),
      ),
    );
  }
}
