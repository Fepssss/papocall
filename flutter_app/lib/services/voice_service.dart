import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import '../utils/app_log.dart';
import 'auth_service.dart';
import 'livekit_token_service.dart';
import 'sound_service.dart';

/// Quem está na sala de voz neste instante, do ponto de vista do LiveKit.
///
/// São dados simples, e não os objetos `Participant` do plugin: a UI não pode
/// segurar um objeto que o motor descarta quando a pessoa sai, e um teste de
/// widget não tem como fabricar um `Participant` verdadeiro.
///
/// Esta é a fonte do "quem está na call". A presença do MQTT diz em qual canal
/// cada um disse que está, mas é um segundo canal de informação sobre o mesmo
/// fato — e quando os dois discordavam, a tela mostrava só quem ela já conhecia
/// de casa: duas pessoas na mesma sala, cada uma vendo a si mesma.
class OcupanteDaSala {
  const OcupanteDaSala({
    required this.identity,
    required this.nome,
    required this.isLocal,
    required this.mudo,
    required this.falando,
    required this.temCamera,
  });

  /// Identidade no token, assinada pelo backend: `@username`.
  final String identity;

  /// Nome que a pessoa usa, vindo do próprio token.
  final String nome;

  final bool isLocal;
  final bool mudo;
  final bool falando;

  /// Se a pessoa está publicando vídeo agora. Vem da publicação da faixa no
  /// LiveKit, não de um botão apertado: é o único jeito de acertar também
  /// quando foi o outro lado que ligou ou desligou a dele.
  final bool temCamera;

  /// O `username` puro, para ir procurar o usuário no diretório local.
  String get username => identity.startsWith('@') ? identity.substring(1) : identity;
}

/// Serviço de Voz e Transmissão de Tela em Tempo Real na Nuvem utilizando LiveKit Cloud.
/// Otimizado para estabilidade nativa no Windows, com DesktopCapturer e codecs de alta taxa de quadros.
class VoiceService {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  Room? get room => _room;

  int currentPingMs = 0;
  Timer? _pingTimer;
  final StreamController<int> _pingController = StreamController<int>.broadcast();
  Stream<int> get pingStream => _pingController.stream;

  LocalVideoTrack? _screenShareTrack;
  LocalTrackPublication<LocalVideoTrack>? _screenSharePublication;
  LocalAudioTrack? _screenShareAudioTrack;
  LocalTrackPublication<LocalAudioTrack>? _screenShareAudioPublication;

  VideoTrack? _remoteScreenShareTrack;
  String? _remoteScreenSharePresenter;
  AudioTrack? _remoteScreenShareAudioTrack;

  /// Volume do áudio que vem junto da tela de outra pessoa, de 0 a 1. O
  /// [AppState] é dono do número persistido; aqui ele só é aplicado na faixa.
  double volumeDaLive = 0.8;

  /// Só existe controle de volume quando a transmissão tem áudio de verdade.
  bool get liveComAudio => _remoteScreenShareAudioTrack != null;

  void definirVolumeDaLive(double volume) {
    volumeDaLive = volume.clamp(0.0, 1.0).toDouble();
    _aplicarVolumeDaLive();
  }

  void _aplicarVolumeDaLive() {
    final faixa = _remoteScreenShareAudioTrack;
    if (faixa == null) return;
    // O caminho nativo do WebRTC pede o id da faixa e da conexão peer para
    // regular um áudio que vem de fora; é o que o próprio SDK usa.
    rtc.Helper.setVolume(volumeDaLive, faixa.mediaStreamTrack).catchError(
        (Object e) => _log('Não foi possível regular o volume da transmissão: $e'));
  }

  bool _ensurdecido = false;

  /// Volume escolhido para cada pessoa, de 0 a 1, e quem foi silenciada. A chave
  /// é o nome de usuário sem `@` e em minúsculas — a mesma forma que a interface
  /// usa para procurar alguém. O [AppState] é dono da cópia gravada em disco;
  /// aqui vivem só as regras em vigor na sala.
  final Map<String, double> volumesPorUsuario = {};
  final Set<String> silenciados = {};

  /// `@nome-da-identity` → `nome`. O LiveKit identifica todo mundo por
  /// `@username`, e comparar as duas formas sem normalizar é o que fazia o anel
  /// de fala não acender para ninguém.
  static String nomeDaIdentity(String identity) =>
      (identity.startsWith('@') ? identity.substring(1) : identity).toLowerCase();

  /// Aplica numa faixa de áudio as regras de quem a enviou: ensurdecer global,
  /// silenciar aquela pessoa, e o volume escolhido para ela.
  ///
  /// É um único ponto porque as três regras chegam em momentos diferentes — a
  /// pessoa mexe no controle, a faixa é assinada depois, a conexão cai e volta —
  /// e em qualquer um deles a faixa tem de acabar no mesmo estado.
  Future<void> _aplicarRegrasDeAudio(Participant dono, TrackPublication pub) async {
    final faixa = pub.track;
    if (faixa is! AudioTrack) return;
    final nome = nomeDaIdentity(dono.identity);
    if (_ensurdecido || silenciados.contains(nome)) {
      await faixa.disable();
      return;
    }
    await faixa.enable();
    // O áudio que vem junto da transmissão tem o controle dele na barra da live;
    // somar o volume do microfone daquela pessoa em cima deixaria um slider sem
    // efeito e o outro mentindo.
    if (pub.source == TrackSource.screenShareAudio) {
      _aplicarVolumeDaLive();
      return;
    }
    final volume = volumesPorUsuario[nome];
    if (volume == null) return;
    await rtc.Helper
        .setVolume(volume.clamp(0.0, 1.0).toDouble(), faixa.mediaStreamTrack)
        .catchError((Object e) =>
            _log('Não foi possível regular o volume de @$nome: $e'));
  }

  /// Regras de uma pessoa só, para quando o controle mexe no meio da call.
  Future<void> _reaplicarAudioDe(String username) async {
    final room = _room;
    if (room == null) return;
    final alvo = username.toLowerCase();
    for (final p in room.remoteParticipants.values) {
      if (nomeDaIdentity(p.identity) != alvo) continue;
      for (final pub in p.audioTrackPublications) {
        await _aplicarRegrasDeAudio(p, pub);
      }
    }
  }

  Future<void> definirVolumeDoUsuario(String username, double volume) async {
    final nome = username.toLowerCase();
    if (volume >= 1.0) {
      // Acima do cheio não há ganho a dar, e guardar 1.0 encheria o arquivo de
      // gente que a pessoa só encostou no controle.
      volumesPorUsuario.remove(nome);
    } else {
      volumesPorUsuario[nome] = volume.clamp(0.0, 1.0).toDouble();
    }
    await _reaplicarAudioDe(nome);
  }

  Future<void> definirSilenciado(String username, bool silenciado) async {
    final nome = username.toLowerCase();
    if (silenciado) {
      silenciados.add(nome);
    } else {
      silenciados.remove(nome);
    }
    await _reaplicarAudioDe(nome);
  }

  /// Se a pessoa está ensurdecida agora, independentemente de haver sala.
  bool get ensurdecido => _ensurdecido;

  /// Ensurdecer é parar de ouvir a sala, não é só emudecer o próprio microfone.
  ///
  /// Cada faixa de áudio remota é desligada na renderização local; as que ainda
  /// vão chegar entram desligadas pelo mesmo caminho, no evento de assinatura.
  /// Quem foi silenciada individualmente continua silenciada quando o
  /// ensurdecer global sai de cena.
  Future<void> definirEnsurdecido(bool valor) async {
    _ensurdecido = valor;
    final room = _room;
    if (room == null) return;
    var tocadas = 0;
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        if (pub.track == null) continue;
        tocadas++;
        await _aplicarRegrasDeAudio(p, pub);
      }
    }
    _log(valor
        ? 'Ensurdecido: $tocadas faixa(s) de áudio da sala desligadas.'
        : 'De volta ao áudio: $tocadas faixa(s) reativadas.');
  }

  bool get isScreenSharing => _screenSharePublication != null;
  VideoTrack? get activeScreenShareTrack => _screenShareTrack ?? _remoteScreenShareTrack;
  String? get activeScreenSharePresenter => isScreenSharing ? 'Você' : _remoteScreenSharePresenter;

  final StreamController<VideoTrack?> _screenShareTrackController =
      StreamController<VideoTrack?>.broadcast();
  Stream<VideoTrack?> get screenShareTrackStream => _screenShareTrackController.stream;

  final StreamController<Set<String>> _activeSpeakersController =
      StreamController<Set<String>>.broadcast();
  Stream<Set<String>> get activeSpeakersStream => _activeSpeakersController.stream;

  EventsListener<ParticipantEvent>? _localParticipantListener;
  Set<String> _lastActiveSpeakers = {};

  final StreamController<List<OcupanteDaSala>> _participantsController =
      StreamController<List<OcupanteDaSala>>.broadcast();
  Stream<List<OcupanteDaSala>> get participantsStream => _participantsController.stream;

  VoidCallback? onDisconnected;

  /// Escolhas feitas em Configurações > Voz e Áudio. `null` deixa o Windows
  /// decidir. O [AppState] é dono desses valores e os persiste; o serviço só
  /// sabe aplicá-los.
  String? entradaDeAudioId;
  String? saidaDeAudioId;
  bool supressaoDeRuido = true;
  bool cancelamentoDeEco = true;
  bool ganhoAutomatico = true;
  bool filtroPassaAltas = false;

  /// Cancelamento de ruído por rede neural (RNNoise) no caminho nativo.
  /// [rnnoiseAplicado] é o resultado da última vez que se tentou montar o
  /// filtro: `null` quer dizer que ainda não se tentou nesta execução, `false`
  /// que a máquina recusou, e aí a interface diz isso em vez de fingir um botão
  /// que não faz nada.
  bool rnnoise = false;
  bool? rnnoiseAplicado;

  /// Função, não chamada direta: em teste de unidade não existe canal de plugin,
  /// e tocar em `Helper` ali abriria uma invocação sem dono. Quem testa troca.
  static Future<bool> Function(bool) aplicarFiltroNeuralNative =
      rtc.Helper.setNeuralNoiseSuppression;

  /// Manda o estado de [rnnoise] ao nativo e registra a resposta.
  Future<bool> aplicarRnnoise() async {
    if (!kIsWeb && !Platform.isWindows) {
      rnnoiseAplicado = false;
      return false;
    }
    try {
      rnnoiseAplicado = await aplicarFiltroNeuralNative(rnnoise);
    } catch (e) {
      _log('Aviso ao ligar o filtro neural de ruído: $e');
      rnnoiseAplicado = false;
    }
    return rnnoiseAplicado!;
  }

  /// Os quatro abaixo são as únicas chaves de processamento que o caminho nativo
  /// do Windows lê (`flutter_media_stream.cc` resolve `echoCancellation`,
  /// `noiseSuppression`, `autoGainControl` e `highpassFilter`, inclusive dentro
  /// da lista `optional` que o LiveKit usa). Os modos, o `voiceIsolation` e o
  /// `typingNoiseDetection` que o `AudioCaptureOptions` também oferece são
  /// descartados no desktop — por isso não há UI para eles.
  AudioCaptureOptions get _opcoesDeCaptura => AudioCaptureOptions(
        deviceId: entradaDeAudioId,
        noiseSuppression: supressaoDeRuido,
        echoCancellation: cancelamentoDeEco,
        autoGainControl: ganhoAutomatico,
        highPassFilter: filtroPassaAltas,
      );

  /// Enumeração dos dispositivos. São funções, não métodos, porque em teste de
  /// unidade não existe plugin de áudio: tocar em `Hardware.instance` ali abrir
  /// uma chamada de método sem dono. Quem testa troca as funções.
  static Future<List<MediaDevice>> Function() listarEntradasDeAudio =
      () => Hardware.instance.audioInputs();

  static Future<List<MediaDevice>> Function() listarSaidasDeAudio =
      () => Hardware.instance.audioOutputs();

  /// Devolve o dispositivo com aquele id, ou null se ele não está plugado
  /// agora (fone desconectado, microfone USB arrancado no meio do dia).
  static MediaDevice? _porId(List<MediaDevice> dispositivos, String? id) {
    if (id == null) return null;
    for (final d in dispositivos) {
      if (d.deviceId == id) return d;
    }
    return null;
  }

  /// Aplica a escolha atual sem esperar pela próxima entrada em call.
  ///
  /// A saída é uma configuração global do motor WebRTC no Windows, então ela
  /// pega na hora. A entrada não: o microfone já publicado continua preso ao
  /// dispositivo antigo, então ele é publicado de novo quando está no ar.
  Future<void> aplicarDispositivosEscolhidos() async {
    try {
      final saida = _porId(await listarSaidasDeAudio(), saidaDeAudioId);
      if (saida != null) {
        await Hardware.instance.selectAudioOutput(saida);
        _log('Saída de áudio aplicada: ${saida.label}');
      }

      final entrada = _porId(await listarEntradasDeAudio(), entradaDeAudioId);
      final local = _room?.localParticipant;

      if (local != null && isConnected && local.isMicrophoneEnabled()) {
        final estavaMuda = local.isMuted;
        if (entrada != null) await _room!.setAudioInputDevice(entrada);
        await local.setMicrophoneEnabled(false);
        await local.setMicrophoneEnabled(true, audioCaptureOptions: _opcoesDeCaptura);
        // Republicar acorda o microfone: devolve o estado de mudo em que a
        // pessoa estava, senão o botão de mudo mente para ela.
        if (estavaMuda) await local.setMicrophoneEnabled(false);
        _log('Microfone republicado com as configurações atuais');
      } else if (entrada != null) {
        await Hardware.instance.selectAudioInput(entrada);
        _log('Entrada de áudio guardada para a próxima call: ${entrada.label}');
      }
    } catch (e) {
      _log('Aviso ao aplicar dispositivos de áudio: $e');
    }
  }

  void _safeAddScreenShareTrack(VideoTrack? track) {
    if (!_screenShareTrackController.isClosed) {
      _screenShareTrackController.add(track);
    }
  }

  void _safeAddActiveSpeakers(Set<String> speakers) {
    if (!_activeSpeakersController.isClosed) {
      _activeSpeakersController.add(speakers);
    }
  }

  void _safeAddParticipants(List<OcupanteDaSala> participants) {
    if (!_participantsController.isClosed) {
      _participantsController.add(participants);
    }
  }

  void _log(String message) {
    debugPrint('[VoiceService] $message');
    AppLog.write('Voice', message);
  }

  String? lastErrorMessage;

  Future<bool> joinVoice({
    required String roomName,
    required String accessToken,
    required Future<AuthSession?> Function() renewSession,
  }) async {
    lastErrorMessage = null;
    _log('Iniciando conexão com a sala: $roomName');
    try {
      await leaveVoice();

      // O token é emitido pelo backend: a identity vem do JWT da sessão,
      // nunca do cliente, e o segredo do LiveKit nunca sai do servidor.
      final grant = await LiveKitTokenService.requestGrant(
        roomName: roomName,
        accessToken: accessToken,
        renewSession: renewSession,
      );
      _log('Token recebido do backend para a sala $roomName');

      const roomOptions = RoomOptions(
        adaptiveStream: false,
        dynacast: false,
        defaultAudioPublishOptions: AudioPublishOptions(
          name: 'microphone',
          dtx: true,
        ),
      );

      _room = Room(roomOptions: roomOptions);
      _listener = _room!.createListener();

      _setupListeners();

      _log('Chamando room.connect...');
      await _room!.connect(
        grant.serverUrl,
        grant.token,
        connectOptions: const ConnectOptions(
          autoSubscribe: true,
        ),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Tempo limite (15s) esgotado ao conectar ao LiveKit Cloud');
        },
      );

      _log('Conectado com sucesso ao LiveKit! Estado: ${_room?.connectionState}');
      _notifyParticipants();
      _startPingMeasurement();

      // Ativar microfone de forma assíncrona após a conexão estar estável
      _enableMicrophoneSafely();

      return true;
    } catch (e, stack) {
      lastErrorMessage = e.toString().replaceFirst('Exception: ', '');
      _log('ERRO ao conectar ao LiveKit: $e\n$stack');
      await leaveVoice();
      return false;
    }
  }

  void _enableMicrophoneSafely() {
    Future.delayed(const Duration(milliseconds: 300), () async {
      if (_room == null || !isConnected) return;
      try {
        // Recomeçar uma call volta a usar o que a pessoa escolheu nas
        // configurações, não o padrão que o Windows impõe.
        await aplicarDispositivosEscolhidos();
        // O slot do filtro é do processamento de áudio do processo, não da sala:
        // sem re-aplicar aqui, uma escolha gravada antes de fechar o aplicativo
        // ficava desligada até a pessoa mexer no botão de novo.
        await aplicarRnnoise();
        _log('Ativando microfone local...');
        final pub = await _room!.localParticipant
            ?.setMicrophoneEnabled(true, audioCaptureOptions: _opcoesDeCaptura)
            .timeout(const Duration(seconds: 4));
        _log('Microfone local ativado com sucesso: ${pub?.sid}');
        _setupLocalParticipantListener();
        _notifyParticipants();
      } catch (e) {
        _log('Aviso ao ativar microfone: $e');
      }
    });
  }

  void _setupLocalParticipantListener() {
    _localParticipantListener?.dispose();
    final local = _room?.localParticipant;
    if (local == null) return;
    _localParticipantListener = local.createListener();
    _localParticipantListener?.on<SpeakingChangedEvent>((event) {
      _log('Local speaking mudou: ${event.speaking}');
      final current = Set<String>.from(_lastActiveSpeakers);
      if (event.speaking) {
        current.add(event.participant.identity);
      } else {
        current.remove(event.participant.identity);
      }
      _lastActiveSpeakers = current;
      _safeAddActiveSpeakers(current);
    });
  }

  /// Publica a tela escolhida. Largura, altura e quadros por segundo vêm do
  /// diálogo de seleção e viram as restrições de captura; o teto de bitrate
  /// acompanha os pixels, porque 60 FPS em 1080p com o bitrate de 720p produz
  /// uma transmissão borrada em vez de uma transmissão fluida.
  Future<bool> startScreenShare(
    String sourceId, {
    int width = 1920,
    int height = 1080,
    int fps = 30,
  }) async {
    if (_room == null || !isConnected) return false;
    try {
      _log('Iniciando compartilhamento de tela: $sourceId ${width}x$height@$fps');
      // Oito bits a cada cem pixels-quadrado: sai 5 Mbps em 1080p30 e
      // 2,2 Mbps em 720p30, que é o ritmo das transmissões do app até aqui.
      final maxBitrate = (width * height * fps ~/ 100 * 8).clamp(1500000, 8000000);
      final options = ScreenShareCaptureOptions(
        sourceId: sourceId,
        params: VideoParameters(
          dimensions: VideoDimensions(width, height),
          encoding: VideoEncoding(
            maxBitrate: maxBitrate,
            maxFramerate: fps,
          ),
        ),
      );

      _screenShareTrack = await _capturarFaixaDeVideo(options);
      _screenSharePublication = await _room!.localParticipant?.publishVideoTrack(_screenShareTrack!);
      _log('Tela publicada com sucesso: ${_screenSharePublication?.sid}');

      final audio = _screenShareAudioTrack;
      if (audio != null) {
        _screenShareAudioPublication =
            await _room!.localParticipant?.publishAudioTrack(audio);
        _log('Áudio da transmissão publicado: ${_screenShareAudioPublication?.sid}');
      }
      _safeAddScreenShareTrack(_screenShareTrack);
      return true;
    } catch (e, stack) {
      _log('Erro ao iniciar compartilhamento de tela: $e\n$stack');
      await stopScreenShare();
      return false;
    }
  }

  /// Captura a tela e aproveita o áudio que vier junto.
  ///
  /// O pedido é literal: `getDisplayMedia` recebe `audio: true` e o Windows
  /// devolve o que conseguir capturar. Se a captura inteira falhar por causa
  /// do áudio, tenta de novo só com o vídeo — ficar sem som na transmissão é
  /// decepcionante, ficar sem transmissão nenhuma é pior.
  Future<LocalVideoTrack> _capturarFaixaDeVideo(ScreenShareCaptureOptions options) async {
    try {
      final faixas = await LocalVideoTrack.createScreenShareTracksWithAudio(options);
      for (final faixa in faixas) {
        if (faixa is LocalAudioTrack) _screenShareAudioTrack = faixa;
      }
      _log('Captura de tela: vídeo${_screenShareAudioTrack != null ? ' + áudio do sistema' : ' (sem áudio do sistema)'}');
      return faixas.first as LocalVideoTrack;
    } catch (e) {
      _log('Captura com áudio recusada ($e); tentando só vídeo.');
      _screenShareAudioTrack = null;
      return LocalVideoTrack.createScreenShareTrack(options);
    }
  }

  Future<void> stopScreenShare() async {
    try {
      _log('Parando compartilhamento de tela...');
      if (_screenSharePublication != null) {
        await _room?.localParticipant?.removePublishedTrack(_screenSharePublication!.sid);
      }
      if (_screenShareAudioPublication != null) {
        await _room?.localParticipant
            ?.removePublishedTrack(_screenShareAudioPublication!.sid);
      }
      await _screenShareTrack?.stop();
      await _screenShareTrack?.dispose();
      await _screenShareAudioTrack?.stop();
      await _screenShareAudioTrack?.dispose();
    } catch (e) {
      _log('Erro ao parar compartilhamento de tela: $e');
    } finally {
      _screenShareTrack = null;
      _screenSharePublication = null;
      _screenShareAudioTrack = null;
      _screenShareAudioPublication = null;
      _safeAddScreenShareTrack(_remoteScreenShareTrack);
    }
  }

  // --- Câmera ---------------------------------------------------------------

  /// A câmera escolhida em Configurações > Voz e Áudio. `null` deixa o Windows
  /// decidir, como no microfone.
  String? cameraId;

  /// Enumerada por função, não por método, pelo mesmo motivo das entradas de
  /// áudio: em teste de unidade não existe canal de plugin.
  static Future<List<MediaDevice>> Function() listarCamaras =
      () => Hardware.instance.videoInputs();

  /// Por que a câmera não ligou, na palavra do Windows. É o que o botão mostra
  /// em vez de acender uma luz que não corresponde a nenhuma captura.
  String? _erroDaCamera;
  String? get erroDaCamera => _erroDaCamera;

  /// Ligada ou não, é o LiveKit que diz: a publicação da faixa é o fato, e um
  /// bool nosso ficaria desatualizado na primeira queda de conexão.
  bool get cameraAtiva => _room?.localParticipant?.isCameraEnabled() ?? false;

  /// As opções de captura da câmera.
  ///
  /// Não há reserva nenhuma para a câmera padrão quando a escolhida não está
  /// plugada: acender uma webcam que a pessoa não escolheu é justamente o que a
  /// tela de privacidade promete que não acontece. Ela falha, e o botão diz por
  /// quê.
  CameraCaptureOptions get _opcoesDeCamera => CameraCaptureOptions(
        deviceId: cameraId,
        maxFrameRate: 30,
      );

  /// Liga ou desliga a câmera da sala e devolve o motivo quando não conseguiu.
  ///
  /// O SDK faz publicar e retirar a faixa; aqui só fica a explicação do erro,
  /// traduzida para o que a pessoa pode fazer com ela.
  Future<String?> alternarCamera() async {
    final local = _room?.localParticipant;
    if (local == null || !isConnected) {
      return 'Entre na chamada de voz antes de ligar a câmera.';
    }
    if (cameraAtiva) {
      await local.setCameraEnabled(false);
      _erroDaCamera = null;
      _notifyParticipants();
      return null;
    }
    try {
      await local.setCameraEnabled(true, cameraCaptureOptions: _opcoesDeCamera)
          .timeout(const Duration(seconds: 12));
      _erroDaCamera = null;
      _log('Câmera publicada: ${cameraId ?? 'padrão do Windows'}');
    } catch (e) {
      _erroDaCamera = _explicarFalhaDeCamera(e);
      _log('Falha ao ligar a câmera: $e');
      _notifyParticipants();
      return _erroDaCamera;
    }
    _notifyParticipants();
    return null;
  }

  /// Os nomes que o `getUserMedia` do Windows devolve, ditos em português.
  static String _explicarFalhaDeCamera(Object e) {
    final texto = e.toString();
    if (texto.contains('ermission') || texto.contains('denied')) {
      return 'O Windows negou a câmera. Libere o acesso em Configurações > Privacidade > Câmera.';
    }
    if (texto.contains('NotFound')) {
      return 'Nenhuma câmera encontrada neste computador.';
    }
    if (texto.contains('NotReadable') || texto.contains('in use')) {
      return 'A câmera está ocupada ou não responde. Feche o programa que está usando ela.';
    }
    return 'Não foi possível ligar a câmera.';
  }

  /// A faixa de câmera de uma pessoa da sala, procurada pelo nome de usuário.
  ///
  /// É a única chave que a interface tem nas mãos: o cartão é um `UserModel`, e
  /// a identity do LiveKit é o `@username` que o backend assinou no token.
  /// Vale para a própria pessoa também — o vídeo local é a mesma faixa que os
  /// outros veem, só que já chega por aqui em vez de atravessar a rede.
  VideoTrack? cameraDe(String username) {
    final room = _room;
    if (username.isEmpty || room == null) return null;
    final alvo = username.toLowerCase();

    for (final p in <Participant?>[
      room.localParticipant,
      ...room.remoteParticipants.values,
    ]) {
      if (p == null) continue;
      final identidade = p.identity;
      final nome = identidade.startsWith('@')
          ? identidade.substring(1)
          : identidade;
      if (nome.toLowerCase() != alvo) continue;
      for (final pub in p.videoTrackPublications) {
        final track = pub.track;
        if (pub.source == TrackSource.camera && !pub.muted && track is VideoTrack) {
          return track;
        }
      }
    }
    return null;
  }

  void _setupListeners() {
    _listener?.on<ActiveSpeakersChangedEvent>((event) {
      final speakerIdentities = event.speakers.map((s) => s.identity).toSet();
      _lastActiveSpeakers = speakerIdentities;
      _safeAddActiveSpeakers(speakerIdentities);
      // O anel de quem está falando é desenhado na lista de ocupantes, então é
      // ela que precisa ser reemitida.
      _notifyParticipants();
    });

    // Renomeação de participante. O mudo chega pelos eventos de track,
    // tratados mais abaixo; sem este listener o apelido do amigo ficaria
    // congelado na versão que ele tinha ao entrar na sala.
    _listener?.on<ParticipantNameUpdatedEvent>((event) {
      _notifyParticipants();
    });

    _listener?.on<ParticipantConnectedEvent>((event) {
      _log('Participante conectado: ${event.participant.identity}');
      SoundService.playJoinCall();
      _notifyParticipants();
    });

    _listener?.on<ParticipantDisconnectedEvent>((event) {
      _log('Participante desconectado: ${event.participant.identity}');
      SoundService.playLeaveCall();
      _notifyParticipants();
    });

    _listener?.on<TrackSubscribedEvent>((event) {
      _log('Track remoto assinado: ${event.track.sid}, source: ${event.publication.source}');
      // O cartão de quem acabou de ligar a câmera só tem o que mostrar a
      // partir daqui — o `TrackPublished` chega antes da faixa existir de
      // fato, e sem reemitir a lista o vídeo nascia depois do desenho.
      _notifyParticipants();
      if (event.track is AudioTrack) {
        final faixa = event.track as AudioTrack;
        if (event.publication.source == TrackSource.screenShareAudio) {
          _remoteScreenShareAudioTrack = faixa;
          // O volume escolhido antes de a faixa existir precisa valer agora, e a
          // reemissão é o que faz o controle de volume aparecer na tela.
          _safeAddScreenShareTrack(activeScreenShareTrack);
        }
        // Quem está ensurdecido ou silenciou aquela pessoa não ouve ninguém que
        // chegar depois: a faixa já entra no estado certo, assinada agora.
        unawaited(_aplicarRegrasDeAudio(event.participant, event.publication));
        return;
      }
      if (event.track is VideoTrack && event.publication.source == TrackSource.screenShareVideo) {
        _remoteScreenShareTrack = event.track as VideoTrack;
        _remoteScreenSharePresenter = event.participant.name.isNotEmpty
            ? event.participant.name
            : event.participant.identity;
        SoundService.playScreenShareStart();
        _safeAddScreenShareTrack(activeScreenShareTrack);
      }
    });

    _listener?.on<TrackUnsubscribedEvent>((event) {
      _log('Track remoto desinscrito: ${event.track.sid}');
      _notifyParticipants();
      if (event.publication.source == TrackSource.screenShareAudio) {
        if (_remoteScreenShareAudioTrack?.sid == event.track.sid) {
          _remoteScreenShareAudioTrack = null;
        }
        return;
      }
      if (event.publication.source == TrackSource.screenShareVideo) {
        if (_remoteScreenShareTrack?.sid == event.track.sid) {
          _remoteScreenShareTrack = null;
          _remoteScreenSharePresenter = null;
          _remoteScreenShareAudioTrack = null;
          SoundService.playScreenShareStop();
          _safeAddScreenShareTrack(activeScreenShareTrack);
        }
      }
    });

    _listener?.on<TrackMutedEvent>((event) {
      _notifyParticipants();
      if (event.publication.source == TrackSource.screenShareVideo) {
        if (event.publication.sid == _remoteScreenShareTrack?.sid) {
          _remoteScreenShareTrack = null;
          _remoteScreenSharePresenter = null;
          _remoteScreenShareAudioTrack = null;
          SoundService.playScreenShareStop();
          _safeAddScreenShareTrack(activeScreenShareTrack);
        }
      }
    });

    _listener?.on<TrackUnmutedEvent>((event) {
      _notifyParticipants();
    });

    _listener?.on<TrackPublishedEvent>((event) {
      _notifyParticipants();
    });

    _listener?.on<TrackUnpublishedEvent>((event) {
      _notifyParticipants();
    });

    _listener?.on<RoomDisconnectedEvent>((event) {
      _log('Sala desconectada: ${event.reason}');
      _notifyParticipants();
      onDisconnected?.call();
    });
  }

  /// Lista quem está na sala agora, dita pelo LiveKit e não pela presença do
  /// MQTT: é a única fonte que sabe de fato quem entrou e saiu da sala de voz.
  void _notifyParticipants() {
    final room = _room;
    if (room == null) return;
    final lista = <OcupanteDaSala>[];

    void adicionar(Participant p, {required bool local}) {
      lista.add(OcupanteDaSala(
        identity: p.identity,
        nome: p.name,
        isLocal: local,
        mudo: !p.isMicrophoneEnabled(),
        falando: _lastActiveSpeakers.contains(p.identity),
        temCamera: p.isCameraEnabled(),
      ));
    }

    final local = room.localParticipant;
    if (local != null) adicionar(local, local: true);
    for (final p in room.remoteParticipants.values) {
      adicionar(p, local: false);
    }
    _safeAddParticipants(lista);
  }

  Future<void> setMuted(bool muted) async {
    try {
      _log('Alterando mudo para: $muted');
      await _room?.localParticipant
          ?.setMicrophoneEnabled(!muted)
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      _log('Erro ao alterar status de mudo: $e');
    }
  }

  Future<void> leaveVoice() async {
    _log('Desconectando voz...');
    try {
      // Desligar a câmera é o que apaga a luz do aparelho. Sair da sala por si
      // só derruba a conexão, e uma webcam acesa depois do "desconectado" não
      // é detalhe cosmético: é o microfone/lente da pessoa entregues a um
      // processo que já não tem chamada nenhuma.
      await _room?.localParticipant?.setCameraEnabled(false);
      if (_screenSharePublication != null) {
        await _room?.localParticipant?.removePublishedTrack(_screenSharePublication!.sid);
      }
      if (_screenShareAudioPublication != null) {
        await _room?.localParticipant
            ?.removePublishedTrack(_screenShareAudioPublication!.sid);
      }
      await _screenShareTrack?.stop();
      await _screenShareTrack?.dispose();
      await _screenShareAudioTrack?.stop();
      await _screenShareAudioTrack?.dispose();
    } catch (_) {}
    _screenShareTrack = null;
    _screenSharePublication = null;
    _screenShareAudioTrack = null;
    _screenShareAudioPublication = null;
    _remoteScreenShareTrack = null;
    _remoteScreenSharePresenter = null;
    _remoteScreenShareAudioTrack = null;
    _erroDaCamera = null;
    _safeAddScreenShareTrack(null);

    try {
      _localParticipantListener?.dispose();
      _localParticipantListener = null;
      _lastActiveSpeakers.clear();
      _listener?.dispose();
      _listener = null;
      if (_room != null) {
        await _room!.disconnect().timeout(const Duration(seconds: 3));
        await _room!.dispose().timeout(const Duration(seconds: 3));
      }
    } catch (e) {
      _log('Erro ao desconectar voz: $e');
    } finally {
      _stopPingMeasurement();
      _room = null;
      _listener = null;
      _localParticipantListener = null;
      _lastActiveSpeakers.clear();
      _safeAddActiveSpeakers(<String>{});
      _safeAddParticipants(<OcupanteDaSala>[]);
      _log('Desconectado e limpo com sucesso.');
    }
  }

  void _startPingMeasurement() {
    _pingTimer?.cancel();
    _measurePing();
    _pingTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (isConnected) {
        _measurePing();
      } else {
        _stopPingMeasurement();
      }
    });
  }

  void _stopPingMeasurement() {
    _pingTimer?.cancel();
    _pingTimer = null;
    currentPingMs = 0;
    if (!_pingController.isClosed) {
      _pingController.add(0);
    }
  }

  Future<void> _measurePing() async {
    try {
      final sw = Stopwatch()..start();
      final client = http.Client();
      try {
        final res = await client
            .head(Uri.parse('https://papocall-9lgrt380.livekit.cloud'))
            .timeout(const Duration(seconds: 2));
        sw.stop();
        if (res.statusCode != 0) {
          currentPingMs = sw.elapsedMilliseconds;
        }
      } finally {
        client.close();
      }
    } catch (_) {
      try {
        final sw = Stopwatch()..start();
        final res = await http
            .get(Uri.parse('${AuthService.apiBaseUrl}/health'))
            .timeout(const Duration(seconds: 2));
        sw.stop();
        if (res.statusCode == 200) {
          currentPingMs = sw.elapsedMilliseconds;
        }
      } catch (_) {}
    }

    if (!_pingController.isClosed && isConnected) {
      _pingController.add(currentPingMs);
    }
  }

  void dispose() {
    _stopPingMeasurement();
    _localParticipantListener?.dispose();
    _localParticipantListener = null;
    _listener?.dispose();
    _listener = null;
    leaveVoice();
    _pingController.close();
    _screenShareTrackController.close();
    _activeSpeakersController.close();
    _participantsController.close();
  }
}
