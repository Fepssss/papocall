import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'livekit_token_service.dart';
import 'sound_service.dart';

/// Serviço de Voz e Transmissão de Tela em Tempo Real na Nuvem utilizando LiveKit Cloud.
/// Otimizado para estabilidade nativa no Windows, com DesktopCapturer e codecs de alta taxa de quadros.
class VoiceService {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  Room? get room => _room;

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

  void _log(String message) {
    debugPrint('[VoiceService] $message');
    try {
      final appData = Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final dir = Directory('$appData/PapoCall');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/papocall.log');
      file.writeAsStringSync('[${DateTime.now().toIso8601String()}] [Voice] $message\n', mode: FileMode.append);
    } catch (_) {}
  }

  Future<bool> joinVoice({
    required String roomName,
    required String identity,
    required String name,
  }) async {
    _log('Iniciando conexão com sala: $roomName para $name ($identity)');
    try {
      await leaveVoice();

      final token = LiveKitTokenService.generateToken(
        roomName: roomName,
        identity: identity,
        name: name,
      );
      _log('Token gerado para a sala $roomName');

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
        LiveKitTokenService.liveKitUrl,
        token,
        connectOptions: const ConnectOptions(
          autoSubscribe: true,
        ),
      ).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException('Tempo limite (8s) esgotado ao conectar ao LiveKit Cloud');
        },
      );

      _log('Conectado com sucesso ao LiveKit! Estado: ${_room?.connectionState}');
      _notifyParticipants();

      // Ativar microfone de forma assíncrona após a conexão estar estável
      _enableMicrophoneSafely();

      return true;
    } catch (e, stack) {
      _log('ERRO ao conectar ao LiveKit: $e\n$stack');
      await leaveVoice();
      return false;
    }
  }

  void _enableMicrophoneSafely() {
    Future.delayed(const Duration(milliseconds: 300), () async {
      if (_room == null || !isConnected) return;
      try {
        _log('Ativando microfone local...');
        final pub = await _room!.localParticipant
            ?.setMicrophoneEnabled(true)
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
      _activeSpeakersController.add(current);
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
      _screenShareTrackController.add(_screenShareTrack);
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
      _screenShareTrackController.add(_remoteScreenShareTrack);
    }
  }

  void _setupListeners() {
    _listener?.on<ActiveSpeakersChangedEvent>((event) {
      final speakerIdentities = event.speakers.map((s) => s.identity).toSet();
      _lastActiveSpeakers = speakerIdentities;
      _activeSpeakersController.add(speakerIdentities);
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
        _screenShareTrackController.add(activeScreenShareTrack);
      }
    });

    _listener?.on<TrackUnsubscribedEvent>((event) {
      _log('Track remoto desinscrito: ${event.track.sid}');
      if (event.publication.source == TrackSource.screenShareVideo) {
        if (_remoteScreenShareTrack?.sid == event.track.sid) {
          _remoteScreenShareTrack = null;
          _remoteScreenSharePresenter = null;
          SoundService.playScreenShareStop();
          _screenShareTrackController.add(activeScreenShareTrack);
        }
      }
    });

    _listener?.on<TrackMutedEvent>((event) {
      if (event.publication.source == TrackSource.screenShareVideo) {
        if (event.publication.sid == _remoteScreenShareTrack?.sid) {
          _remoteScreenShareTrack = null;
          _remoteScreenSharePresenter = null;
          SoundService.playScreenShareStop();
          _screenShareTrackController.add(activeScreenShareTrack);
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
    _participantsController.add(all);
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
    _screenShareTrackController.add(null);

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
      _room = null;
      _listener = null;
      _localParticipantListener = null;
      _lastActiveSpeakers.clear();
      _activeSpeakersController.add(<String>{});
      _participantsController.add(<Participant>[]);
      _log('Desconectado e limpo com sucesso.');
    }
  }

  void dispose() {
    _localParticipantListener?.dispose();
    leaveVoice();
    _screenShareTrackController.close();
    _activeSpeakersController.close();
    _participantsController.close();
  }
}
