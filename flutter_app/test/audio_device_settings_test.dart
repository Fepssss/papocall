import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/services/sound_service.dart';
import 'package:papocall/services/voice_service.dart';
import 'package:papocall/utils/app_paths.dart';

import 'app_sandbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  late Future<List<MediaDevice>> Function() entradasReais;
  late Future<List<MediaDevice>> Function() saidasReais;
  late Future<bool> Function(bool) filtroNeuralReal;

  setUp(() {
    entradasReais = VoiceService.listarEntradasDeAudio;
    saidasReais = VoiceService.listarSaidasDeAudio;
    filtroNeuralReal = VoiceService.aplicarFiltroNeuralNative;
    // Sem plugin de áudio no teste: a enumeração devolve lista vazia.
    VoiceService.listarEntradasDeAudio = () async => const [];
    VoiceService.listarSaidasDeAudio = () async => const [];
  });

  tearDown(() {
    VoiceService.listarEntradasDeAudio = entradasReais;
    VoiceService.listarSaidasDeAudio = saidasReais;
    VoiceService.aplicarFiltroNeuralNative = filtroNeuralReal;
    // O SoundService é estático: sem devolver os avisos ao ligado, um teste
    // seguinte começaria calado por causa de um anterior.
    SoundService.definirSons(SoundService.sonsDeChamada, ativos: true);
    SoundService.definirSons(SoundService.sonsDeCompartilhamento, ativos: true);
  });

  Map<String, dynamic> configLida() =>
      jsonDecode(AppPaths.file('settings.json').readAsStringSync());

  test('ligar o RNNoise tira a supressão do WebRTC do caminho', () async {
    VoiceService.aplicarFiltroNeuralNative = (ligado) async => ligado;
    final state = AppState();
    expect(state.rnnoise, isFalse);

    final aplicado = await state.definirRnnoise(true);

    expect(aplicado, isTrue);
    expect(state.rnnoise, isTrue);
    // Dois filtros em série mastigam a fala: ligar um desliga o outro.
    expect(state.noiseSuppression, isFalse);
    expect(state.voiceService.rnnoise, isTrue);
    expect(configLida()['rnnoise'], true);
    expect(configLida()['noiseSuppression'], false);
  });

  test('máquina que recusa o filtro não deixa botão aceso mentindo', () async {
    VoiceService.aplicarFiltroNeuralNative = (ligado) async => false;
    final state = AppState();

    final aplicado = await state.definirRnnoise(true);

    expect(aplicado, isFalse);
    expect(state.rnnoise, isFalse);
    expect(state.rnnoiseAplicado, isFalse);
    // A supressão que existia antes continua onde estava: nada foi tirado do
    // ar em troca de um filtro que não entrou.
    expect(state.noiseSuppression, isTrue);
    expect(configLida()['rnnoise'], false);
  });

  test('a escolha de entrada e saída sobrevive ao fechar o aplicativo', () async {
    final state = AppState();

    await state.definirMicrofone('mic-usb');
    await state.definirSaidaDeAudio('fone-azul');
    await state.definirSupressaoDeRuido(false);
    await state.definirCancelamentoDeEco(false);
    await state.definirGanhoAutomatico(false);
    await state.definirFiltroPassaAltas(true);

    final salvas = configLida();
    expect(salvas['audioInputId'], 'mic-usb');
    expect(salvas['audioOutputId'], 'fone-azul');
    expect(salvas['noiseSuppression'], false);
    expect(salvas['echoCancellation'], false);
    expect(salvas['autoGainControl'], false);
    expect(salvas['highPassFilter'], true);
  });

  test('as quatro chaves de processamento chegam ao serviço que entra na call',
      () async {
    final state = AppState();

    // Ninguém pediu para mudar de comportamento no upgrade: os três que não
    // tinham UI começam como o caminho nativo já aplicava por padrão.
    expect(state.voiceService.cancelamentoDeEco, isTrue);
    expect(state.voiceService.ganhoAutomatico, isTrue);
    expect(state.voiceService.filtroPassaAltas, isFalse);

    await state.definirCancelamentoDeEco(false);
    expect(state.voiceService.cancelamentoDeEco, isFalse);

    await state.definirGanhoAutomatico(false);
    expect(state.voiceService.ganhoAutomatico, isFalse);

    await state.definirFiltroPassaAltas(true);
    expect(state.voiceService.filtroPassaAltas, isTrue);
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

  test('a câmera escolhida é gravada e espelhada no serviço da call', () async {
    final state = AppState();

    // Fora de uma chamada, escolher não liga captura nenhuma: devolve null
    // porque não houve recusa do Windows, apenas nada a republicar.
    expect(await state.definirCamera('cam-usb'), isNull);
    expect(state.cameraAtiva, isFalse);
    expect(state.voiceService.cameraId, 'cam-usb');
    expect(configLida()['cameraId'], 'cam-usb');

    await state.definirCamera(null);
    expect(state.voiceService.cameraId, isNull);
    expect(configLida()['cameraId'], isNull);
  });

  test('sem sala, o botão de câmera diz isso e não chama o plugin', () async {
    final service = VoiceService();

    expect(service.cameraAtiva, isFalse);
    expect(await service.alternarCamera(), contains('Entre na chamada'));
    expect(service.cameraDe('feps'), isNull);
  });

  test('a chave de som de chamada cala entrar e sair, e só isso', () async {
    final state = AppState();

    await state.definirSomDeChamada(false);
    expect(SoundService.somAtivo(SoundType.joinCall), isFalse);
    expect(SoundService.somAtivo(SoundType.leaveCall), isFalse);
    // A marcação não obedece a esta chave: seria um desligamento escondido.
    expect(SoundService.somAtivo(SoundType.mention), isTrue);

    await state.definirSomDeChamada(true);
    expect(SoundService.somAtivo(SoundType.joinCall), isTrue);
  });

  test('o compartilhamento de tela tem chave própria', () async {
    final state = AppState();

    await state.definirSomDeCompartilhamento(false);
    expect(SoundService.somAtivo(SoundType.screenShareStart), isFalse);
    expect(SoundService.somAtivo(SoundType.screenWatchStop), isFalse);
    expect(SoundService.somAtivo(SoundType.joinCall), isTrue);

    expect(configLida()['somDeCompartilhamento'], false);
  });
}
