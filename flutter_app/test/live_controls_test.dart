import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/utils/app_paths.dart';

import 'app_sandbox.dart';

/// Os controles da transmissão que dependem só do estado: o modo como a tela de
/// outra pessoa ocupa a janela, o volume do áudio que vem junto dela, e a
/// reconfiguração de quem está no ar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  test('o modo de exibição muda uma vez e volta ao sair da chamada', () async {
    final state = AppState();
    var avisos = 0;
    state.addListener(() => avisos++);

    state.definirModoDeExibicao(ModoDeExibicao.teatro);
    expect(state.modoDeExibicao, ModoDeExibicao.teatro);
    expect(avisos, 1);

    // Pedir o modo que já está valendo não tem de repintar a HUD inteira.
    state.definirModoDeExibicao(ModoDeExibicao.teatro);
    expect(avisos, 1);

    await state.disconnectVoice();
    expect(state.modoDeExibicao, ModoDeExibicao.normal);
  });

  test('reconfigurar sem nada no ar não inventa uma transmissão', () async {
    final state = AppState();

    expect(state.transmissaoAtual, isNull);
    expect(await state.reconfigurarTransmissao(fps: 60), isFalse);
    expect(state.transmissaoAtual, isNull);
  });

  test('o volume da live vai para o serviço, para o disco e não passa de 1',
      () async {
    final state = AppState();

    await state.definirVolumeDaLive(0.3);
    expect(state.volumeDaLive, 0.3);
    expect(state.voiceService.volumeDaLive, 0.3);
    expect(
      jsonDecode(AppPaths.file('settings.json').readAsStringSync())['volumeDaLive'],
      0.3,
    );

    await state.definirVolumeDaLive(5);
    expect(state.volumeDaLive, 1.0);

    await state.definirVolumeDaLive(-2);
    expect(state.volumeDaLive, 0.0);
  });

  test('ensurdecer silencia o que entra, e não só o próprio microfone', () {
    final state = AppState();

    state.toggleDeafen();
    expect(state.currentUser.isDeafened, isTrue);
    expect(state.currentUser.isMuted, isTrue, reason: 'quem ensurdece também emudece');
    expect(state.voiceService.ensurdecido, isTrue,
        reason: 'o serviço precisa saber, para desligar cada faixa que chegar');

    state.toggleDeafen();
    expect(state.currentUser.isDeafened, isFalse);
    expect(state.voiceService.ensurdecido, isFalse);
  });
}
