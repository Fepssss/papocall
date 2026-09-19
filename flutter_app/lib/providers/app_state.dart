import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;
import '../models/channel.dart';
import '../models/chat_message.dart';
import '../models/friend_request.dart';
import '../models/server.dart';
import '../models/user_model.dart';
import '../services/mqtt_service.dart';
import '../services/server_crypto.dart';
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
  String activeServerId = '';
  String activeChannelId = '';

  String? connectedVoiceChannelId;
  bool isConnectingVoice = false;
  VideoTrack? activeScreenShareTrack;
  String? activeScreenSharePresenter;
  bool isWatchingScreenShare = true;
  bool get isScreenSharing => _voiceService.isScreenSharing;

  // Gerenciamento de Foco e Otimização de Renderização de Live
  bool isWindowFocused = true;
  bool forceRenderOwnStream = false;

  // Navegação: Página Inicial do App (Tela Cheia) - por padrão ativa se não há servidores
  bool isHomePageActive = true;

  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, UserModel> _onlineUsers = {};
  final Map<String, UserModel> _knownUsers = {};
  final Map<String, int> _lastSeen = {};
  List<UserModel> friends = [];
  List<FriendRequest> friendRequests = [];
  Timer? _heartbeatTimer;
  StreamSubscription? _mqttSubscription;
  StreamSubscription? _pingSubscription;
  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  AppState() {
    currentUser = UserModel(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      username: 'usuario',
      displayName: 'Usuário',
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
    if (servers.isEmpty) return;
    if (isHomePageActive) {
      isHomePageActive = false;
      notifyListeners();
    }
  }

  void toggleHomePage() {
    if (servers.isEmpty) {
      isHomePageActive = true;
      notifyListeners();
      return;
    }
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

    _pingSubscription?.cancel();
    _pingSubscription = _voiceService.pingStream.listen((_) {
      if (!_isDisposed) {
        notifyListeners();
      }
    });

    _voiceService.onDisconnected = () {
      debugPrint('[AppState] LiveKit reportou desconexao da sala de voz.');
      disconnectVoice();
    };
  }

  int get voicePingMs => _voiceService.currentPingMs;

  String get voiceConnectionQuality {
    if (voicePingMs <= 0) return 'Conectando...';
    if (voicePingMs < 60) return 'Excelente (< 60ms)';
    if (voicePingMs < 120) return 'Boa (< 120ms)';
    return 'Oscilando (> 120ms)';
  }

  Server? get activeServer {
    if (servers.isEmpty) return null;
    return servers.firstWhere(
      (s) => s.id == activeServerId,
      orElse: () => servers.first,
    );
  }

  Channel? get activeChannel {
    final srv = activeServer;
    if (srv == null || srv.channels.isEmpty) return null;
    return srv.channels.firstWhere(
      (c) => c.id == activeChannelId,
      orElse: () => srv.channels.first,
    );
  }

  List<ChatMessage> get activeMessages => _messages[activeChannelId] ?? [];
  List<UserModel> get onlineMembers => _onlineUsers.values.toList();

  List<FriendRequest> get pendingReceivedRequests => friendRequests
      .where((r) =>
          r.status == FriendRequestStatus.pending &&
          r.recipientUsername.toLowerCase() == currentUser.username.toLowerCase())
      .toList();

  List<FriendRequest> get pendingSentRequests => friendRequests
      .where((r) =>
          r.status == FriendRequestStatus.pending &&
          r.senderUsername.toLowerCase() == currentUser.username.toLowerCase())
      .toList();

  int get pendingRequestsCount => pendingReceivedRequests.length;

  void _initDefaultData() {
    // Contas novas iniciam sem nenhum servidor padrão por solicitação explícita de arquitetura
    servers = [];
    isHomePageActive = true;
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
  File _getServersFile() => _getAppFile('servers.json');
  File _getChatHistoryFile() => _getAppFile('chat_history.json');
  File _getDraftsFile() => _getAppFile('drafts.json');
  File _getFriendsFile() => _getAppFile('friends.json');
  File _getKnownUsersFile() => _getAppFile('known_users.json');
  File _getFriendRequestsFile() => _getAppFile('friend_requests.json');

  Future<void> _saveServers() async {
    try {
      final file = _getServersFile();
      final list = servers.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint('Erro ao salvar servidores: $e');
    }
  }

  Future<void> _loadServers() async {
    try {
      final file = _getServersFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> raw = jsonDecode(content);
          final loaded = raw.map((s) => Server.fromJson(s as Map<String, dynamic>)).toList();
          servers = loaded;
          if (servers.isNotEmpty) {
            if (activeServerId.isEmpty || !servers.any((s) => s.id == activeServerId)) {
              activeServerId = servers.first.id;
            }
            if (activeServer?.channels.isNotEmpty ?? false) {
              activeChannelId = activeServer!.channels.first.id;
            }
          } else {
            activeServerId = '';
            activeChannelId = '';
            isHomePageActive = true;
          }
        }
      } else {
        servers = [];
        activeServerId = '';
        activeChannelId = '';
        isHomePageActive = true;
      }
    } catch (e) {
      debugPrint('Erro ao carregar servidores: $e');
    }
  }

  Future<void> _saveFriendRequests() async {
    try {
      final file = _getFriendRequestsFile();
      final list = friendRequests.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint('Erro ao salvar solicitações de amizade: $e');
    }
  }

  Future<void> _loadFriendRequests() async {
    try {
      final file = _getFriendRequestsFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> raw = jsonDecode(content);
          friendRequests = raw.map((r) => FriendRequest.fromJson(r as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar solicitações de amizade: $e');
    }
  }

  Future<void> _saveFriends() async {
    try {
      final file = _getFriendsFile();
      final list = friends.map((f) => f.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint('Erro ao salvar amigos: $e');
    }
  }

  Future<void> _loadFriends() async {
    try {
      final file = _getFriendsFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> raw = jsonDecode(content);
          friends = raw.map((f) => UserModel.fromJson(f as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar amigos: $e');
    }
  }

  Future<void> _saveKnownUsers() async {
    try {
      final file = _getKnownUsersFile();
      final list = _knownUsers.values.map((u) => u.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint('Erro ao salvar usuários conhecidos: $e');
    }
  }

  Future<void> _loadKnownUsers() async {
    try {
      final file = _getKnownUsersFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> raw = jsonDecode(content);
          _knownUsers.clear();
          for (final item in raw) {
            final u = UserModel.fromJson(item as Map<String, dynamic>);
            _knownUsers[u.id] = u;
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar usuários conhecidos: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final file = _getSettingsFile();
      final data = {
        'user_id': currentUser.id,
        'username': currentUser.username.replaceAll('@', '').trim(),
        'displayName': currentUser.displayName,
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
    // Apaga tokens e hashes de senha gravados em texto puro pelas versões
    // anteriores antes de qualquer outra coisa.
    await AuthService.purgeLegacyInsecureFiles();

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
        final savedDisplayName = data['displayName'] as String?;
        if (savedUsername != null && savedUsername.isNotEmpty && !isAuthenticated) {
          currentUser.username = savedUsername.replaceAll('@', '').trim();
        }
        if (savedDisplayName != null && savedDisplayName.isNotEmpty && !isAuthenticated) {
          currentUser.displayName = savedDisplayName;
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar configurações: $e');
    }

    currentUser.username = currentUser.username.replaceAll('@', '').trim();

    await _loadServers();
    await _loadChatHistory();
    await _loadDrafts();
    await _loadFriends();
    await _loadKnownUsers();
    await _loadFriendRequests();

    // Garante que currentUser faça parte dos servidores carregados
    for (final srv in servers) {
      if (!srv.memberIds.contains(currentUser.id)) {
        srv.memberIds.insert(0, currentUser.id);
      }
    }

    isCheckingAuth = false;
    notifyListeners();

    if (isAuthenticated) {
      await _startNetwork();
    }
  }

  Future<void> _startNetwork() async {
    try {
      _stopNetwork();
      final clientId = 'pc_${_uuid.v4().replaceAll('-', '').substring(0, 20)}';
      debugPrint('[AppState] Conectando rede MQTT...');
      await _mqtt.connect(clientId);

      _subscribeToOwnServers();

      _mqttSubscription = _mqtt.messageStream.listen(_handleIncomingNetworkData);

      _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) => _sendPresence());
      _sendPresence();
    } catch (e) {
      debugPrint('Erro ao inicializar rede: $e');
    }
  }

  /// Assina os tópicos dos servidores que o usuário integra, o inbox pessoal e a presença de amigos.
  void _subscribeToOwnServers() {
    _mqtt.unsubscribeAll();

    // 1. Tópicos de servidores
    for (final srv in servers) {
      if (srv.inviteCode.trim().isEmpty) continue;
      _mqtt.subscribe(ServerCrypto.chatTopic(srv.inviteCode));
      _mqtt.subscribe(ServerCrypto.presenceTopic(srv.inviteCode));
    }

    // 2. Inbox pessoal para solicitações e notificações diretas
    final myUser = currentUser.username.trim().toLowerCase();
    if (myUser.isNotEmpty) {
      _mqtt.subscribe(ServerCrypto.userInboxTopic(myUser));
      _mqtt.subscribe(ServerCrypto.userPresenceTopic(myUser));
    }

    // 3. Presença em tempo real dos amigos
    for (final f in friends) {
      final fUser = f.username.trim().toLowerCase();
      if (fUser.isNotEmpty) {
        _mqtt.subscribe(ServerCrypto.userPresenceTopic(fUser));
      }
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
    // Novas contas iniciam com 0 servidores
    servers = [];
    await _saveServers();
    await _saveSettings();
    await _startNetwork();
    notifyListeners();
  }

  Future<void> logout() async {
    if (connectedVoiceChannelId != null) {
      await disconnectVoice();
    }
    // Anuncia status offline antes de desconectar
    await _sendPresence(isOffline: true);
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

  /// Verifica se algum usuário remoto não envia presença há mais de 30 segundos
  void _checkPresenceTimeouts() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final entry in _lastSeen.entries) {
      final uid = entry.key;
      final lastTime = entry.value;
      if (uid != currentUser.id && (now - lastTime > 30000)) {
        if (_onlineUsers.containsKey(uid) && _onlineUsers[uid]!.status != UserStatus.offline) {
          _onlineUsers[uid]!.status = UserStatus.offline;
          changed = true;
        }
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Publica presença nos servidores e no canal pessoal para amigos.
  Future<void> _sendPresence({bool isOffline = false}) async {
    if (!_mqtt.isConnected) return;

    _checkPresenceTimeouts();

    final myStatus = isOffline ? 'offline' : currentUser.status.name;

    // 1. Presença por servidor
    for (final srv in servers) {
      if (srv.inviteCode.trim().isEmpty) continue;

      final presenceData = {
        'action': 'presence',
        'userId': currentUser.id,
        'username': currentUser.username,
        'displayName': currentUser.displayName,
        'avatar': currentUser.avatar,
        'status': myStatus,
        'isMuted': currentUser.isMuted,
        'isDeafened': currentUser.isDeafened,
        'isScreenSharing': currentUser.isScreenSharing,
        'voiceChannelId': activeServerId == srv.id ? connectedVoiceChannelId : null,
        'voiceServerId': activeServerId == srv.id ? activeServerId : null,
        'serverId': srv.id,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      try {
        final envelope = await ServerCrypto.encryptPayload(srv.inviteCode, presenceData);
        _mqtt.publishEncrypted(ServerCrypto.presenceTopic(srv.inviteCode), envelope);
      } catch (e) {
        debugPrint('Erro ao publicar presença em ${srv.id}: $e');
      }
    }

    // 2. Presença no canal pessoal para amigos
    final myUser = currentUser.username.trim().toLowerCase();
    if (myUser.isNotEmpty) {
      final personalPresence = {
        'action': 'user_presence',
        'userId': currentUser.id,
        'username': currentUser.username,
        'displayName': currentUser.displayName,
        'avatar': currentUser.avatar,
        'status': myStatus,
        'isMuted': currentUser.isMuted,
        'isDeafened': currentUser.isDeafened,
        'isScreenSharing': currentUser.isScreenSharing,
        'voiceChannelId': connectedVoiceChannelId,
        'voiceServerId': activeServerId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      try {
        final envelope = await ServerCrypto.encryptFriendPresencePayload(myUser, personalPresence);
        _mqtt.publishEncrypted(ServerCrypto.userPresenceTopic(myUser), envelope);
      } catch (e) {
        debugPrint('Erro ao publicar presença pessoal: $e');
      }
    }
  }

  /// Trata os envelopes MQTT recebidos da rede com validação e decifragem segura.
  Future<void> _handleIncomingNetworkData(MqttEnvelope envelope) async {
    final myUser = currentUser.username.trim().toLowerCase();

    // 1. Mensagem recebida no Inbox pessoal (solicitação de amizade, aceite, recusa)
    if (myUser.isNotEmpty && envelope.topic == ServerCrypto.userInboxTopic(myUser)) {
      final data = await ServerCrypto.decryptInboxPayload(myUser, envelope.payload);
      if (data != null) {
        _processInboxPayload(data);
      }
      return;
    }

    // 2. Presença de amigo recebida diretamente pelo canal pessoal do amigo
    for (final f in friends) {
      final fUser = f.username.trim().toLowerCase();
      if (fUser.isNotEmpty && envelope.topic == ServerCrypto.userPresenceTopic(fUser)) {
        final data = await ServerCrypto.decryptFriendPresencePayload(fUser, envelope.payload);
        if (data != null) {
          _processFriendPresencePayload(data);
        }
        return;
      }
    }

    // 3. Tópico de servidor (chat ou presença)
    Server? origin;
    for (final srv in servers) {
      if (srv.inviteCode.trim().isEmpty) continue;
      final id = ServerCrypto.topicIdFor(srv.inviteCode);
      if (envelope.topic.contains(id)) {
        origin = srv;
        break;
      }
    }
    if (origin == null) return;

    final data = await ServerCrypto.decryptPayload(origin.inviteCode, envelope.payload);
    if (data == null) return;

    _processNetworkPayload(data, origin);
  }

  /// Processa eventos do inbox pessoal (amizades em tempo real)
  void _processInboxPayload(Map<String, dynamic> data) {
    final action = data['action'] as String?;
    if (action == 'friend_request') {
      final reqMap = data['request'] as Map<String, dynamic>?;
      if (reqMap != null) {
        final req = FriendRequest.fromJson(reqMap);
        if (req.recipientUsername.toLowerCase() == currentUser.username.toLowerCase()) {
          friendRequests.removeWhere((r) =>
              r.id == req.id ||
              (r.senderUsername.toLowerCase() == req.senderUsername.toLowerCase() &&
                  r.status == FriendRequestStatus.pending));
          friendRequests.insert(0, req);
          _saveFriendRequests();
          SoundService.playJoinCall();
          notifyListeners();
        }
      }
    } else if (action == 'friend_accepted') {
      final reqId = data['requestId'] as String?;
      final acceptedBy = data['acceptedBy'] as Map<String, dynamic>?;
      if (acceptedBy != null) {
        final user = UserModel.fromJson(acceptedBy);
        final cleanUsername = user.username.replaceFirst('@', '').trim();
        if (!friends.any((f) => f.username.toLowerCase() == cleanUsername.toLowerCase())) {
          friends.add(user);
          _saveFriends();
          _mqtt.subscribe(ServerCrypto.userPresenceTopic(cleanUsername));
        }
      }
      if (reqId != null) {
        for (final r in friendRequests) {
          if (r.id == reqId) {
            r.status = FriendRequestStatus.accepted;
          }
        }
        _saveFriendRequests();
      }
      SoundService.playJoinCall();
      notifyListeners();
    } else if (action == 'friend_rejected') {
      final reqId = data['requestId'] as String?;
      if (reqId != null) {
        friendRequests.removeWhere((r) => r.id == reqId);
        _saveFriendRequests();
        notifyListeners();
      }
    }
  }

  /// Processa atualização de presença vinda de um amigo
  void _processFriendPresencePayload(Map<String, dynamic> data) {
    final uid = data['userId'] as String?;
    if (uid != null && uid != currentUser.id) {
      final username = (data['username'] as String? ?? 'Amigo').replaceFirst('@', '').trim();
      final displayName = data['displayName'] as String? ?? username;
      final statusVal = UserStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => UserStatus.online,
      );

      final user = UserModel(
        id: uid,
        username: username,
        displayName: displayName,
        avatar: data['avatar'] as String? ?? '',
        status: statusVal,
        isMuted: data['isMuted'] as bool? ?? false,
        isDeafened: data['isDeafened'] as bool? ?? false,
        isScreenSharing: data['isScreenSharing'] as bool? ?? false,
        currentVoiceChannelId: data['voiceChannelId'] as String?,
        currentVoiceServerId: data['voiceServerId'] as String?,
      );

      _onlineUsers[uid] = user;
      _knownUsers[uid] = user;
      _lastSeen[uid] = DateTime.now().millisecondsSinceEpoch;
      _saveKnownUsers();

      // Atualiza também o amigo na lista local se encontrado
      final friendIndex = friends.indexWhere((f) => f.username.toLowerCase() == username.toLowerCase());
      if (friendIndex != -1) {
        friends[friendIndex] = user;
      }
      notifyListeners();
    }
  }

  void _processNetworkPayload(Map<String, dynamic> data, Server origin) {
    final action = data['action'] as String?;
    if (action == 'chat_message') {
      final channelId = data['channelId'] as String?;
      final channelName = data['channelName'] as String?;

      // Busca o canal por ID ou por nome correspondente no servidor
      Channel? targetChannel;
      if (channelId != null) {
        for (final c in origin.channels) {
          if (c.id == channelId) {
            targetChannel = c;
            break;
          }
        }
      }
      if (targetChannel == null && channelName != null) {
        for (final c in origin.channels) {
          if (c.name.toLowerCase() == channelName.toLowerCase()) {
            targetChannel = c;
            break;
          }
        }
      }
      if (targetChannel == null && origin.channels.isNotEmpty) {
        targetChannel = origin.channels.firstWhere(
          (c) => c.type == ChannelType.text,
          orElse: () => origin.channels.first,
        );
      }

      if (targetChannel != null) {
        final actualChannelId = targetChannel.id;
        final newMsg = ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
        _messages.putIfAbsent(actualChannelId, () => []);
        if (!_messages[actualChannelId]!.any((m) => m.id == newMsg.id)) {
          _messages[actualChannelId]!.add(newMsg);
          _saveChatHistory();

          if (newMsg.authorId.isNotEmpty && newMsg.authorId != currentUser.id) {
            final authorName = newMsg.authorUsername.replaceFirst('@', '').trim();
            _knownUsers[newMsg.authorId] = UserModel(
              id: newMsg.authorId,
              username: authorName.isNotEmpty ? authorName : newMsg.author,
              displayName: newMsg.authorDisplayName.isNotEmpty ? newMsg.authorDisplayName : newMsg.author,
              status: UserStatus.offline,
            );
            _saveKnownUsers();

            if (!origin.memberIds.contains(newMsg.authorId)) {
              origin.memberIds.add(newMsg.authorId);
              _saveServers();
            }
          }
          notifyListeners();
        }
      }
    } else if (action == 'presence') {
      final uid = data['userId'] as String?;
      if (uid != null && uid != currentUser.id) {
        final username = (data['username'] as String? ?? 'Amigo').replaceFirst('@', '').trim();
        final displayName = data['displayName'] as String? ?? username;
        final user = UserModel(
          id: uid,
          username: username,
          displayName: displayName,
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
        _onlineUsers[uid] = user;
        _knownUsers[uid] = user;
        _lastSeen[uid] = DateTime.now().millisecondsSinceEpoch;
        _saveKnownUsers();

        if (!origin.memberIds.contains(uid)) {
          origin.memberIds.add(uid);
          _saveServers();
        }
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

  Future<Server> createServer({
    required String name,
    String description = '',
    String template = 'gaming',
    String colorHex = '22C55E',
  }) async {
    final randomCode = _uuid.v4().substring(0, 8);
    final inviteCode = 'papo-$randomCode';
    final topicHash = ServerCrypto.topicIdFor(inviteCode);
    final serverId = 'srv-$topicHash';

    List<Channel> channels = [];
    switch (template) {
      case 'gaming':
        channels = [
          Channel(id: '$serverId-c-geral', name: 'geral', type: ChannelType.text, topic: 'Bate-papo geral do squad'),
          Channel(id: '$serverId-c-estrategia', name: 'estratégia', type: ChannelType.text, topic: 'Táticas, calls e jogadas'),
          Channel(id: '$serverId-c-clipes', name: 'clipes-e-midia', type: ChannelType.text, topic: 'Vídeos e melhores momentos'),
          Channel(id: '$serverId-v-squad1', name: '🎮 Squad Alfa', type: ChannelType.voice, userLimit: 5),
          Channel(id: '$serverId-v-squad2', name: '🎮 Squad Bravo', type: ChannelType.voice, userLimit: 5),
          Channel(id: '$serverId-v-lounge', name: '🔊 Sala de Espera', type: ChannelType.voice, userLimit: 15),
        ];
        break;
      case 'community':
        channels = [
          Channel(id: '$serverId-c-boas-vindas', name: 'boas-vindas', type: ChannelType.text, topic: 'Regras e apresentações'),
          Channel(id: '$serverId-c-geral', name: 'geral', type: ChannelType.text, topic: 'Conversa livre'),
          Channel(id: '$serverId-c-anuncios', name: 'anúncios', type: ChannelType.text, topic: 'Comunicados importantes'),
          Channel(id: '$serverId-v-lounge', name: '🔊 Lounge Principal', type: ChannelType.voice, userLimit: 25),
          Channel(id: '$serverId-v-batepapo', name: '🔊 Bate-Papo Descontraído', type: ChannelType.voice, userLimit: 12),
        ];
        break;
      case 'study':
        channels = [
          Channel(id: '$serverId-c-projetos', name: 'projetos', type: ChannelType.text, topic: 'Anotações e tarefas'),
          Channel(id: '$serverId-c-recursos', name: 'links-e-recursos', type: ChannelType.text, topic: 'Materiais de apoio'),
          Channel(id: '$serverId-c-duvidas', name: 'dúvidas', type: ChannelType.text, topic: 'Discussões técnicas'),
          Channel(id: '$serverId-v-foco', name: '🎧 Sala de Foco (Mudo)', type: ChannelType.voice, userLimit: 20),
          Channel(id: '$serverId-v-reuniao', name: '📊 Reunião / Alinhamento', type: ChannelType.voice, userLimit: 10),
        ];
        break;
      default:
        channels = [
          Channel(id: '$serverId-c-geral', name: 'geral', type: ChannelType.text, topic: 'Canal principal'),
          Channel(id: '$serverId-v-geral', name: '🔊 Sala de Voz', type: ChannelType.voice, userLimit: 15),
        ];
    }

    final newServer = Server(
      id: serverId,
      name: name.trim(),
      description: description.trim(),
      inviteCode: inviteCode,
      ownerId: currentUser.id,
      colorHex: colorHex,
      isCustom: true,
      memberIds: [currentUser.id],
      channels: channels,
    );

    servers.add(newServer);
    await _saveServers();
    _subscribeToOwnServers();

    final firstText = channels.firstWhere(
      (c) => c.type == ChannelType.text,
      orElse: () => channels.first,
    );
    _messages[firstText.id] = [
      ChatMessage(
        id: 'msg-init-$serverId',
        authorId: 'sys',
        author: 'Sistema PapoCall',
        text: 'Servidor "${newServer.name}" criado com sucesso! Convide seu squad com o código: $inviteCode',
        timestamp: 'Agora',
        isSystem: true,
      ),
    ];
    await _saveChatHistory();

    selectServer(newServer.id);
    _sendPresence();
    SoundService.playJoinCall();
    notifyListeners();

    return newServer;
  }

  Future<bool> deleteServer(String serverId) async {
    final index = servers.indexWhere((s) => s.id == serverId);
    if (index == -1) return false;

    servers.removeAt(index);
    await _saveServers();

    if (servers.isEmpty) {
      activeServerId = '';
      activeChannelId = '';
      isHomePageActive = true;
    } else if (activeServerId == serverId) {
      selectServer(servers.first.id);
    }
    _sendPresence();
    notifyListeners();
    return true;
  }

  Future<bool> joinServerByInvite(String inviteCode) async {
    final cleanCode = inviteCode.trim();
    if (cleanCode.isEmpty) return false;

    final existing = servers.firstWhere(
      (s) => s.inviteCode.toLowerCase() == cleanCode.toLowerCase(),
      orElse: () => Server(id: '', name: '', inviteCode: '', channels: []),
    );
    if (existing.id.isNotEmpty) {
      if (!existing.memberIds.contains(currentUser.id)) {
        existing.memberIds.add(currentUser.id);
        await _saveServers();
      }
      selectServer(existing.id);
      return true;
    }

    final topicHash = ServerCrypto.topicIdFor(cleanCode);
    final serverId = 'srv-$topicHash';
    final joinedServer = Server(
      id: serverId,
      name: 'Servidor ($cleanCode)',
      description: 'Servidor acessado via convite $cleanCode',
      inviteCode: cleanCode,
      isCustom: true,
      colorHex: '38BDF8',
      memberIds: [currentUser.id],
      channels: [
        Channel(id: '$serverId-c-geral', name: 'geral', type: ChannelType.text, topic: 'Canal de texto principal'),
        Channel(id: '$serverId-v-geral', name: '🔊 Sala de Voz', type: ChannelType.voice, userLimit: 15),
      ],
    );

    servers.add(joinedServer);
    await _saveServers();
    _subscribeToOwnServers();
    selectServer(joinedServer.id);
    _sendPresence();
    SoundService.playJoinCall();
    notifyListeners();
    return true;
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
      author: currentUser.displayNameOrUsername,
      authorDisplayName: currentUser.displayName,
      authorUsername: currentUser.username,
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

    _publishChatMessage(activeChannelId, newMsg);
  }

  Future<void> _publishChatMessage(String channelId, ChatMessage message) async {
    final srv = activeServer;
    if (srv == null || srv.inviteCode.trim().isEmpty) return;

    final channel = activeChannel;
    final chatPayload = {
      'action': 'chat_message',
      'channelId': channelId,
      'channelName': channel?.name ?? 'geral',
      'channelType': channel?.type.name ?? 'text',
      'serverId': srv.id,
      'message': message.toJson(),
    };

    try {
      final envelope = await ServerCrypto.encryptPayload(srv.inviteCode, chatPayload);
      _mqtt.publishEncrypted(ServerCrypto.chatTopic(srv.inviteCode), envelope);
    } catch (e) {
      debugPrint('Erro ao publicar mensagem cifrada: $e');
    }
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

  Future<void> setDisplayName(String newDisplayName) async {
    final trimmed = newDisplayName.trim();
    if (trimmed.isEmpty) return;
    currentUser.displayName = trimmed;

    if (currentSession != null) {
      currentSession = AuthSession(
        accessToken: currentSession!.accessToken,
        refreshToken: currentSession!.refreshToken,
        user: AuthUser(
          id: currentSession!.user.id,
          email: currentSession!.user.email,
          username: currentSession!.user.username,
          rawUsername: currentSession!.user.rawUsername,
          displayName: trimmed,
          emailVerified: currentSession!.user.emailVerified,
        ),
      );
      await AuthService.saveSession(currentSession!);
    }

    await _saveSettings();
    _sendPresence();
    notifyListeners();
  }

  Future<void> setUsername(String newName) async {
    final rawUser = newName.trim().replaceAll('@', '').toLowerCase();
    if (rawUser.isEmpty) return;
    currentUser.username = rawUser;

    if (currentSession != null) {
      currentSession = AuthSession(
        accessToken: currentSession!.accessToken,
        refreshToken: currentSession!.refreshToken,
        user: AuthUser(
          id: currentSession!.user.id,
          email: currentSession!.user.email,
          username: '@$rawUser',
          rawUsername: rawUser,
          displayName: currentSession!.user.displayName,
          emailVerified: currentSession!.user.emailVerified,
        ),
      );
      await AuthService.saveSession(currentSession!);
    }

    await _saveSettings();
    _sendPresence();
    notifyListeners();
  }

  List<UserModel> get friendsWithLiveStatus {
    return friends.map((f) {
      if (_onlineUsers.containsKey(f.id)) {
        return _onlineUsers[f.id]!;
      }
      return f;
    }).toList();
  }

  Future<String?> sendFriendRequest(String rawHandle) async {
    final cleanHandle = rawHandle.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
    if (cleanHandle.isEmpty) {
      return 'Por favor, insira uma tag de usuário válida.';
    }
    if (cleanHandle == currentUser.username.toLowerCase()) {
      return 'Você não pode enviar solicitação para si mesmo.';
    }
    if (friends.any((f) => f.username.toLowerCase() == cleanHandle)) {
      return 'Este usuário já está na sua lista de amigos.';
    }
    final alreadyPending = friendRequests.any((r) =>
        r.status == FriendRequestStatus.pending &&
        r.recipientUsername.toLowerCase() == cleanHandle &&
        r.senderUsername.toLowerCase() == currentUser.username.toLowerCase());
    if (alreadyPending) {
      return 'Já existe uma solicitação pendente enviada para este usuário.';
    }

    final req = FriendRequest(
      id: 'req-${_uuid.v4().substring(0, 8)}',
      senderId: currentUser.id,
      senderUsername: currentUser.username,
      senderDisplayName: currentUser.displayName,
      senderAvatar: currentUser.avatar,
      recipientUsername: cleanHandle,
      status: FriendRequestStatus.pending,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    friendRequests.removeWhere((r) =>
        r.recipientUsername.toLowerCase() == cleanHandle &&
        r.senderUsername.toLowerCase() == currentUser.username.toLowerCase());
    friendRequests.insert(0, req);
    await _saveFriendRequests();
    notifyListeners();

    // Envia o envelope cifrado no inbox do destinatário
    final payload = {
      'action': 'friend_request',
      'request': req.toJson(),
    };
    try {
      final envelope = await ServerCrypto.encryptInboxPayload(cleanHandle, payload);
      _mqtt.publishEncrypted(ServerCrypto.userInboxTopic(cleanHandle), envelope);
    } catch (e) {
      debugPrint('Erro ao publicar solicitação de amizade: $e');
    }

    return null;
  }

  Future<String?> addFriendByHandle(String rawHandle) async {
    return sendFriendRequest(rawHandle);
  }

  Future<void> acceptFriendRequest(FriendRequest req) async {
    req.status = FriendRequestStatus.accepted;
    await _saveFriendRequests();

    final cleanSender = req.senderUsername.replaceFirst('@', '').trim();
    final newFriend = UserModel(
      id: req.senderId.isNotEmpty ? req.senderId : 'user-$cleanSender',
      username: cleanSender,
      displayName: req.senderDisplayName,
      avatar: req.senderAvatar ?? '',
      status: _onlineUsers[req.senderId]?.status ?? UserStatus.online,
    );

    if (!friends.any((f) => f.username.toLowerCase() == cleanSender.toLowerCase())) {
      friends.add(newFriend);
      await _saveFriends();
      _mqtt.subscribe(ServerCrypto.userPresenceTopic(cleanSender));
    }

    // Notifica o remetente de volta que o pedido foi aceito
    final responsePayload = {
      'action': 'friend_accepted',
      'requestId': req.id,
      'acceptedBy': currentUser.toJson(),
    };
    try {
      final envelope = await ServerCrypto.encryptInboxPayload(cleanSender, responsePayload);
      _mqtt.publishEncrypted(ServerCrypto.userInboxTopic(cleanSender), envelope);
    } catch (e) {
      debugPrint('Erro ao publicar aceite de amizade: $e');
    }

    SoundService.playJoinCall();
    notifyListeners();
  }

  Future<void> rejectFriendRequest(FriendRequest req) async {
    req.status = FriendRequestStatus.rejected;
    friendRequests.removeWhere((r) => r.id == req.id);
    await _saveFriendRequests();

    final cleanSender = req.senderUsername.replaceFirst('@', '').trim();
    final rejectPayload = {
      'action': 'friend_rejected',
      'requestId': req.id,
      'rejectedBy': currentUser.username,
    };
    try {
      final envelope = await ServerCrypto.encryptInboxPayload(cleanSender, rejectPayload);
      _mqtt.publishEncrypted(ServerCrypto.userInboxTopic(cleanSender), envelope);
    } catch (e) {
      debugPrint('Erro ao publicar rejeição de amizade: $e');
    }

    notifyListeners();
  }

  Future<void> cancelFriendRequest(FriendRequest req) async {
    friendRequests.removeWhere((r) => r.id == req.id);
    await _saveFriendRequests();
    notifyListeners();
  }

  Future<void> removeFriend(String friendId) async {
    friends.removeWhere((f) => f.id == friendId);
    await _saveFriends();
    notifyListeners();
  }

  Map<String, List<UserModel>> getServerMembersGrouped(String serverId) {
    if (servers.isEmpty) {
      return {
        'online': [],
        'offline': [],
      };
    }

    final srv = servers.firstWhere(
      (s) => s.id == serverId,
      orElse: () => activeServer ?? servers.first,
    );

    if (!srv.memberIds.contains(currentUser.id)) {
      srv.memberIds.insert(0, currentUser.id);
    }

    final online = <UserModel>[];
    final offline = <UserModel>[];

    for (final memberId in srv.memberIds) {
      if (memberId == currentUser.id) {
        if (currentUser.status == UserStatus.offline) {
          offline.add(currentUser);
        } else {
          online.add(currentUser);
        }
      } else if (_onlineUsers.containsKey(memberId)) {
        final onlineUser = _onlineUsers[memberId]!;
        if (onlineUser.status == UserStatus.offline) {
          offline.add(onlineUser);
        } else {
          online.add(onlineUser);
        }
      } else if (_knownUsers.containsKey(memberId)) {
        final known = _knownUsers[memberId]!;
        offline.add(UserModel(
          id: known.id,
          username: known.username,
          displayName: known.displayName,
          avatar: known.avatar,
          status: UserStatus.offline,
        ));
      } else {
        offline.add(UserModel(
          id: memberId,
          username: memberId.replaceFirst('user-', 'membro_'),
          status: UserStatus.offline,
        ));
      }
    }

    online.sort((a, b) {
      if (a.id == currentUser.id) return -1;
      if (b.id == currentUser.id) return 1;
      return a.displayNameOrUsername.toLowerCase().compareTo(b.displayNameOrUsername.toLowerCase());
    });

    offline.sort((a, b) {
      if (a.id == currentUser.id) return -1;
      if (b.id == currentUser.id) return 1;
      return a.displayNameOrUsername.toLowerCase().compareTo(b.displayNameOrUsername.toLowerCase());
    });

    return {
      'online': online,
      'offline': offline,
    };
  }

  Future<String> regenerateServerInvite(String serverId) async {
    if (servers.isEmpty) return '';
    final srv = servers.firstWhere(
      (s) => s.id == serverId,
      orElse: () => activeServer ?? servers.first,
    );
    // Regenerar o convite rotaciona a chave de criptografia e o topico do
    // servidor: quem tinha o codigo antigo perde o acesso as mensagens novas.
    final randomCode = _uuid.v4().substring(0, 8);
    srv.inviteCode = 'papo-$randomCode';
    await _saveServers();
    _subscribeToOwnServers();
    notifyListeners();
    return srv.inviteCode;
  }

  String? voiceErrorMessage;

  Future<void> connectVoice(String channelId) async {
    if (isConnectingVoice) return;
    if (connectedVoiceChannelId == channelId) return;

    isConnectingVoice = true;
    voiceErrorMessage = null;
    notifyListeners();

    try {
      // A identity do LiveKit passa a ser definida pelo backend a partir do JWT,
      // e não mais montada aqui, para impedir personificação de outro usuário.
      final success = await _voiceService.joinVoice(
        roomName: channelId,
        accessToken: currentSession?.accessToken ?? '',
      );

      if (success) {
        connectedVoiceChannelId = channelId;
        currentUser.currentVoiceChannelId = channelId;
        voiceErrorMessage = null;
        SoundService.playJoinCall();
      } else {
        connectedVoiceChannelId = null;
        currentUser.currentVoiceChannelId = null;
        voiceErrorMessage = _voiceService.lastErrorMessage ?? 'Falha ao conectar à chamada de voz.';
        final lower = voiceErrorMessage!.toLowerCase();
        if (lower.contains('sessão expirou') || lower.contains('faça login') || lower.contains('não autorizado')) {
          Future.microtask(() => logout());
        }
      }
    } catch (e) {
      debugPrint('Erro ao conectar no LiveKit para o canal $channelId: $e');
      connectedVoiceChannelId = null;
      currentUser.currentVoiceChannelId = null;
      voiceErrorMessage = e.toString().replaceFirst('Exception: ', '');
      final lower = voiceErrorMessage!.toLowerCase();
      if (lower.contains('sessão expirou') || lower.contains('faça login') || lower.contains('não autorizado')) {
        Future.microtask(() => logout());
      }
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
    _isDisposed = true;
    _pingSubscription?.cancel();
    _pingSubscription = null;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _voiceService.dispose();
    _mqtt.disconnect();
    super.dispose();
  }
}
