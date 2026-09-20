import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import '../utils/app_log.dart';
import 'auth_service.dart';
import 'livekit_token_service.dart';
import 'sound_service.dart';

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

  VideoTrack? _remoteScreenShareTrack;
  String? _remoteScreenSharePresenter;

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

  final StreamController<List<Participant>> _participantsController =
      StreamController<List<Participant>>.broadcast();
  Stream<List<Participant>> get participantsStream => _participantsController.stream;

  VoidCallback? onDisconnected;

  /// Escolhas feitas em Configurações > Voz e Áudio. `null` deixa o Windows
  /// decidir. O [AppState] é dono desses valores e os persiste; o serviço só
  /// sabe aplicá-los.
  String? entradaDeAudioId;
  String? saidaDeAudioId;
  bool supressaoDeRuido = true;

  AudioCaptureOptions get _opcoesDeCaptura => AudioCaptureOptions(
        deviceId: entradaDeAudioId,
        noiseSuppression: supressaoDeRuido,
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

  void _safeAddParticipants(List<Participant> participants) {
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

  Future<bool> startScreenShare(String sourceId) async {
    if (_room == null || !isConnected) return false;
    try {
      _log('Iniciando compartilhamento de tela com sourceId: $sourceId');
      final options = ScreenShareCaptureOptions(
        sourceId: sourceId,
        params: VideoParametersPresets.screenShareH1080FPS30,
      );

      _screenShareTrack = await LocalVideoTrack.createScreenShareTrack(options);
      _screenSharePublication = await _room!.localParticipant?.publishVideoTrack(_screenShareTrack!);
      _log('Tela publicada com sucesso: ${_screenSharePublication?.sid}');
      _safeAddScreenShareTrack(_screenShareTrack);
      return true;
    } catch (e, stack) {
      _log('Erro ao iniciar compartilhamento de tela: $e\n$stack');
      await stopScreenShare();
      return false;
    }
  }

  Future<void> stopScreenShare() async {
    try {
      _log('Parando compartilhamento de tela...');
      if (_screenSharePublication != null) {
        await _room?.localParticipant?.removePublishedTrack(_screenSharePublication!.sid);
      }
      await _screenShareTrack?.stop();
      await _screenShareTrack?.dispose();
    } catch (e) {
      _log('Erro ao parar compartilhamento de tela: $e');
    } finally {
      _screenShareTrack = null;
      _screenSharePublication = null;
      _safeAddScreenShareTrack(_remoteScreenShareTrack);
    }
  }

  void _setupListeners() {
    _listener?.on<ActiveSpeakersChangedEvent>((event) {
      final speakerIdentities = event.speakers.map((s) => s.identity).toSet();
      _lastActiveSpeakers = speakerIdentities;
      _safeAddActiveSpeakers(speakerIdentities);
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
      if (event.publication.source == TrackSource.screenShareVideo) {
        if (_remoteScreenShareTrack?.sid == event.track.sid) {
          _remoteScreenShareTrack = null;
          _remoteScreenSharePresenter = null;
          SoundService.playScreenShareStop();
          _safeAddScreenShareTrack(activeScreenShareTrack);
        }
      }
    });

    _listener?.on<TrackMutedEvent>((event) {
      if (event.publication.source == TrackSource.screenShareVideo) {
        if (event.publication.sid == _remoteScreenShareTrack?.sid) {
          _remoteScreenShareTrack = null;
          _remoteScreenSharePresenter = null;
          SoundService.playScreenShareStop();
          _safeAddScreenShareTrack(activeScreenShareTrack);
        }
      }
    });

    _listener?.on<RoomDisconnectedEvent>((event) {
      _log('Sala desconectada: ${event.reason}');
      _notifyParticipants();
      onDisconnected?.call();
    });
  }

  void _notifyParticipants() {
    if (_room == null) return;
    final all = <Participant>[];
    if (_room!.localParticipant != null) {
      all.add(_room!.localParticipant!);
    }
    all.addAll(_room!.remoteParticipants.values);
    _safeAddParticipants(all);
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
      if (_screenSharePublication != null) {
        await _room?.localParticipant?.removePublishedTrack(_screenSharePublication!.sid);
      }
      await _screenShareTrack?.stop();
      await _screenShareTrack?.dispose();
    } catch (_) {}
    _screenShareTrack = null;
    _screenSharePublication = null;
    _remoteScreenShareTrack = null;
    _remoteScreenSharePresenter = null;
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
      _safeAddParticipants(<Participant>[]);
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
