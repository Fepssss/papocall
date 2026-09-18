import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;
import '../models/channel.dart';
import '../models/chat_message.dart';
import '../models/server.dart';
import '../models/user_model.dart';
import '../services/mqtt_service.dart';
import '../services/voice_service.dart';
import '../services/sound_service.dart';
import '../services/auth_service.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final MqttService _mqtt = MqttService();
  final VoiceService _voiceService = VoiceService();
  final Uuid _uuid = const Uuid();

  VoiceService get voiceService => _voiceService;

  late UserModel currentUser;
  bool isAuthenticated = false;
  bool isCheckingAuth = true;
  AuthSession? currentSession;

  List<Server> servers = [];
  String activeServerId = 'server-default';
  String activeChannelId = 'c-geral';

  String? connectedVoiceChannelId;
  bool isConnectingVoice = false;
  VideoTrack? activeScreenShareTrack;
  String? activeScreenSharePresenter;
  bool isWatchingScreenShare = true;
  bool get isScreenSharing => _voiceService.isScreenSharing;

  // Gerenciamento de Foco e Otimização de Renderização de Live
  bool isWindowFocused = true;
  bool forceRenderOwnStream = false;

  // Navegação: Página Inicial do App (Tela Cheia)
  bool isHomePageActive = false;

  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, UserModel> _onlineUsers = {};
  Timer? _heartbeatTimer;
  StreamSubscription? _mqttSubscription;

  AppState() {
    currentUser = UserModel(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      username: 'Usuário',
      status: UserStatus.online,
    );
    WidgetsBinding.instance.addObserver(this);
    _initVoiceListeners();
    _initDefaultData();
    _initStorageAndNetwork();
  }

  void setWindowFocused(bool focused) {
    if (isWindowFocused != focused) {
      isWindowFocused = focused;
      notifyListeners();
    }
  }

  void toggleForceRenderOwnStream() {
    forceRenderOwnStream = !forceRenderOwnStream;
    notifyListeners();
  }

  void openHomePage() {
    if (!isHomePageActive) {
      isHomePageActive = true;
      notifyListeners();
    }
  }

  void closeHomePage() {
    if (isHomePageActive) {
      isHomePageActive = false;
      notifyListeners();
    }
  }

  void toggleHomePage() {
    isHomePageActive = !isHomePageActive;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No Windows:
    // resumed: Janela do PapoCall está ativa/em destaque (focada)
    // inactive / hidden / paused: Usuário trocou de aplicativo ou minimizou
    final focused = (state == AppLifecycleState.resumed);
    if (isWindowFocused != focused) {
      isWindowFocused = focused;
      notifyListeners();
    }
  }

  /// Regra de Otimização de Performance para Live:
  /// - Lives de outras pessoas: SEMPRE renderizam.
  /// - Live própria (streamer): só renderiza na UI se o app estiver em destaque
  ///   (focado) ou se o usuário optar por forçar a prévia.
  bool get shouldRenderScreenShare {
    if (activeScreenShareTrack == null) return false;

    // Transmissões de terceiros sempre são renderizadas
    if (!isScreenSharing) return true;

    // Transmissão própria: suspende a renderização quando o app não estiver em destaque
    return isWindowFocused || forceRenderOwnStream;
  }

  void _initVoiceListeners() {
    _voiceService.activeSpeakersStream.listen((speakers) {
      final userChanged = currentUser.isSpeaking != speakers.contains(currentUser.id);
      currentUser.isSpeaking = speakers.contains(currentUser.id);

      var remoteChanged = false;
      for (final user in _onlineUsers.values) {
        final isSpk = speakers.contains(user.id);
        if (user.isSpeaking != isSpk) {
          user.isSpeaking = isSpk;
          remoteChanged = true;
        }
      }

      if (userChanged || remoteChanged) {
        notifyListeners();
      }
    });

    _voiceService.screenShareTrackStream.listen((track) {
      final wasActive = activeScreenShareTrack != null;
      activeScreenShareTrack = track;
      activeScreenSharePresenter = _voiceService.activeScreenSharePresenter;
      currentUser.isScreenSharing = _voiceService.isScreenSharing;
      if (!wasActive && track != null) {
        isWatchingScreenShare = true;
      }
      _sendPresence();
      notifyListeners();
    });

    _voiceService.onDisconnected = () {
      debugPrint('[AppState] LiveKit reportou desconexao da sala de voz.');
      disconnectVoice();
    };
  }

  Server? get activeServer => servers.firstWhere(
        (s) => s.id == activeServerId,
        orElse: () => servers.first,
      );

  Channel? get activeChannel {
    final srv = activeServer;
    if (srv == null) return null;
    return srv.channels.firstWhere(
      (c) => c.id == activeChannelId,
      orElse: () => srv.channels.first,
    );
  }

  List<ChatMessage> get activeMessages => _messages[activeChannelId] ?? [];
  List<UserModel> get onlineMembers => _onlineUsers.values.toList();

  void _initDefaultData() {
    final defaultServer = Server(
      id: 'server-default',
      name: 'PapoCall',
      inviteCode: 'papocall-oficial',
      channels: [
        Channel(id: 'c-geral', name: 'geral', type: ChannelType.text, topic: 'Canal de texto principal'),
        Channel(id: 'c-avisos', name: 'avisos', type: ChannelType.text, topic: 'Comunicados e novidades'),
        Channel(id: 'c-memes', name: 'memes', type: ChannelType.text, topic: 'Memes e coisas divertidas'),
        Channel(id: 'v-geral', name: 'Sala Geral', type: ChannelType.voice, userLimit: 15),
        Channel(id: 'v-jogos', name: 'Sala de Jogos', type: ChannelType.voice, userLimit: 6),
        Channel(id: 'v-batepapo', name: 'Bate-Papo Livre', type: ChannelType.voice, userLimit: 10),
      ],
    );
    servers = [defaultServer];

    _messages['c-geral'] = [
      ChatMessage(
        id: 'msg-welcome',
        authorId: 'sys',
        author: 'Sistema PapoCall',
        text: 'Bem-vindo ao aplicativo nativo PapoCall! Comunicação rápida, estável e sóbria.',
        timestamp: 'Hoje às 12:00',
        isSystem: true,
      ),
    ];
  }

  File _getAppFile(String fileName) {
    final appData = Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dir = Directory('$appData/PapoCall');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File('${dir.path}/$fileName');
  }

  File _getSettingsFile() => _getAppFile('settings.json');
  File _getChatHistoryFile() => _getAppFile('chat_history.json');
  File _getDraftsFile() => _getAppFile('drafts.json');

  Future<void> _saveSettings() async {
    try {
      final file = _getSettingsFile();
      final data = {
        'user_id': currentUser.id,
        'username': currentUser.username,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Erro ao salvar configurações: $e');
    }
  }

  final Map<String, String> _drafts = {};
  String getDraft(String channelId) => _drafts[channelId] ?? '';
  void setDraft(String channelId, String text) {
    _drafts[channelId] = text;
    _saveDrafts();
  }
  void clearDraft(String channelId) {
    _drafts.remove(channelId);
    _saveDrafts();
  }

  Future<void> _saveDrafts() async {
    try {
      final file = _getDraftsFile();
      await file.writeAsString(jsonEncode(_drafts));
    } catch (e) {
      debugPrint('Erro ao salvar rascunhos: $e');
    }
  }

  Future<void> _loadDrafts() async {
    try {
      final file = _getDraftsFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final Map<String, dynamic> raw = jsonDecode(content);
          _drafts.clear();
          for (final entry in raw.entries) {
            _drafts[entry.key] = entry.value.toString();
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar rascunhos: $e');
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      final file = _getChatHistoryFile();
      final Map<String, dynamic> serialized = {};
      for (final entry in _messages.entries) {
        serialized[entry.key] = entry.value.map((m) => m.toJson()).toList();
      }
      await file.writeAsString(jsonEncode(serialized));
    } catch (e) {
      debugPrint('Erro ao salvar histórico de chat: $e');
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final file = _getChatHistoryFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final Map<String, dynamic> raw = jsonDecode(content);
          for (final entry in raw.entries) {
            final list = (entry.value as List)
                .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
                .toList();
            if (list.isNotEmpty) {
              _messages[entry.key] = list;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar histórico de chat: $e');
    }
  }

  Future<void> _initStorageAndNetwork() async {
    try {
      final savedSession = await AuthService.loadSession();
      if (savedSession != null) {
        currentSession = savedSession;
        currentUser = savedSession.user.toUserModel();
        isAuthenticated = true;
      } else {
        isAuthenticated = false;
      }
    } catch (e) {
      debugPrint('Erro ao carregar sessão: $e');
      isAuthenticated = false;
    }

    try {
      final file = _getSettingsFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final savedUsername = data['username'] as String?;
        if (savedUsername != null && savedUsername.isNotEmpty && !isAuthenticated) {
          currentUser.username = savedUsername;
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar configurações: $e');
    }

    await _loadChatHistory();
    await _loadDrafts();

    isCheckingAuth = false;
    notifyListeners();

    if (isAuthenticated) {
      await _startNetwork();
    }
  }

  Future<void> _startNetwork() async {
    try {
      _stopNetwork();
      final clientId = 'papocall_${currentUser.id}_${DateTime.now().millisecondsSinceEpoch % 10000}';
      debugPrint('[AppState] Conectando rede MQTT como $clientId...');
      await _mqtt.connect(clientId);
      _mqtt.subscribe('papocall/v1/srv/+/chat');
      _mqtt.subscribe('papocall/v1/global/presence');

      _mqttSubscription = _mqtt.messageStream.listen(_handleIncomingNetworkData);

      _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) => _sendPresence());
      _sendPresence();
    } catch (e) {
      debugPrint('Erro ao inicializar rede: $e');
    }
  }

  void _stopNetwork() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _mqttSubscription?.cancel();
    _mqttSubscription = null;
    try {
      _mqtt.disconnect();
    } catch (_) {}
  }

  Future<void> login({required String identifier, required String password}) async {
    final session = await AuthService.login(identifier: identifier, password: password);
    currentSession = session;
    currentUser = session.user.toUserModel();
    isAuthenticated = true;
    await _saveSettings();
    await _startNetwork();
    notifyListeners();
  }

  Future<void> register({
    required String displayName,
    required String username,
    required String email,
    required String password,
  }) async {
    final session = await AuthService.register(
      displayName: displayName,
      username: username,
      email: email,
      password: password,
    );
    currentSession = session;
    currentUser = session.user.toUserModel();
    isAuthenticated = true;
    await _saveSettings();
    await _startNetwork();
    notifyListeners();
  }

  Future<void> logout() async {
    if (connectedVoiceChannelId != null) {
      await disconnectVoice();
    }
    await AuthService.clearSession();
    _stopNetwork();
    currentSession = null;
    currentUser = UserModel(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      username: 'Usuário',
      status: UserStatus.offline,
    );
    isAuthenticated = false;
    notifyListeners();
  }

  void _sendPresence() {
    if (!_mqtt.isConnected) return;
    final presenceData = {
      'action': 'presence',
      'userId': currentUser.id,
      'username': currentUser.username,
      'avatar': currentUser.avatar,
      'status': currentUser.status.name,
      'isMuted': currentUser.isMuted,
      'isDeafened': currentUser.isDeafened,
      'isScreenSharing': currentUser.isScreenSharing,
      'voiceChannelId': connectedVoiceChannelId,
      'voiceServerId': activeServerId,
      'servers': servers.map((s) => s.id).toList(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    _mqtt.publish('papocall/v1/global/presence', presenceData);
  }

  void _handleIncomingNetworkData(Map<String, dynamic> data) {
    final action = data['action'] as String?;
    if (action == 'chat_message') {
      final channelId = data['channelId'] as String?;
      if (channelId != null) {
        final newMsg = ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
        _messages.putIfAbsent(channelId, () => []);
        if (!_messages[channelId]!.any((m) => m.id == newMsg.id)) {
          _messages[channelId]!.add(newMsg);
          _saveChatHistory();
          notifyListeners();
        }
      }
    } else if (action == 'presence') {
      final uid = data['userId'] as String?;
      if (uid != null && uid != currentUser.id) {
        _onlineUsers[uid] = UserModel(
          id: uid,
          username: data['username'] as String? ?? 'Amigo',
          avatar: data['avatar'] as String? ?? '',
          status: UserStatus.values.firstWhere(
            (s) => s.name == data['status'],
            orElse: () => UserStatus.online,
          ),
          isMuted: data['isMuted'] as bool? ?? false,
          isDeafened: data['isDeafened'] as bool? ?? false,
          isScreenSharing: data['isScreenSharing'] as bool? ?? false,
          currentVoiceChannelId: data['voiceChannelId'] as String?,
          currentVoiceServerId: data['voiceServerId'] as String?,
        );
        notifyListeners();
      }
    }
  }

  void selectServer(String serverId) {
    isHomePageActive = false;
    activeServerId = serverId;
    final srv = activeServer;
    if (srv != null && srv.channels.isNotEmpty) {
      activeChannelId = srv.channels.first.id;
    }
    notifyListeners();
  }

  void selectChannel(String channelId) {
    activeChannelId = channelId;
    notifyListeners();
  }

  void sendMessage(String text, {String? gifUrl, String? replyToAuthor, String? replyToText}) {
    if (text.trim().isEmpty && gifUrl == null) return;

    final newMsg = ChatMessage(
      id: _uuid.v4(),
      authorId: currentUser.id,
      author: currentUser.username,
      authorAvatar: currentUser.avatar,
      text: text.trim(),
      timestamp: 'Hoje às ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      gifUrl: gifUrl,
      replyToAuthor: replyToAuthor,
      replyToText: replyToText,
    );

    _messages.putIfAbsent(activeChannelId, () => []);
    _messages[activeChannelId]!.add(newMsg);
    clearDraft(activeChannelId);
    _saveChatHistory();
    notifyListeners();

    final chatPayload = {
      'action': 'chat_message',
      'channelId': activeChannelId,
      'message': newMsg.toJson(),
    };
    _mqtt.publish('papocall/v1/srv/$activeServerId/chat', chatPayload);
  }

  void toggleMute() {
    currentUser.isMuted = !currentUser.isMuted;
    _voiceService.setMuted(currentUser.isMuted);
    _sendPresence();
    notifyListeners();
  }

  void toggleDeafen() {
    currentUser.isDeafened = !currentUser.isDeafened;
    if (currentUser.isDeafened) {
      currentUser.isMuted = true;
      _voiceService.setMuted(true);
    } else {
      _voiceService.setMuted(currentUser.isMuted);
    }
    _sendPresence();
    notifyListeners();
  }

  void setStatus(UserStatus newStatus) {
    currentUser.status = newStatus;
    _sendPresence();
    notifyListeners();
  }

  void setUsername(String newName) async {
    if (newName.trim().isEmpty) return;
    currentUser.username = newName.trim();
    await _saveSettings();
    _sendPresence();
    notifyListeners();
  }

  Future<void> connectVoice(String channelId) async {
    if (isConnectingVoice) return;
    if (connectedVoiceChannelId == channelId) return;

    isConnectingVoice = true;
    notifyListeners();

    try {
      // Identidade única e determinística por sessão para evitar colisão DUPLICATE_IDENTITY no LiveKit
      final randomSuffix = (DateTime.now().millisecondsSinceEpoch % 100000).toString().padLeft(5, '0');
      final uniqueIdentity = '${currentUser.username}_${currentUser.id}_$randomSuffix';

      final success = await _voiceService.joinVoice(
        roomName: channelId,
        identity: uniqueIdentity,
        name: currentUser.username,
      );

      if (success) {
        connectedVoiceChannelId = channelId;
        currentUser.currentVoiceChannelId = channelId;
        SoundService.playJoinCall();
      } else {
        connectedVoiceChannelId = null;
        currentUser.currentVoiceChannelId = null;
      }
    } catch (e) {
      debugPrint('Erro ao conectar no LiveKit para o canal $channelId: $e');
      connectedVoiceChannelId = null;
      currentUser.currentVoiceChannelId = null;
    } finally {
      isConnectingVoice = false;
      _sendPresence();
      notifyListeners();
    }
  }

  void setWatchingScreenShare(bool watching) {
    if (isWatchingScreenShare == watching) return;
    isWatchingScreenShare = watching;
    if (watching) {
      SoundService.playScreenWatchStart();
    } else {
      SoundService.playScreenWatchStop();
    }
    notifyListeners();
  }

  Future<bool> startScreenShare(String sourceId) async {
    final ok = await _voiceService.startScreenShare(sourceId);
    if (ok) {
      currentUser.isScreenSharing = true;
      activeScreenShareTrack = _voiceService.activeScreenShareTrack;
      activeScreenSharePresenter = 'Você';
      isWatchingScreenShare = true;
      SoundService.playScreenShareStart();
      _sendPresence();
      notifyListeners();
    }
    return ok;
  }

  Future<void> stopScreenShare() async {
    await _voiceService.stopScreenShare();
    currentUser.isScreenSharing = false;
    activeScreenShareTrack = _voiceService.activeScreenShareTrack;
    activeScreenSharePresenter = _voiceService.activeScreenSharePresenter;
    SoundService.playScreenShareStop();
    _sendPresence();
    notifyListeners();
  }

  Future<void> disconnectVoice() async {
    isConnectingVoice = false;
    connectedVoiceChannelId = null;
    currentUser.currentVoiceChannelId = null;
    currentUser.isSpeaking = false;
    currentUser.isScreenSharing = false;
    SoundService.playLeaveCall();
    await _voiceService.stopScreenShare();
    await _voiceService.leaveVoice();
    activeScreenShareTrack = null;
    activeScreenSharePresenter = null;
    _sendPresence();
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _voiceService.dispose();
    _mqtt.disconnect();
    super.dispose();
  }
}
