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
import '../utils/mentions.dart';

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
  Timer? _presenceSweepTimer;
  StreamSubscription? _mqttSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _pingSubscription;
  bool _isDisposed = false;

  /// Estado da malha de sincronização (MQTT) exposto à UI.
  ///
  /// Sem isso o app parecia normal enquanto nada entrava nem saía: mensagens,
  /// presenças e solicitações de amizade simplesmente sumiam em silêncio.
  bool isNetworkOnline = false;

  /// Solicitações de amizade enviadas sem rede, aguardando reenvio.
  final List<FriendRequest> _outboxFriendRequests = [];

  bool get hasPendingOutbox => _outboxFriendRequests.isNotEmpty;

  // --- Histórico compartilhado -------------------------------------------
  //
  // O broker não guarda conversa: cada membro mantém um retrato retido das
  // mensagens recentes que conhece, e quem chega intercala os retratos de
  // todos. Os limites abaixo existem porque uma mensagem retida tem teto de
  // tamanho e o broker é público — um retrato ilimitado viraria um despejo de
  // dados que ninguém consegue baixar.

  /// Mensagens por canal incluídas no retrato publicado.
  static const int _historyPerChannel = 60;

  /// Teto de mensagens do retrato inteiro, somando todos os canais.
  static const int _historyTotalCap = 300;

  /// Teto de mensagens mantidas em memória e em disco por canal.
  static const int _channelMessageCap = 600;

  /// Teto de tamanho do retrato cifrado (o recebimento corta em 256 KB).
  static const int _historyMaxBytes = 160 * 1024;

  /// Quantidade de membros anunciada na estrutura do servidor.
  static const int _maxRosterSize = 200;

  Timer? _historyPublishTimer;
  final Set<String> _serversNeedingHistoryPublish = {};

  /// Momento da última leitura de cada canal, para contar o que chegou depois.
  final Map<String, int> _lastReadAt = {};

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
  File _getReadMarksFile() => _getAppFile('read_marks.json');

  Future<void> _saveReadMarks() async {
    try {
      await _getReadMarksFile().writeAsString(jsonEncode(_lastReadAt));
    } catch (e) {
      debugPrint('Erro ao salvar marcas de leitura: $e');
    }
  }

  Future<void> _loadReadMarks() async {
    try {
      final file = _getReadMarksFile();
      if (!file.existsSync()) return;
      final content = await file.readAsString();
      if (content.isEmpty) return;
      final Map<String, dynamic> raw = jsonDecode(content);
      _lastReadAt.clear();
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is int) _lastReadAt[entry.key] = value;
      }
    } catch (e) {
      debugPrint('Erro ao carregar marcas de leitura: $e');
    }
  }

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
          // O criador do servidor é a fonte da verdade da estrutura. Os demais
          // ficam marcados como não sincronizados para adotar a estrutura real
          // assim que ela chegar pela rede, em vez de manter os canais que as
          // versões anteriores inventavam localmente ao entrar por convite.
          for (final s in servers) {
            if (s.ownerId.isNotEmpty && s.ownerId == currentUser.id) {
              s.isSynced = true;
            }
          }
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
            if (list.isEmpty) continue;

            // Mensagens gravadas antes da v1.0.0n não têm data. Renumera-as com
            // valores sequenciais mínimos: elas mantêm a ordem em que foram
            // gravadas e ficam sempre antes de qualquer mensagem com data real,
            // que é o único posicionamento defensável para elas.
            var legado = 0;
            for (final m in list) {
              if (m.sentAt <= 0) m.sentAt = ++legado;
            }

            if (list.length > _channelMessageCap) {
              list.removeRange(0, list.length - _channelMessageCap);
            }
            _messages[entry.key] = list;
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
    await _loadReadMarks();

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

      _mqttSubscription = _mqtt.messageStream.listen(_handleIncomingNetworkData);
      _connectionSubscription = _mqtt.connectionStream.listen(_handleConnectionChange);

      // A varredura de presença roda independentemente da conexão: sem ela, um
      // membro que caiu ficava marcado como online para sempre enquanto o
      // próprio app estivesse sem rede.
      _presenceSweepTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _checkPresenceTimeouts();
      });

      final clientId = 'pc_${_uuid.v4().replaceAll('-', '').substring(0, 20)}';
      debugPrint('[AppState] Conectando rede MQTT...');
      // Não aguarda o resultado: se a primeira tentativa falhar, o MqttService
      // reconecta sozinho com backoff e _handleConnectionChange reassina tudo.
      unawaited(_mqtt.connect(clientId));

      _subscribeToOwnServers();

      _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) => _sendPresence());
    } catch (e) {
      debugPrint('Erro ao inicializar rede: $e');
    }
  }

  /// Reage a cada transição de conectividade com o broker.
  ///
  /// Toda vez que a malha volta, o estado precisa ser reconciliado: reassinar
  /// os tópicos, reanunciar presença, republicar a estrutura dos servidores e
  /// reenviar o que ficou preso na fila de saída enquanto estávamos offline.
  void _handleConnectionChange(bool connected) {
    isNetworkOnline = connected;
    notifyListeners();
    if (!connected) return;

    _subscribeToOwnServers();
    _publishAllServerInfo();
    _sendPresence();
    _flushOutbox();
    for (final srv in servers) {
      _publishHistorySnapshot(srv);
    }
  }

  /// Assina os tópicos dos servidores que o usuário integra, o inbox pessoal e a presença de amigos.
  void _subscribeToOwnServers() {
    final desired = <String>{};

    // 1. Tópicos de servidores, todos por nome exato — sem curinga.
    // O tópico compartilhado de presença traz os heartbeats ao vivo e é o que
    // revela membros ainda desconhecidos; o compartimento retido de cada membro
    // já conhecido é assinado individualmente e entrega a última presença dele
    // no ato, sem esperar o próximo heartbeat.
    for (final srv in servers) {
      if (srv.inviteCode.trim().isEmpty) continue;
      desired.add(ServerCrypto.chatTopic(srv.inviteCode));
      desired.add(ServerCrypto.presenceTopic(srv.inviteCode));
      desired.add(ServerCrypto.serverInfoTopic(srv.inviteCode));
      for (final memberId in srv.memberIds) {
        if (memberId == currentUser.id) continue;
        desired.add(ServerCrypto.presenceSlotTopic(srv.inviteCode, memberId));
        // Retrato de histórico de cada membro conhecido: é o que traz a
        // conversa anterior para quem acabou de entrar, mesmo com todos offline.
        desired.add(ServerCrypto.historySlotTopic(srv.inviteCode, memberId));
      }
    }

    // 2. Inbox pessoal para solicitações e notificações diretas
    final myUser = currentUser.username.trim().toLowerCase();
    if (myUser.isNotEmpty) {
      desired.add(ServerCrypto.userInboxWildcard(myUser));
    }

    // 3. Presença em tempo real dos amigos
    for (final f in friends) {
      final fUser = f.username.trim().toLowerCase();
      if (fUser.isNotEmpty) {
        desired.add(ServerCrypto.userPresenceTopic(fUser));
      }
    }

    _mqtt.syncSubscriptions(desired);
  }

  void _stopNetwork() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _presenceSweepTimer?.cancel();
    _presenceSweepTimer = null;
    _historyPublishTimer?.cancel();
    _historyPublishTimer = null;
    _serversNeedingHistoryPublish.clear();
    _mqttSubscription?.cancel();
    _mqttSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    isNetworkOnline = false;
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

  /// Janela em que uma presença ainda conta como recente (3 heartbeats).
  static const int _presenceTtlMs = 30000;

  /// Verifica se algum usuário remoto não envia presença há mais de 30 segundos
  void _checkPresenceTimeouts() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final entry in _lastSeen.entries) {
      final uid = entry.key;
      final lastTime = entry.value;
      if (uid != currentUser.id && (now - lastTime > _presenceTtlMs)) {
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

        // 1a. Heartbeat no tópico compartilhado. É por aqui que membros que
        // ainda não se conhecem descobrem uns aos outros, já que ninguém pode
        // assinar o compartimento de alguém cujo ID desconhece.
        _mqtt.publishEncrypted(ServerCrypto.presenceTopic(srv.inviteCode), envelope);

        // 1b. Cópia retida no compartimento pessoal: quem já conhece este
        // usuário recebe a presença dele no instante em que abre o app, sem
        // esperar o próximo heartbeat.
        _mqtt.publishEncrypted(
          ServerCrypto.presenceSlotTopic(srv.inviteCode, currentUser.id),
          envelope,
          retain: true,
        );
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
        _mqtt.publishEncrypted(ServerCrypto.userPresenceTopic(myUser), envelope, retain: true);
      } catch (e) {
        debugPrint('Erro ao publicar presença pessoal: $e');
      }
    }
  }

  /// Publica (retida) a estrutura real de cada servidor que este usuário conhece.
  ///
  /// É o que permite a quem entra por convite adotar o nome, a cor e sobretudo
  /// os IDs de canal reais do servidor, em vez de inventar uma estrutura local
  /// que não bate com a de ninguém.
  Future<void> _publishAllServerInfo() async {
    for (final srv in servers) {
      if (srv.ownerId == currentUser.id) {
        await _publishServerInfo(srv);
      } else if (!srv.isSynced) {
        // Ainda com estrutura provisória: pede a verdadeira, caso o dono esteja
        // online. Se não estiver, a versão retida no tópico de info resolve.
        await _requestServerInfo(srv);
      }
    }
  }

  /// Agenda a republicação do retrato de histórico deste servidor.
  ///
  /// É debounced porque o retrato é republicado a cada mensagem nova: sem a
  /// espera, uma conversa animada geraria uma publicação retida por linha
  /// digitada, cada uma carregando as últimas dezenas de mensagens.
  void _scheduleHistoryPublish(String serverId) {
    _serversNeedingHistoryPublish.add(serverId);
    _historyPublishTimer ??= Timer(const Duration(seconds: 20), () {
      _historyPublishTimer = null;
      final pendentes = Set<String>.from(_serversNeedingHistoryPublish);
      _serversNeedingHistoryPublish.clear();
      for (final id in pendentes) {
        final index = servers.indexWhere((s) => s.id == id);
        if (index != -1) _publishHistorySnapshot(servers[index]);
      }
    });
  }

  /// Publica (retido) o retrato das mensagens recentes deste servidor.
  ///
  /// Cada membro publica no seu próprio compartimento, então ninguém apaga o
  /// retrato de ninguém — e a conversa continua disponível mesmo que todos os
  /// participantes estejam offline quando alguém novo entrar.
  Future<void> _publishHistorySnapshot(Server srv) async {
    if (srv.inviteCode.trim().isEmpty) return;
    if (!_mqtt.isConnected) return;

    var porCanal = <String, List<Map<String, dynamic>>>{};
    var restante = _historyTotalCap;

    for (final canal in srv.channels) {
      if (restante <= 0) break;
      final mensagens = _messages[canal.id];
      if (mensagens == null || mensagens.isEmpty) continue;

      final quantidade =
          mensagens.length < _historyPerChannel ? mensagens.length : _historyPerChannel;
      final limite = quantidade < restante ? quantidade : restante;
      final recentes = mensagens.sublist(mensagens.length - limite);

      // Mensagens de sistema são locais de quem as gerou ("servidor criado
      // com sucesso") e não fazem sentido no histórico alheio.
      final uteis = recentes.where((m) => !m.isSystem).map((m) => m.toJson()).toList();
      if (uteis.isEmpty) continue;

      porCanal[canal.id] = uteis;
      restante -= uteis.length;
    }

    if (porCanal.isEmpty) return;

    Map<String, dynamic> montar() => {
          'action': 'history_snapshot',
          'serverId': srv.id,
          'channels': porCanal,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

    // Corta pela metade até caber no teto. Um retrato grande demais seria
    // descartado no recebimento e não serviria para ninguém.
    var payload = montar();
    var tentativas = 0;
    while (jsonEncode(payload).length > _historyMaxBytes && tentativas < 6) {
      porCanal = porCanal.map((canalId, lista) {
        final metade = lista.length ~/ 2;
        return MapEntry(canalId, metade > 0 ? lista.sublist(lista.length - metade) : <Map<String, dynamic>>[]);
      })..removeWhere((_, lista) => lista.isEmpty);
      if (porCanal.isEmpty) return;
      payload = montar();
      tentativas++;
    }

    try {
      final envelope = await ServerCrypto.encryptPayload(srv.inviteCode, payload);
      _mqtt.publishEncrypted(
        ServerCrypto.historySlotTopic(srv.inviteCode, currentUser.id),
        envelope,
        retain: true,
      );
    } catch (e) {
      debugPrint('Erro ao publicar histórico de ${srv.id}: $e');
    }
  }

  /// Intercala o retrato recebido de outro membro com o histórico local.
  void _processHistorySnapshot(Map<String, dynamic> data, Server origin) {
    final canais = data['channels'] as Map<String, dynamic>?;
    if (canais == null || canais.isEmpty) return;

    final idsValidos = origin.channels.map((c) => c.id).toSet();
    var mudou = false;

    for (final entrada in canais.entries) {
      // Só aceita canais que existem na estrutura deste servidor: o envelope é
      // autenticado, mas um membro com estrutura defasada ainda poderia trazer
      // IDs de canais que já não existem.
      if (!idsValidos.contains(entrada.key)) continue;

      final recebidas = entrada.value as List<dynamic>?;
      if (recebidas == null || recebidas.isEmpty) continue;

      final destino = _messages.putIfAbsent(entrada.key, () => []);
      final conhecidas = destino.map((m) => m.id).toSet();
      var adicionadas = 0;

      for (final bruta in recebidas) {
        if (bruta is! Map<String, dynamic>) continue;
        final msg = ChatMessage.fromJson(bruta);
        if (msg.id.isEmpty || conhecidas.contains(msg.id)) continue;
        if (msg.sentAt <= 0) continue; // sem data não há como posicionar

        destino.add(msg);
        conhecidas.add(msg.id);
        adicionadas++;

        if (msg.authorId.isNotEmpty && msg.authorId != currentUser.id) {
          _registerKnownAuthor(msg);
        }
      }

      if (adicionadas == 0) continue;
      mudou = true;

      destino.sort((a, b) => a.sentAt != b.sentAt
          ? a.sentAt.compareTo(b.sentAt)
          : a.id.compareTo(b.id));
      if (destino.length > _channelMessageCap) {
        destino.removeRange(0, destino.length - _channelMessageCap);
      }
    }

    if (mudou) {
      _saveChatHistory();
      _saveKnownUsers();
      notifyListeners();
    }
  }

  /// Passa a acompanhar os compartimentos retidos de um membro recém-descoberto.
  ///
  /// Um membro só pode ser encontrado ao vivo (heartbeat ou mensagem) ou pelo
  /// roster do servidor; a partir daí, assinar presença e histórico dele pelo
  /// nome exato faz com que ele apareça de imediato nas próximas aberturas do
  /// app, sem esperar que volte a falar.
  void _trackMemberSlots(Server origin, String memberId) {
    if (memberId.isEmpty || memberId == currentUser.id) return;
    if (origin.memberIds.contains(memberId)) return;

    origin.memberIds.add(memberId);
    _saveServers();
    _mqtt.subscribe(ServerCrypto.presenceSlotTopic(origin.inviteCode, memberId));
    _mqtt.subscribe(ServerCrypto.historySlotTopic(origin.inviteCode, memberId));
  }

  /// Registra o autor de uma mensagem como membro conhecido do servidor.
  void _registerKnownAuthor(ChatMessage msg) {
    final nome = msg.authorUsername.replaceFirst('@', '').trim();
    _knownUsers[msg.authorId] = UserModel(
      id: msg.authorId,
      username: nome.isNotEmpty ? nome : msg.author,
      displayName: msg.authorDisplayName.isNotEmpty ? msg.authorDisplayName : msg.author,
      status: _onlineUsers[msg.authorId]?.status ?? UserStatus.offline,
    );
  }

  /// Pede ao dono do servidor que reanuncie a estrutura.
  Future<void> _requestServerInfo(Server srv) async {
    if (srv.inviteCode.trim().isEmpty) return;
    try {
      final envelope = await ServerCrypto.encryptPayload(srv.inviteCode, {
        'action': 'request_server_info',
        'serverId': srv.id,
        'requestedBy': currentUser.id,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      _mqtt.publishEncrypted(ServerCrypto.chatTopic(srv.inviteCode), envelope);
    } catch (e) {
      debugPrint('Erro ao pedir estrutura de ${srv.id}: $e');
    }
  }

  /// Anuncia a estrutura do servidor. Só o dono publica.
  ///
  /// A mensagem é retida e o broker guarda apenas a última de cada tópico: se
  /// qualquer membro pudesse publicar, um membro com uma revisão antiga
  /// sobrescreveria a atual e reverteria os canais de todo mundo.
  Future<void> _publishServerInfo(Server srv) async {
    if (srv.inviteCode.trim().isEmpty) return;
    if (srv.ownerId != currentUser.id) return;
    if (!srv.isSynced) return; // não propaga uma estrutura provisória

    final payload = {
      'action': 'server_info',
      'serverId': srv.id,
      'name': srv.name,
      'description': srv.description,
      'colorHex': srv.colorHex,
      'ownerId': srv.ownerId,
      'channels': srv.channels.map((c) => c.toJson()).toList(),
      // O roster viaja junto porque é a única forma de quem acabou de entrar
      // descobrir de quem pedir histórico e presença: os compartimentos de cada
      // membro são assinados pelo nome exato, e não dá para assinar o
      // compartimento de alguém cujo ID se desconhece.
      'memberIds': srv.memberIds.take(_maxRosterSize).toList(),
      'revision': srv.revision,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      final envelope = await ServerCrypto.encryptPayload(srv.inviteCode, payload);
      _mqtt.publishEncrypted(ServerCrypto.serverInfoTopic(srv.inviteCode), envelope, retain: true);
    } catch (e) {
      debugPrint('Erro ao publicar estrutura de ${srv.id}: $e');
    }
  }

  /// Trata os envelopes MQTT recebidos da rede com validação e decifragem segura.
  Future<void> _handleIncomingNetworkData(MqttEnvelope envelope) async {
    final myUser = currentUser.username.trim().toLowerCase();

    // 1. Mensagem recebida no Inbox pessoal (solicitação de amizade, aceite, recusa).
    // Cobre tanto o tópico legado quanto os compartimentos retidos por remetente.
    if (myUser.isNotEmpty && envelope.topic.startsWith(ServerCrypto.userInboxTopic(myUser))) {
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
        final cleanSender = req.senderUsername.replaceFirst('@', '').trim().toLowerCase();
        if (req.recipientUsername.toLowerCase() != currentUser.username.toLowerCase()) return;

        // Já somos amigos: o pedido retido ficou órfão no broker. Limpa o
        // compartimento para não ser reentregue a cada reconexão.
        if (friends.any((f) => f.username.toLowerCase() == cleanSender)) {
          _mqtt.clearRetained(
            ServerCrypto.userInboxSlotTopic(currentUser.username, cleanSender),
          );
          return;
        }

        // Mensagens retidas são reentregues a cada assinatura: só trata como
        // novidade (e só toca o som) o que ainda não estava na lista.
        final isNew = !friendRequests.any((r) =>
            r.id == req.id ||
            (r.senderUsername.toLowerCase() == cleanSender &&
                r.recipientUsername.toLowerCase() == req.recipientUsername.toLowerCase()));
        if (!isNew) return;

        friendRequests.removeWhere((r) =>
            r.id == req.id ||
            (r.senderUsername.toLowerCase() == cleanSender &&
                r.status == FriendRequestStatus.pending));
        friendRequests.insert(0, req);
        _saveFriendRequests();
        SoundService.playJoinCall();
        notifyListeners();
      }
    } else if (action == 'friend_accepted') {
      final reqId = data['requestId'] as String?;
      final acceptedBy = data['acceptedBy'] as Map<String, dynamic>?;
      var changed = false;

      if (acceptedBy != null) {
        final user = UserModel.fromJson(acceptedBy);
        final cleanUsername = user.username.replaceFirst('@', '').trim();
        if (!friends.any((f) => f.username.toLowerCase() == cleanUsername.toLowerCase())) {
          friends.add(user);
          _saveFriends();
          _mqtt.subscribe(ServerCrypto.userPresenceTopic(cleanUsername));
          changed = true;
        }
        // Evento terminal: apaga o retido para não ser reentregue a cada
        // reconexão nem tocar o som de novo.
        _mqtt.clearRetained(
          ServerCrypto.userInboxSlotTopic(currentUser.username, cleanUsername),
        );
      }

      if (reqId != null) {
        for (final r in friendRequests) {
          if (r.id == reqId && r.status != FriendRequestStatus.accepted) {
            r.status = FriendRequestStatus.accepted;
            changed = true;
          }
        }
        _outboxFriendRequests.removeWhere((r) => r.id == reqId);
        _saveFriendRequests();
      }

      if (changed) {
        SoundService.playJoinCall();
        notifyListeners();
      }
    } else if (action == 'friend_rejected') {
      final reqId = data['requestId'] as String?;
      final rejectedBy = (data['rejectedBy'] as String? ?? '').replaceFirst('@', '').trim();
      if (rejectedBy.isNotEmpty) {
        _mqtt.clearRetained(
          ServerCrypto.userInboxSlotTopic(currentUser.username, rejectedBy),
        );
      }
      if (reqId != null) {
        final before = friendRequests.length;
        friendRequests.removeWhere((r) => r.id == reqId);
        _outboxFriendRequests.removeWhere((r) => r.id == reqId);
        if (friendRequests.length != before) {
          _saveFriendRequests();
          notifyListeners();
        }
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

      // Mesma regra da presença de servidor: a presença retida de um amigo é o
      // último estado publicado e só vale como "agora" enquanto for recente.
      final sentAt = data['timestamp'] as int? ?? 0;
      final isFresh =
          sentAt > 0 && DateTime.now().millisecondsSinceEpoch - sentAt < _presenceTtlMs;

      final user = UserModel(
        id: uid,
        username: username,
        displayName: displayName,
        avatar: data['avatar'] as String? ?? '',
        status: isFresh ? statusVal : UserStatus.offline,
        isMuted: data['isMuted'] as bool? ?? false,
        isDeafened: data['isDeafened'] as bool? ?? false,
        isScreenSharing: isFresh && (data['isScreenSharing'] as bool? ?? false),
        currentVoiceChannelId: isFresh ? data['voiceChannelId'] as String? : null,
        currentVoiceServerId: isFresh ? data['voiceServerId'] as String? : null,
      );

      _onlineUsers[uid] = user;
      _knownUsers[uid] = user;
      _lastSeen[uid] = isFresh ? DateTime.now().millisecondsSinceEpoch : sentAt;
      _saveKnownUsers();

      // Atualiza também o amigo na lista local se encontrado
      final friendIndex = friends.indexWhere((f) => f.username.toLowerCase() == username.toLowerCase());
      if (friendIndex != -1) {
        friends[friendIndex] = user;
      }
      notifyListeners();
    }
  }

  /// Adota a estrutura real do servidor anunciada por outro membro.
  ///
  /// O envelope só é decifrável por quem tem o código de convite, então a
  /// origem já está autenticada pelo próprio AES-GCM: um terceiro não consegue
  /// forjar uma estrutura para reescrever os canais alheios.
  void _processServerInfoPayload(Map<String, dynamic> data, Server origin) {
    // O roster é absorvido sempre, mesmo quando a estrutura em si não muda: é
    // ele que revela de quem assinar presença e histórico, e um membro novo
    // pode aparecer sem que nada mais do servidor tenha mudado.
    final roster = (data['memberIds'] as List<dynamic>?)?.map((m) => m.toString()) ?? const [];
    var rosterMudou = false;
    for (final memberId in roster) {
      if (memberId.isEmpty || origin.memberIds.contains(memberId)) continue;
      origin.memberIds.add(memberId);
      rosterMudou = true;
      if (memberId != currentUser.id) {
        _mqtt.subscribe(ServerCrypto.presenceSlotTopic(origin.inviteCode, memberId));
        _mqtt.subscribe(ServerCrypto.historySlotTopic(origin.inviteCode, memberId));
      }
    }
    if (rosterMudou) {
      _saveServers();
      notifyListeners();
    }

    final rawChannels = data['channels'] as List<dynamic>? ?? [];
    if (rawChannels.isEmpty) return;

    final incomingRevision = data['revision'] as int? ?? 1;
    // Uma estrutura ainda provisória sempre cede à primeira versão real que
    // chegar; depois disso, só uma revisão maior substitui a local.
    if (origin.isSynced && incomingRevision <= origin.revision) return;

    final newChannels =
        rawChannels.map((c) => Channel.fromJson(c as Map<String, dynamic>)).toList();

    // Migra o histórico local dos canais provisórios para os canais reais de
    // mesmo nome, para que as mensagens já escritas não sumam da tela.
    final remap = <String, String>{};
    for (final old in origin.channels) {
      if (newChannels.any((c) => c.id == old.id)) continue;
      for (final fresh in newChannels) {
        if (fresh.type == old.type && fresh.name.toLowerCase() == old.name.toLowerCase()) {
          remap[old.id] = fresh.id;
          break;
        }
      }
    }
    remap.forEach((oldId, newId) {
      final pending = _messages.remove(oldId);
      if (pending == null || pending.isEmpty) return;
      final target = _messages.putIfAbsent(newId, () => []);
      for (final m in pending) {
        if (!target.any((existing) => existing.id == m.id)) target.add(m);
      }
    });

    final wasVoiceChannel = connectedVoiceChannelId;

    origin.adoptStructure(
      newName: (data['name'] as String? ?? origin.name).trim(),
      newDescription: data['description'] as String? ?? origin.description,
      newColorHex: data['colorHex'] as String? ?? origin.colorHex,
      newChannels: newChannels,
      newRevision: incomingRevision,
    );

    // O canal ativo pode ter deixado de existir na estrutura verdadeira.
    if (origin.id == activeServerId && !newChannels.any((c) => c.id == activeChannelId)) {
      final remapped = remap[activeChannelId];
      activeChannelId = remapped ??
          newChannels
              .firstWhere((c) => c.type == ChannelType.text, orElse: () => newChannels.first)
              .id;
    }

    _saveServers();
    _saveChatHistory();
    notifyListeners();

    // Se estávamos numa sala de voz que só existia na estrutura provisória, o
    // usuário está sozinho numa sala que ninguém mais enxerga: avisa e sai.
    if (wasVoiceChannel != null && !newChannels.any((c) => c.id == wasVoiceChannel)) {
      voiceErrorMessage =
          'Os canais deste servidor foram sincronizados. Entre novamente na sala de voz.';
      disconnectVoice();
    }
  }

  void _processNetworkPayload(Map<String, dynamic> data, Server origin) {
    final action = data['action'] as String?;
    if (action == 'server_info') {
      _processServerInfoPayload(data, origin);
      return;
    }
    if (action == 'history_snapshot') {
      _processHistorySnapshot(data, origin);
      return;
    }
    if (action == 'request_server_info') {
      if (origin.ownerId == currentUser.id && data['requestedBy'] != currentUser.id) {
        _publishServerInfo(origin);
      }
      return;
    }
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
        // Mensagem vinda de versão anterior chega sem data. Sem um valor real
        // ela nunca entraria no retrato de histórico nem contaria como não
        // lida, então é datada na chegada.
        if (newMsg.sentAt <= 0) {
          newMsg.sentAt = DateTime.now().millisecondsSinceEpoch;
        }

        final destino = _messages.putIfAbsent(actualChannelId, () => []);
        if (!destino.any((m) => m.id == newMsg.id)) {
          destino.add(newMsg);
          if (destino.length > _channelMessageCap) {
            destino.removeRange(0, destino.length - _channelMessageCap);
          }
          _saveChatHistory();
          // Passa a servir esta mensagem a quem entrar depois.
          _scheduleHistoryPublish(origin.id);

          if (newMsg.authorId.isNotEmpty && newMsg.authorId != currentUser.id) {
            _registerKnownAuthor(newMsg);
            _saveKnownUsers();
            _trackMemberSlots(origin, newMsg.authorId);

            // Avisa quando a mensagem marca este usuário. Só para mensagem
            // alheia e recém-chegada: um retrato de histórico pode trazer
            // marcações antigas, e elas não devem tocar de novo.
            if (mentionsUser(newMsg.text, currentUser.username)) {
              SoundService.playMention();
            }
          }

          // Se a mensagem caiu no canal aberto com a janela em destaque, o
          // usuário está lendo agora: marcar um não lido que ele está vendo
          // acender e apagar na cara dele não ajudaria ninguém.
          if (actualChannelId == activeChannelId && isWindowFocused && !isHomePageActive) {
            markChannelRead(actualChannelId);
          }
          notifyListeners();
        }
      }
    } else if (action == 'presence') {
      final uid = data['userId'] as String?;
      if (uid != null && uid != currentUser.id) {
        final username = (data['username'] as String? ?? 'Amigo').replaceFirst('@', '').trim();
        final displayName = data['displayName'] as String? ?? username;

        // Presenças retidas chegam com o último estado publicado, que pode ser
        // de dias atrás. O carimbo de tempo da própria mensagem é que decide se
        // aquilo ainda vale como "online" — do contrário a lista de membros se
        // encheria de fantasmas a cada reconexão.
        final sentAt = data['timestamp'] as int? ?? 0;
        final isFresh = sentAt > 0 &&
            DateTime.now().millisecondsSinceEpoch - sentAt < _presenceTtlMs;

        final declared = UserStatus.values.firstWhere(
          (s) => s.name == data['status'],
          orElse: () => UserStatus.online,
        );

        final user = UserModel(
          id: uid,
          username: username,
          displayName: displayName,
          avatar: data['avatar'] as String? ?? '',
          status: isFresh ? declared : UserStatus.offline,
          isMuted: data['isMuted'] as bool? ?? false,
          isDeafened: data['isDeafened'] as bool? ?? false,
          isScreenSharing: isFresh && (data['isScreenSharing'] as bool? ?? false),
          currentVoiceChannelId: isFresh ? data['voiceChannelId'] as String? : null,
          currentVoiceServerId: isFresh ? data['voiceServerId'] as String? : null,
        );
        _onlineUsers[uid] = user;
        _knownUsers[uid] = user;
        _lastSeen[uid] = isFresh ? DateTime.now().millisecondsSinceEpoch : sentAt;
        _saveKnownUsers();

        _trackMemberSlots(origin, uid);
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
    // Publica a estrutura antes de qualquer outra coisa: é o que quem entrar
    // pelo convite vai adotar, inclusive se entrar com o criador offline.
    await _publishServerInfo(newServer);

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

    final leaving = servers[index];
    // Retira a presença retida deste usuário do servidor: sem isso ele
    // continuaria listado como membro para quem entrasse depois.
    if (leaving.inviteCode.trim().isNotEmpty) {
      _mqtt.clearRetained(
        ServerCrypto.presenceSlotTopic(leaving.inviteCode, currentUser.id),
      );
      // O retrato de histórico também é retirado: continuar servindo a
      // conversa de um servidor que já não se integra seria deixar dados
      // nossos guardados num tópico do qual saímos.
      _mqtt.clearRetained(
        ServerCrypto.historySlotTopic(leaving.inviteCode, currentUser.id),
      );
    }

    servers.removeAt(index);
    await _saveServers();
    _subscribeToOwnServers();

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

    // Esqueleto provisório apenas para a interface ter algo enquanto a
    // estrutura verdadeira não chega. Ele é marcado como não sincronizado e
    // nunca é publicado aos outros membros: a estrutura real vem retida no
    // tópico de info do servidor e chega em segundos, mesmo com o criador
    // offline. Antes desta versão, este esqueleto virava a estrutura definitiva
    // deste usuário — e como o nome da sala do LiveKit é o ID do canal, ele
    // entrava numa sala de voz que nenhum outro membro enxergava.
    final joinedServer = Server(
      id: serverId,
      name: 'Servidor ($cleanCode)',
      description: 'Sincronizando com os outros membros...',
      inviteCode: cleanCode,
      isCustom: true,
      colorHex: '38BDF8',
      memberIds: [currentUser.id],
      isSynced: false,
      channels: [
        Channel(id: '$serverId-c-geral', name: 'geral', type: ChannelType.text, topic: 'Canal de texto principal'),
        Channel(id: '$serverId-v-geral', name: '🔊 Sala de Voz', type: ChannelType.voice, userLimit: 15),
      ],
    );

    servers.add(joinedServer);
    await _saveServers();
    _subscribeToOwnServers();
    selectServer(joinedServer.id);
    await _requestServerInfo(joinedServer);
    _sendPresence();
    SoundService.playJoinCall();
    notifyListeners();
    return true;
  }

  void selectChannel(String channelId) {
    activeChannelId = channelId;
    markChannelRead(channelId);
    notifyListeners();
  }

  /// Marca o canal como lido agora, zerando o contador de marcações.
  void markChannelRead(String channelId) {
    if (channelId.isEmpty) return;
    _lastReadAt[channelId] = DateTime.now().millisecondsSinceEpoch;
    _saveReadMarks();
  }

  /// Quantas mensagens ainda não lidas deste canal marcam o usuário atual.
  ///
  /// É derivado das mensagens em mãos, e não de um contador incrementado na
  /// chegada: assim a conta continua certa quando uma marcação antiga entra
  /// pelo histórico recebido de outro membro, e sobrevive a reinícios do app.
  int mentionCountFor(String channelId) {
    final mensagens = _messages[channelId];
    if (mensagens == null || mensagens.isEmpty) return 0;

    final desde = _lastReadAt[channelId] ?? 0;
    final eu = currentUser.username;
    var total = 0;
    for (final m in mensagens) {
      if (m.sentAt <= desde) continue;
      if (m.authorId == currentUser.id || m.isSystem) continue;
      if (mentionsUser(m.text, eu)) total++;
    }
    return total;
  }

  /// Total de marcações não lidas de um servidor inteiro.
  int mentionCountForServer(String serverId) {
    final index = servers.indexWhere((s) => s.id == serverId);
    if (index == -1) return 0;
    var total = 0;
    for (final canal in servers[index].channels) {
      total += mentionCountFor(canal.id);
    }
    return total;
  }

  /// Membros e amigos que podem ser marcados a partir do contexto atual.
  ///
  /// Usada tanto pelo autocompletar do campo de mensagem quanto pela pintura
  /// das marcações, para que só um @ de alguém real ganhe destaque.
  List<UserModel> mentionCandidates() {
    final porHandle = <String, UserModel>{};

    void adicionar(UserModel u) {
      final handle = normalizeHandle(u.username);
      if (handle.isEmpty || handle == normalizeHandle(currentUser.username)) return;
      // Prefere a versão com presença ao vivo, que traz nome de exibição atual.
      porHandle.putIfAbsent(handle, () => u);
    }

    final srv = activeServer;
    if (srv != null) {
      for (final memberId in srv.memberIds) {
        final u = _onlineUsers[memberId] ?? _knownUsers[memberId];
        if (u != null) adicionar(u);
      }
    }
    for (final f in friendsWithLiveStatus) {
      adicionar(f);
    }

    final lista = porHandle.values.toList();
    lista.sort((a, b) =>
        a.displayNameOrUsername.toLowerCase().compareTo(b.displayNameOrUsername.toLowerCase()));
    return lista;
  }

  /// Conjunto de @ que devem ser pintados como marcação válida.
  Set<String> knownMentionHandles() {
    final handles = mentionCandidates().map((u) => normalizeHandle(u.username)).toSet();
    handles.add(normalizeHandle(currentUser.username));
    handles.remove('');
    return handles;
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

    final targetServer = activeServer;
    final targetChannel = activeChannel;
    final targetChannelId = activeChannelId;

    _messages.putIfAbsent(targetChannelId, () => []);
    _messages[targetChannelId]!.add(newMsg);
    clearDraft(targetChannelId);
    // Quem escreve já leu o canal: não faz sentido acumular marcação de si.
    markChannelRead(targetChannelId);
    _saveChatHistory();
    notifyListeners();

    if (targetServer != null) {
      _publishChatMessage(targetServer, targetChannel, targetChannelId, newMsg);
      _scheduleHistoryPublish(targetServer.id);
    }
  }

  /// Publica a mensagem no servidor/canal em que ela foi escrita.
  ///
  /// O destino é capturado no momento do envio, e não lido de novo aqui: a
  /// cifragem é assíncrona e o usuário pode ter trocado de canal no meio do
  /// caminho, o que fazia a mensagem sair endereçada ao canal errado.
  Future<void> _publishChatMessage(
    Server srv,
    Channel? channel,
    String channelId,
    ChatMessage message,
  ) async {
    if (srv.inviteCode.trim().isEmpty) return;

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

    // A caixa de entrada e o canal de presença são derivados do @: sem refazer
    // as assinaturas, o usuário continuaria escutando o endereço antigo e não
    // receberia nenhuma solicitação enviada para o @ novo.
    final oldUser = currentUser.username.trim().toLowerCase();
    if (oldUser.isNotEmpty && oldUser != rawUser) {
      _mqtt.clearRetained(ServerCrypto.userPresenceTopic(oldUser));
      _mqtt.unsubscribe(ServerCrypto.userInboxWildcard(oldUser));
    }

    currentUser.username = rawUser;
    _subscribeToOwnServers();

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

  static final RegExp _handlePattern = RegExp(r'^[a-z0-9_]+$');

  Future<String?> sendFriendRequest(String rawHandle) async {
    final cleanHandle = rawHandle.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
    if (cleanHandle.isEmpty) {
      return 'Por favor, insira uma tag de usuário válida.';
    }
    if (cleanHandle.length < 3 || cleanHandle.length > 20) {
      return 'A tag de usuário deve ter entre 3 e 20 caracteres.';
    }
    if (!_handlePattern.hasMatch(cleanHandle)) {
      return 'A tag pode conter apenas letras, números e underscore (_).';
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

    // Confere com o servidor de contas se o @ existe de verdade. A malha de
    // mensagens não tem diretório de usuários: publicar para uma tag inexistente
    // é publicar num tópico que ninguém escuta, e o app fingia que deu certo.
    final exists = await AuthService.userExists(cleanHandle);
    if (exists == false) {
      return 'Não existe nenhuma conta com a tag @$cleanHandle.';
    }
    if (exists == null) {
      return 'Não foi possível confirmar a tag @$cleanHandle agora. Verifique sua conexão e tente de novo.';
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

    final delivered = await _publishFriendRequest(req);
    if (!delivered) {
      // Sem rede no momento: guarda para reenviar assim que a malha voltar,
      // em vez de perder a solicitação em silêncio.
      _outboxFriendRequests.removeWhere((r) => r.id == req.id);
      _outboxFriendRequests.add(req);
      notifyListeners();
    }

    return null;
  }

  /// Publica a solicitação retida no compartimento do destinatário.
  ///
  /// Retida porque é assim que o pedido chega a quem estava offline: o broker
  /// guarda a última mensagem do compartimento e a entrega quando o
  /// destinatário assinar sua caixa de entrada, mesmo dias depois.
  Future<bool> _publishFriendRequest(FriendRequest req) async {
    final recipient = req.recipientUsername.trim().toLowerCase();
    if (recipient.isEmpty) return false;

    final payload = {
      'action': 'friend_request',
      'request': req.toJson(),
    };
    try {
      final envelope = await ServerCrypto.encryptInboxPayload(recipient, payload);
      return _mqtt.publishEncrypted(
        ServerCrypto.userInboxSlotTopic(recipient, currentUser.username),
        envelope,
        retain: true,
      );
    } catch (e) {
      debugPrint('Erro ao publicar solicitação de amizade: $e');
      return false;
    }
  }

  /// Reenvia as solicitações que ficaram presas enquanto o app estava sem rede.
  Future<void> _flushOutbox() async {
    if (_outboxFriendRequests.isEmpty) return;
    final pending = List<FriendRequest>.from(_outboxFriendRequests);
    for (final req in pending) {
      if (await _publishFriendRequest(req)) {
        _outboxFriendRequests.removeWhere((r) => r.id == req.id);
      }
    }
    notifyListeners();
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

    // O pedido original fica retido no broker até ser respondido; sem limpá-lo
    // ele seria reentregue como "nova solicitação" a cada reconexão.
    _mqtt.clearRetained(
      ServerCrypto.userInboxSlotTopic(currentUser.username, cleanSender),
    );

    // Notifica o remetente de volta que o pedido foi aceito
    final responsePayload = {
      'action': 'friend_accepted',
      'requestId': req.id,
      'acceptedBy': currentUser.toJson(),
    };
    try {
      final envelope = await ServerCrypto.encryptInboxPayload(cleanSender, responsePayload);
      _mqtt.publishEncrypted(
        ServerCrypto.userInboxSlotTopic(cleanSender, currentUser.username),
        envelope,
        retain: true,
      );
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

    _mqtt.clearRetained(
      ServerCrypto.userInboxSlotTopic(currentUser.username, cleanSender),
    );

    final rejectPayload = {
      'action': 'friend_rejected',
      'requestId': req.id,
      'rejectedBy': currentUser.username,
    };
    try {
      final envelope = await ServerCrypto.encryptInboxPayload(cleanSender, rejectPayload);
      _mqtt.publishEncrypted(
        ServerCrypto.userInboxSlotTopic(cleanSender, currentUser.username),
        envelope,
        retain: true,
      );
    } catch (e) {
      debugPrint('Erro ao publicar rejeição de amizade: $e');
    }

    notifyListeners();
  }

  Future<void> cancelFriendRequest(FriendRequest req) async {
    friendRequests.removeWhere((r) => r.id == req.id);
    _outboxFriendRequests.removeWhere((r) => r.id == req.id);
    await _saveFriendRequests();

    // Retira o pedido retido do compartimento do destinatário, senão ele
    // continuaria aparecendo para o outro lado mesmo após o cancelamento.
    final recipient = req.recipientUsername.trim().toLowerCase();
    if (recipient.isNotEmpty &&
        req.senderUsername.toLowerCase() == currentUser.username.toLowerCase()) {
      _mqtt.clearRetained(
        ServerCrypto.userInboxSlotTopic(recipient, currentUser.username),
      );
    }

    notifyListeners();
  }

  Future<void> removeFriend(String friendId) async {
    final removed = friends.where((f) => f.id == friendId).toList();
    friends.removeWhere((f) => f.id == friendId);
    await _saveFriends();
    for (final f in removed) {
      final handle = f.username.trim().toLowerCase();
      if (handle.isNotEmpty) {
        _mqtt.unsubscribe(ServerCrypto.userPresenceTopic(handle));
      }
    }
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
    final oldCode = srv.inviteCode;
    final randomCode = _uuid.v4().substring(0, 8);
    srv.inviteCode = 'papo-$randomCode';
    srv.revision++;
    await _saveServers();

    // Apaga o que ficou retido sob o convite antigo (estrutura e presença):
    // são dados nossos guardados num tópico ao qual não pertencemos mais.
    if (oldCode.trim().isNotEmpty) {
      _mqtt.clearRetained(ServerCrypto.serverInfoTopic(oldCode));
      _mqtt.clearRetained(ServerCrypto.presenceSlotTopic(oldCode, currentUser.id));
      _mqtt.clearRetained(ServerCrypto.historySlotTopic(oldCode, currentUser.id));
    }

    _subscribeToOwnServers();
    await _publishServerInfo(srv);
    await _sendPresence();
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
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _presenceSweepTimer?.cancel();
    _historyPublishTimer?.cancel();
    _voiceService.dispose();
    _mqtt.dispose();
    super.dispose();
  }
}
