import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../theme/hud_theme.dart';
import '../screen_share_dialog.dart';

/// O painel de quem está ao vivo.
///
/// A pessoa começa a transmitir e precisa mudar de ideia no meio: a janela
/// errada, o jogo em 30 quadros que devia ser 60, a resolução que pesa na
/// conexão. Sem este painel a única saída era parar e recomeçar, perdendo o
/// que estava escolhido. Tudo aqui trabalha sobre a transmissão que já está
/// no ar, e só publica de novo quando se aperta Aplicar.
class LiveSettingsDialog extends StatefulWidget {
  const LiveSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => const LiveSettingsDialog(),
    );
  }

  @override
  State<LiveSettingsDialog> createState() => _LiveSettingsDialogState();
}

class _LiveSettingsDialogState extends State<LiveSettingsDialog> {
  String _sourceId = '';
  String _nome = '';
  int _altura = 1080;
  int _fps = 30;
  bool _aplicando = false;

  @override
  void initState() {
    super.initState();
    final atual = context.read<AppState>().transmissaoAtual;
    if (atual != null) {
      _sourceId = atual.sourceId;
      _nome = atual.nome;
      _altura = atual.height;
      _fps = atual.fps;
    }
  }

  int get _largura => _altura == 1080 ? 1920 : 1280;

  /// O que está no ar hoje é diferente do que a pessoa escolheu aqui?
  bool _mudouPara(AppState state) {
    final noAr = state.transmissaoAtual;
    if (noAr == null) return false;
    return noAr.sourceId != _sourceId || noAr.height != _altura || noAr.fps != _fps;
  }

  Future<void> _trocarJanela() async {
    final escolha = await ScreenShareDialog.show(context);
    if (escolha == null || !mounted) return;
    setState(() {
      _sourceId = escolha.sourceId;
      _nome = escolha.nome;
      _altura = escolha.height;
      _fps = escolha.fps;
    });
  }

  Future<void> _aplicar(AppState state) async {
    setState(() => _aplicando = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ok = await state.reconfigurarTransmissao(
      sourceId: _sourceId,
      nomeDaFonte: _nome,
      width: _largura,
      height: _altura,
      fps: _fps,
    );
    nav.pop();
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('A nova configuração não entrou no ar. A transmissão foi parada.'),
          backgroundColor: HudTheme.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final noAr = state.transmissaoAtual;

    return AlertDialog(
      backgroundColor: HudTheme.bgSidebar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HudTheme.divider),
      ),
      title: const Text(
        'Configurar a transmissão',
        style: TextStyle(color: HudTheme.textHeader, fontWeight: FontWeight.bold, fontSize: 16),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Linha(
              rotulo: 'No ar',
              valor: noAr == null
                  ? 'nada'
                  : '${noAr.nome.isEmpty ? "janela" : noAr.nome} - ${noAr.width}x${noAr.height} ${noAr.fps} FPS',
            ),
            const SizedBox(height: 18),
            const Text(
              'RESOLUÇÃO',
              style: TextStyle(color: HudTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.6),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Opcao(
                  texto: '720p',
                  selecionada: _altura == 720,
                  onTap: () => setState(() => _altura = 720),
                ),
                const SizedBox(width: 8),
                _Opcao(
                  texto: '1080p',
                  selecionada: _altura == 1080,
                  onTap: () => setState(() => _altura = 1080),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'QUADROS POR SEGUNDO',
              style: TextStyle(color: HudTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.6),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Opcao(
                  texto: '30 FPS',
                  selecionada: _fps == 30,
                  onTap: () => setState(() => _fps = 30),
                ),
                const SizedBox(width: 8),
                _Opcao(
                  texto: '60 FPS',
                  selecionada: _fps == 60,
                  onTap: () => setState(() => _fps = 60),
                ),
              ],
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: HudTheme.accent,
                side: const BorderSide(color: HudTheme.divider),
              ),
              icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 16),
              label: Text(_nome.isEmpty ? 'Escolher a janela' : 'Trocar de janela'),
              onPressed: _aplicando ? null : _trocarJanela,
            ),
            if (_mudouPara(state)) ...[
              const SizedBox(height: 14),
              const Text(
                'Aplicar recomeça a transmissão: quem assiste vê o cartão piscar e voltar com a escolha nova.',
                style: TextStyle(color: HudTheme.textMuted, fontSize: 11, height: 1.4),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: HudTheme.red),
          onPressed: _aplicando
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  await state.stopScreenShare();
                  nav.pop();
                },
          child: const Text('Parar transmissão'),
        ),
        const Spacer(),
        TextButton(
          onPressed: _aplicando ? null : () => Navigator.of(context).pop(),
          child: const Text('Fechar', style: TextStyle(color: HudTheme.textMuted)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: HudTheme.green,
            foregroundColor: Colors.white,
          ),
          icon: _aplicando
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check, size: 16),
          label: const Text('Aplicar'),
          onPressed: (_aplicando || !_mudouPara(state)) ? null : () => _aplicar(state),
        ),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$rotulo: ', style: const TextStyle(color: HudTheme.textMuted, fontSize: 12)),
        Expanded(
          child: Text(
            valor,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: HudTheme.textHeader, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _Opcao extends StatelessWidget {
  const _Opcao({required this.texto, required this.selecionada, required this.onTap});

  final String texto;
  final bool selecionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selecionada ? HudTheme.green.withValues(alpha: 0.16) : HudTheme.bgCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selecionada ? HudTheme.green : HudTheme.divider),
        ),
        child: Text(
          texto,
          style: TextStyle(
            color: selecionada ? HudTheme.green : HudTheme.textNormal,
            fontSize: 12,
            fontWeight: selecionada ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
