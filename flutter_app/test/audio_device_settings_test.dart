import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/services/voice_service.dart';
import 'package:papocall/utils/app_paths.dart';

import 'app_sandbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  late Future<List<MediaDevice>> Function() entradasReais;
  late Future<List<MediaDevice>> Function() saidasReais;

  setUp(() {
    entradasReais = VoiceService.listarEntradasDeAudio;
    saidasReais = VoiceService.listarSaidasDeAudio;
    // Sem plugin de áudio no teste: a enumeração devolve lista vazia.
    VoiceService.listarEntradasDeAudio = () async => const [];
    VoiceService.listarSaidasDeAudio = () async => const [];
  });

  tearDown(() {
    VoiceService.listarEntradasDeAudio = entradasReais;
    VoiceService.listarSaidasDeAudio = saidasReais;
  });

  Map<String, dynamic> configLida() =>
      jsonDecode(AppPaths.file('settings.json').readAsStringSync());

  test('a escolha de entrada e saída sobrevive ao fechar o aplicativo', () async {
    final state = AppState();

    await state.definirMicrofone('mic-usb');
    await state.definirSaidaDeAudio('fone-azul');
    await state.definirSupressaoDeRuido(false);

    final salvas = configLida();
    expect(salvas['audioInputId'], 'mic-usb');
    expect(salvas['audioOutputId'], 'fone-azul');
    expect(salvas['noiseSuppression'], false);
  });

  test('a escolha fica espelhada no serviço que entra na call', () async {
    final state = AppState();

    await state.definirMicrofone('mic-usb');
    expect(state.voiceService.entradaDeAudioId, 'mic-usb');

    await state.definirSupressaoDeRuido(false);
    expect(state.voiceService.supressaoDeRuido, isFalse);

    // Voltar ao padrão do Windows tem que sumir com o id gravado também.
    await state.definirMicrofone(null);
    expect(state.voiceService.entradaDeAudioId, isNull);
    expect(configLida()['audioInputId'], isNull);
  });

  test('dispositivo escolhido que não está plugado não derruba a aplicação',
      () async {
    final state = AppState();
    await state.definirMicrofone('mic-arrancado-do-usb');
    await state.definirSaidaDeAudio('fone-guardado-na-gaveta');

    // Sem sala e sem o dispositivo na lista: nada é aplicado, nada estoura.
    await expectLater(state.voiceService.aplicarDispositivosEscolhidos(), completes);
  });
}
