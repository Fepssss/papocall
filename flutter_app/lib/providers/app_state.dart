import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;
import '../models/channel.dart';
import '../models/chat_message.dart';
import '../models/direct_conversation.dart';
import '../models/friend_request.dart';
import '../models/role.dart';
import '../models/server.dart';
import '../models/user_model.dart';
import '../services/mqtt_service.dart';
import '../services/direct_crypto.dart';
import '../services/server_crypto.dart';
import '../services/voice_service.dart';
import '../services/sound_service.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../utils/app_log.dart';
import '../utils/app_paths.dart';
import '../utils/app_version.dart';
import '../utils/foto_de_perfil.dart';
import '../utils/mentions.dart';

/// Como a tela de outra pessoa ocupa a janela do PapoCall.
enum ModoDeExibicao { normal, teatro, telaCheia }

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

  /// Como a tela de outra pessoa ocupa a janela.
  ///  - `normal`: palco com a faixa de participantes embaixo;
  ///  - `teatro`: palco grande e participantes flutuando por cima;
  ///  - `telaCheia`: nada mais na janela; Esc devolve o normal.
  ModoDeExibicao modoDeExibicao = ModoDeExibicao.normal;

  /// A escolha que está no ar agora. Guardada para quem transmite poder trocar
  /// uma parte dela — a janela, a resolução, os quadros — sem recomeçar do zero.
  ({String sourceId, String nome, int width, int height, int fps})? transmissaoAtual;

  void definirModoDeExibicao(ModoDeExibicao modo) {
    if (modoDeExibicao == modo) return;
    modoDeExibicao = modo;
    notifyListeners();
  }

  // Configurações de Voz e Áudio, persistidas em settings.json. O VoiceService
  // é quem aplica no motor WebRTC; aqui vive apenas a escolha da pessoa.
  String? audioInputId;
  String? audioOutputId;
  bool noiseSuppression = true;
  bool echoCancellation = true;
  bool autoGainControl = true;
  bool highPassFilter = false;

  /// A webcam escolhida, persistida como as outras. Se ela está de fato
  /// publicando vídeo não é um campo aqui: é o LiveKit que diz, em
  /// [cameraAtiva], porque a publicação da faixa é o fato e um botão apertado
  /// é só a intenção.
  String? cameraId;
  bool get cameraAtiva => _voiceService.cameraAtiva;
  String? get erroDaCamera => _voiceService.erroDaCamera;

  /// O vídeo de uma pessoa da sala, ou `null` se ela não está publicando
  /// nenhum agora — o que inclui a própria pessoa.
  VideoTrack? cameraDe(String username) => _voiceService.cameraDe(username);

  /// Liga ou desliga a câmera e devolve o motivo quando não conseguiu, para o
  /// chamador dizer na tela em vez de deixar o botão aceso sem captura.
  Future<String?> alternarCamera() async {
    final motivo = await _voiceService.alternarCamera();
    notifyListeners();
    return motivo;
  }

  Future<String?> definirCamera(String? id) async {
    cameraId = id;
    _espelharConfigDeAudio();
    await _saveSettings();
    notifyListeners();
    if (!cameraAtiva) return null;
    // Trocar de câmera durante a call só vale alguma coisa se a faixa nova for
    // publicada: desligar e ligar de novo é o caminho que o próprio SDK usa, e
    // é o que garante que a lente antiga parou de capturar.
    final desligou = await _voiceService.alternarCamera();
    if (desligou != null) return desligou;
    return _voiceService.alternarCamera();
  }

  /// O filtro neural (RNNoise) montado no caminho nativo, e o que a máquina
  /// respondeu na última tentativa (`null` = ainda não se tentou nesta execução).
  /// Não é um quinto processador para somar aos outros quatro: ao ligá-lo, a
  /// supressão de ruído do WebRTC sai de cena, porque dois filtros em série
  /// mastigam a fala.
  bool rnnoise = false;
  bool? get rnnoiseAplicado => _voiceService.rnnoiseAplicado;

  /// Liga ou desliga o filtro neural e devolve se está de pé. Uma recusa do
  /// caminho nativo reverte a escolha na hora, para o botão não ficar mentindo.
  Future<bool> definirRnnoise(bool valor) async {
    if (!valor) {
      rnnoise = false;
      _voiceService.rnnoise = false;
      await _voiceService.aplicarRnnoise();
      await _saveSettings();
      notifyListeners();
      return false;
    }
    _voiceService.rnnoise = true;
    final aplicado = await _voiceService.aplicarRnnoise();
    rnnoise = aplicado;
    if (aplicado) noiseSuppression = false;
    _espelharConfigDeAudio();
    await _saveSettings();
    notifyListeners();
    return aplicado;
  }

  // Avisos sonoros, também persistidos. Quem obedece à escolha é o
  // SoundService, que verifica antes de mandar o som ao Windows.
  bool somDeChamada = true;
  bool somDeCompartilhamento = true;

  /// Volume do áudio que vem junto da tela de outra pessoa, de 0 a 1.
  double volumeDaLive = 0.8;

  /// Só há o que regular quando a transmissão do amigo trouxe faixa de áudio.
  bool get liveComAudio => _voiceService.liveComAudio;

  /// Arrastar o controle não pode escrever no disco a cada quadro pintado.
  void ajustarVolumeDaLive(double valor) {
    volumeDaLive = valor.clamp(0.0, 1.0).toDouble();
    _voiceService.definirVolumeDaLive(volumeDaLive);
    notifyListeners();
  }

  /// Grava a escolha, para valer quando o slider soltar.
  Future<void> definirVolumeDaLive(double valor) async {
    ajustarVolumeDaLive(valor);
    await _saveSettings();
  }

  Future<void> definirSomDeChamada(bool valor) async {
    somDeChamada = valor;
    SoundService.definirSons(SoundService.sonsDeChamada, ativos: valor);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> definirSomDeCompartilhamento(bool valor) async {
    somDeCompartilhamento = valor;
    SoundService.definirSons(SoundService.sonsDeCompartilhamento, ativos: valor);
    await _saveSettings();
    notifyListeners();
  }

  /// Troca o microfone. `null` devolve a escolha ao padrão do Windows.
  ///
  /// Aqui só guarda e espelha no serviço: quem aplica no motor WebRTC é a
  /// própria tela de configurações, que já está com a enumeração de
  /// dispositivos na mão. Manter isso separado deixa a escolha testável sem
  /// depender do plugin nativo de áudio.
  Future<void> definirMicrofone(String? id) async {
    audioInputId = id;
    _espelharConfigDeAudio();
    await _saveSettings();
    notifyListeners();
  }

  Future<void> definirSaidaDeAudio(String? id) async {
    audioOutputId = id;
    _espelharConfigDeAudio();
    await _saveSettings();
    notifyListeners();
  }

  Future<void> definirSupressaoDeRuido(bool valor) =>
      _definirProcessadorDeVoz(supressao: valor);

  Future<void> definirCancelamentoDeEco(bool valor) =>
      _definirProcessadorDeVoz(eco: valor);

  Future<void> definirGanhoAutomatico(bool valor) =>
      _definirProcessadorDeVoz(ganho: valor);

  Future<void> definirFiltroPassaAltas(bool valor) =>
      _definirProcessadorDeVoz(passaAltas: valor);

  /// Os quatro processamentos de microfone que o Windows de fato aplica. Um
  /// único caminho de escrita para que salvar, espelhar no serviço e avisar a
  /// interface não se dissociem em quatro cópias.
  Future<void> _definirProcessadorDeVoz({
    bool? supressao,
    bool? eco,
    bool? ganho,
    bool? passaAltas,
  }) async {
    if (supressao != null) noiseSuppression = supressao;
    if (eco != null) echoCancellation = eco;
    if (ganho != null) autoGainControl = ganho;
    if (passaAltas != null) highPassFilter = passaAltas;
    _espelharConfigDeAudio();
    await _saveSettings();
    notifyListeners();
  }

  void _espelharConfigDeAudio() {
    _voiceService.entradaDeAudioId = audioInputId;
    _voiceService.saidaDeAudioId = audioOutputId;
    _voiceService.cameraId = cameraId;
    _voiceService.supressaoDeRuido = noiseSuppression;
    _voiceService.cancelamentoDeEco = echoCancellation;
    _voiceService.ganhoAutomatico = autoGainControl;
    _voiceService.filtroPassaAltas = highPassFilter;
    _voiceService.rnnoise = rnnoise;
  }

  /// Troca a foto de perfil pela imagem escolhida no disco.
  ///
  /// A decodificação de uma foto de celular custa dezenas de milissegundos e
  /// aconteceria no meio da pintura da janela, então o trabalho vai para um
  /// isolate. Devolve o motivo da recusa, ou null quando a foto entrou.
  Future<String?> definirFotoDePerfil(Uint8List bytes) async {
    final resultado = await Isolate.run(() => prepararFotoDePerfil(bytes));
    final nova = resultado.avatar;
    if (nova == null) return resultado.erro ?? 'Não foi possível usar essa imagem.';
    currentUser.avatar = nova;
    await _saveSettings();
    _sendPresence();
    notifyListeners();
    return null;
  }

  Future<void> removerFotoDePerfil() async {
    currentUser.avatar = '';
    await _saveSettings();
    _sendPresence();
    notifyListeners();
  }

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

  // --- Conversas diretas -----------------------------------------------------
  // As mensagens de uma conversa privada vivem em [_messages] com a chave
  // 'dm:<id do contato>', no mesmo arquivo do histórico dos canais. O que mora
  // aqui é só a escolha da conversa aberta e a chave X25519 de cada contato.
  String? activeDirectPeerId;
  final Map<String, String> _chavesDosPares = {};

  /// Nossa própria chave pública, lida uma vez e repetida em cada presença.
  String? _publicaParaAnunciar;
  Timer? _heartbeatTimer;
  Timer? _presenceSweepTimer;
  StreamSubscription? _mqttSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _pingSubscription;

  /// Assinaturas do próprio SDK do LiveKit (falantes, ocupantes, tela).
  ///
  /// Precisam ser guardadas: cada entrada e saída de sala criava um conjunto
  /// novo de listeners que jamais era cancelado, e eles continuavam apontando
  /// para um `Room` morto.
  final List<StreamSubscription> _vozAssinaturas = [];
  Timer? _updateCheckTimer;
  bool _isDisposed = false;

  /// Estado da malha de sincronização (MQTT) exposto à UI.
  ///
  /// Sem isso o app parecia normal enquanto nada entrava nem saía: mensagens,
  /// presenças e solicitações de amizade simplesmente sumiam em silêncio.
  bool isNetworkOnline = false;

  // --- Atualizações ---------------------------------------------------------

  /// Versão mais nova anunciada pelo site, ou null quando não há nenhuma.
  UpdateManifest? atualizacaoDisponivel;

  /// Motivo de a última consulta ter falhado. "Não consegui conferir" e "não há
  /// novidade" são mensagens diferentes para quem está na tela; misturar as
  /// duas faria o app mentir que está tudo em dia.
  String? erroAoVerificarAtualizacao;

  bool verificandoAtualizacao = false;
  bool baixandoAtualizacao = false;

  /// Alguma consulta chegou a terminar sem erro? Sem isso a tela não tem como
  /// dizer "você está em dia" — que só é verdade depois de conferir.
  bool atualizacoesConferidas = false;

  /// Fração do instalador já baixada (0 a 1); null antes de começar.
  double? progressoDoDownload;

  /// Solicitações de amizade enviadas sem rede, aguardando reenvio.
  final List<FriendRequest> _outboxFriendRequests = [];

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

  /// IDs das mensagens que foram apagadas por alguém com permissão.
  ///
  /// O histórico é mesclado por adição: sem esta lista, o retrato retido de
  /// outro membro trazeria de volta a mensagem que acabamos de apagar.
  final Set<String> _deletedMessageIds = {};
  static const int _deletedIdCap = 3000;

  /// Teto de tamanho do retrato cifrado (o recebimento corta em 256 KB).
  static const int _historyMaxBytes = 160 * 1024;

  /// Quantidade de membros anunciada na estrutura do servidor.
  static const int _maxRosterSize = 200;

  Timer? _historyPublishTimer;
  final Set<String> _serversNeedingHistoryPublish = {};

  /// Janela de coalescência das gravações em disco.
  ///
  /// Cada mensagem recebida reescrevia o histórico inteiro e cada presença
  /// reescrevia o retrato dos usuários conhecidos, sempre serializando e
  /// gravando no isolato da interface. Numa conversa movimentada isso encavala
  /// dezenas de escritas redundantes e é um dos motivos de a janela engasgar.
  /// Aqui as chamadas próximas viram uma única escrita.
  static const Duration _folgaDeGravacao = Duration(seconds: 5);
  Timer? _gravacaoEmDiscoTimer;
  bool _historicoSujo = false;

  /// Última latência que a interface ficou sabendo. Serve só para não avisar de
  /// novo o mesmo número.
  int _ultimoPingNotificado = -1;

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
    // Com a raiz de dados redirecionada estamos em teste: nada de abrir socket,
    // cronômetro de heartbeat nem ler a sessão gravada nesta máquina.
    if (dataRootOverride == null) {
      _initVoiceListeners();
      _initDefaultData();
      _initStorageAndNetwork();
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
    if (!focused) {
      // Sair da janela é o último momento certo para guardar o que está sendo
      // escrito: depois disso o aplicativo pode fechar sem nova digitação.
      _rascunhoGravadoEm = null;
      _saveDrafts();
    }
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
    _vozAssinaturas.add(_voiceService.activeSpeakersStream.listen((falantes) {
      // O LiveKit identifica todo mundo por `@username`; o restante do app
      // trabalha com o id da conta. Comparar um com o outro é o que fazia o anel
      // de "está falando" nunca acender, nem para a própria pessoa.
      final nomes = falantes.map(_nomeDaIdentity).toSet();
      var mudou = currentUser.isSpeaking != nomes.contains(currentUser.username.toLowerCase());
      currentUser.isSpeaking = nomes.contains(currentUser.username.toLowerCase());

      for (final user in _onlineUsers.values) {
        final estaFalando = nomes.contains(user.username.toLowerCase());
        if (user.isSpeaking != estaFalando) {
          user.isSpeaking = estaFalando;
          mudou = true;
        }
      }

      if (mudou) notifyListeners();
    }));

    // A sala de voz em si: quem está nela é o que o LiveKit diz, não o que a
    // presença anunciou. É a diferença entre ver o amigo na chamada e ver só o
    // próprio avatar numa sala cheia.
    _vozAssinaturas.add(_voiceService.participantsStream.listen((ocupantes) {
      if (_isDisposed) return;
      _ocupantesDaSala = ocupantes;
      notifyListeners();
    }));

    _vozAssinaturas.add(_voiceService.screenShareTrackStream.listen((track) {
      final wasActive = activeScreenShareTrack != null;
      activeScreenShareTrack = track;
      activeScreenSharePresenter = _voiceService.activeScreenSharePresenter;
      currentUser.isScreenSharing = _voiceService.isScreenSharing;
      if (!wasActive && track != null) {
        isWatchingScreenShare = true;
      }
      // Acabou a transmissão: sair sozinho do teatro e da tela cheia, que sem
      // palco nenhum deixariam a janela preta.
      if (wasActive && track == null) {
        modoDeExibicao = ModoDeExibicao.normal;
      }
      _sendPresence();
      notifyListeners();
    }));

    _pingSubscription?.cancel();
    _pingSubscription = _voiceService.pingStream.listen((ms) {
      if (_isDisposed) return;
      // A batida vem a cada 2,5 s dentro da chamada; avisar a interface também
      // quando o número é o mesmo pintava a HUD inteira de dois em dois
      // segundos por nada.
      if (ms == _ultimoPingNotificado) return;
      _ultimoPingNotificado = ms;
      notifyListeners();
    });

    _voiceService.onDisconnected = () {
      debugPrint('[AppState] LiveKit reportou desconexao da sala de voz.');
      disconnectVoice();
    };
  }

  static String _nomeDaIdentity(String identity) =>
      identity.startsWith('@') ? identity.substring(1).toLowerCase() : identity.toLowerCase();

  /// Quem está na sala de voz neste instante, na fonte verdadeira (LiveKit).
  List<OcupanteDaSala> _ocupantesDaSala = const [];

  /// Os ocupantes da sala traduzidos para um usuário conhecido, na ordem em que
  /// entraram. Quem não está no diretório local ainda aparece: o nome vem do
  /// próprio token, e esconder alguém da chamada por falta de cadastro seria
  /// pior do que mostrá-lo pelo que ele é.
  List<UserModel> get ocupantesDaChamada {
    final lista = <UserModel>[];
    for (final o in _ocupantesDaSala) {
      // O próprio participante local vem sempre pela nossa conta: é o id dela
      // que a interface compara para saber se o cartão é "Você".
      final resolvido = o.isLocal
          ? currentUser
          : _porNomeDeUsuario(o.username) ??
              UserModel(
                id: 'livekit:${o.identity}',
                username: o.username,
                displayName: o.nome.isNotEmpty ? o.nome : o.username,
              );
      lista.add(UserModel(
        id: resolvido.id,
        username: resolvido.username,
        displayName: resolvido.displayName,
        avatar: resolvido.avatar,
        status: UserStatus.online,
        isSpeaking: o.falando,
        isMuted: o.mudo,
        isScreenSharing: o.isLocal ? currentUser.isScreenSharing : resolvido.isScreenSharing,
        isCameraOn: o.temCamera,
        currentVoiceChannelId: connectedVoiceChannelId,
        currentVoiceServerId: activeServerId,
      ));
    }
    return lista;
  }

  /// Procura no diretório local e na lista de amigos pelo `username`.
  UserModel? _porNomeDeUsuario(String nome) {
    final alvo = nome.toLowerCase();
    if (alvo.isEmpty) return null;
    for (final u in _onlineUsers.values) {
      if (u.username.toLowerCase() == alvo) return u;
    }
    for (final u in _knownUsers.values) {
      if (u.username.toLowerCase() == alvo) return u;
    }
    for (final u in friends) {
      if (u.username.toLowerCase() == alvo) return u;
    }
    return null;
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

  /// Raiz dos dados locais. Os testes apontam isto para um diretório
  /// temporário: sem isso, criar um servidor de teste sobrescreveria o
  /// `servers.json` real desta máquina. É a mesma chave usada por todo o app,
  /// inclusive a sessão gravada e o log de diagnóstico.
  @visibleForTesting
  static String? get dataRootOverride => AppPaths.rootOverride;

  @visibleForTesting
  static set dataRootOverride(String? valor) => AppPaths.rootOverride = valor;

  File _getAppFile(String fileName) => AppPaths.file(fileName);

  File _getSettingsFile() => _getAppFile('settings.json');
  File _getServersFile() => _getAppFile('servers.json');
  File _getChatHistoryFile() => _getAppFile('chat_history.json');
  File _getDraftsFile() => _getAppFile('drafts.json');
  File _getFriendsFile() => _getAppFile('friends.json');
  File _getKnownUsersFile() => _getAppFile('known_users.json');
  File _getFriendRequestsFile() => _getAppFile('friend_requests.json');
  File _getReadMarksFile() => _getAppFile('read_marks.json');
  File _getDeletedMessagesFile() => _getAppFile('deleted_messages.json');
  File _getDirectKeysFile() => _getAppFile('dm_keys.json');

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

  /// Adia a gravação do histórico; ver [_folgaDeGravacao].
  void _saveChatHistorySoon() {
    _historicoSujo = true;
    _gravacaoEmDiscoTimer ??= Timer(_folgaDeGravacao, _escreverPendenciasEmDisco);
  }

  Future<void> _escreverPendenciasEmDisco() async {
    _gravacaoEmDiscoTimer?.cancel();
    _gravacaoEmDiscoTimer = null;
    if (_historicoSujo) await _saveChatHistory();
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

  /// Servidores com o som de menção silenciado. É preferência local: não altera
  /// nada do que chega pelo broker, apenas o que toca nesta máquina.
  final Set<String> _mutedServerIds = {};

  bool isServerMuted(String serverId) => _mutedServerIds.contains(serverId);

  void toggleServerMuted(String serverId) {
    if (serverId.isEmpty) return;
    if (!_mutedServerIds.remove(serverId)) _mutedServerIds.add(serverId);
    _saveSettings();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    try {
      final file = _getSettingsFile();
      final data = {
        'user_id': currentUser.id,
        'username': currentUser.username.replaceAll('@', '').trim(),
        'displayName': currentUser.displayName,
        'avatar': currentUser.avatar,
        'mutedServers': _mutedServerIds.toList(),
        'audioInputId': audioInputId,
        'audioOutputId': audioOutputId,
        'cameraId': cameraId,
        'noiseSuppression': noiseSuppression,
        'echoCancellation': echoCancellation,
        'autoGainControl': autoGainControl,
        'highPassFilter': highPassFilter,
        'rnnoise': rnnoise,
        'somDeChamada': somDeChamada,
        'somDeCompartilhamento': somDeCompartilhamento,
        'volumeDaLive': volumeDaLive,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Erro ao salvar configurações: $e');
    }
  }

  final Map<String, String> _drafts = {};
  DateTime? _rascunhoGravadoEm;
  static const Duration _folgaDeRascunho = Duration(seconds: 2);

  String getDraft(String channelId) => _drafts[channelId] ?? '';

  /// O campo de mensagem dispara a cada tecla. Grava o rascunho no máximo uma
  /// vez a cada [_folgaDeRascunho]: escrita em disco por caractere digitado é
  /// o tipo de coisa que faz a janela engasgar enquanto se escreve.
  void setDraft(String channelId, String text) {
    _drafts[channelId] = text;
    final agora = DateTime.now();
    final anterior = _rascunhoGravadoEm;
    if (anterior != null && agora.difference(anterior) < _folgaDeRascunho) return;
    _rascunhoGravadoEm = agora;
    _saveDrafts();
  }

  void clearDraft(String channelId) {
    _drafts.remove(channelId);
    _rascunhoGravadoEm = null;
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
    _historicoSujo = false;
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
                // O disco pode ter ficado com uma mensagem apagada antes de a
                // gravação chegar. O túmulo manda.
                .where((m) => !_deletedMessageIds.contains(m.id))
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

  Future<void> _saveDeletedMessages() async {
    try {
      await _getDeletedMessagesFile().writeAsString(jsonEncode(_deletedMessageIds.toList()));
    } catch (e) {
      debugPrint('Erro ao salvar mensagens apagadas: $e');
    }
  }

  Future<void> _loadDeletedMessages() async {
    try {
      final file = _getDeletedMessagesFile();
      if (!file.existsSync()) return;
      final content = await file.readAsString();
      if (content.isEmpty) return;
      for (final id in (jsonDecode(content) as List)) {
        _deletedMessageIds.add(id.toString());
      }
    } catch (e) {
      debugPrint('Erro ao carregar mensagens apagadas: $e');
    }
  }

  /// Marca uma mensagem como apagada e a remove de onde ela estiver.
  void _forgetMessage(String messageId) {
    if (messageId.isEmpty) return;
    _deletedMessageIds.add(messageId);
    if (_deletedMessageIds.length > _deletedIdCap) {
      // O Set preserva a ordem de inserção, então os primeiros são os mais
      // antigos: são os menos prováveis de voltar a aparecer num retrato.
      final excedente = _deletedMessageIds.length - _deletedIdCap;
      _deletedMessageIds.removeAll(_deletedMessageIds.take(excedente).toList());
    }
    for (final lista in _messages.values) {
      lista.removeWhere((m) => m.id == messageId);
    }
    _saveChatHistorySoon();
    _saveDeletedMessages();
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
        // O access token dura 15 minutos: ao abrir o app ele quase sempre já
        // venceu. Renovar aqui evita que a primeira coisa que o usuário tente
        // fazer depois de abrir o aplicativo falhe por token velho.
        if (!AuthService.accessTokenValid(savedSession.accessToken)) {
          unawaited(renewSession());
        }
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
        // A foto é a escolha da pessoa, não uma credencial: ela é pública e já
        // viaja na presença. Guardada aqui, volta antes do primeiro batimento.
        final salvoAvatar = data['avatar'] as String?;
        if (salvoAvatar != null && salvoAvatar.isNotEmpty) {
          currentUser.avatar = salvoAvatar;
        }
        final muted = data['mutedServers'];
        if (muted is List) {
          _mutedServerIds.addAll(muted.whereType<String>());
        }
        audioInputId = data['audioInputId'] as String?;
        audioOutputId = data['audioOutputId'] as String?;
        cameraId = data['cameraId'] as String?;
        noiseSuppression = data['noiseSuppression'] as bool? ?? true;
        echoCancellation = data['echoCancellation'] as bool? ?? true;
        autoGainControl = data['autoGainControl'] as bool? ?? true;
        highPassFilter = data['highPassFilter'] as bool? ?? false;
        // A escolha volta ligada e é aplicada na entrada da sala. Se a máquina
        // recusar o filtro, `rnnoiseAplicado` fica `false` e a própria linha da
        // interface diz que não está filtrando nada — em vez de acender um botão
        // que não faz nada ou de mexer na escolha da pessoa por trás dela.
        rnnoise = data['rnnoise'] as bool? ?? false;
        somDeChamada = data['somDeChamada'] as bool? ?? true;
        somDeCompartilhamento = data['somDeCompartilhamento'] as bool? ?? true;
        volumeDaLive = (data['volumeDaLive'] as num?)?.toDouble() ?? 0.8;
        _espelharConfigDeAudio();
        _voiceService.definirVolumeDaLive(volumeDaLive);
        SoundService.definirSons(SoundService.sonsDeChamada, ativos: somDeChamada);
        SoundService.definirSons(SoundService.sonsDeCompartilhamento,
            ativos: somDeCompartilhamento);
      }
    } catch (e) {
      debugPrint('Erro ao carregar configurações: $e');
    }

    currentUser.username = currentUser.username.replaceAll('@', '').trim();

    await _loadServers();
    await _loadDeletedMessages();
    await _loadChatHistory();
    await _loadDrafts();
    await _loadFriends();
    await _loadKnownUsers();
    await _loadFriendRequests();
    await _loadReadMarks();
    await _loadDirectKeys();

    // Garante que currentUser faça parte dos servidores carregados
    for (final srv in servers) {
      if (!srv.memberIds.contains(currentUser.id)) {
        srv.memberIds.insert(0, currentUser.id);
      }
    }

    isCheckingAuth = false;
    notifyListeners();

    // A checagem de versão roda com a janela já de pé: o site de atualizações
    // não pode atrasar a abertura do aplicativo.
    _updateCheckTimer =
        Timer(const Duration(seconds: 8), () => verificarAtualizacao());

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
    // Senha dada, token novo na mão: nada mais está em dúvida.
    _renovacaoIncerta = false;
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
    _renovacaoIncerta = false;
    currentUser = session.user.toUserModel();
    isAuthenticated = true;
    // Novas contas iniciam com 0 servidores
    servers = [];
    await _saveServers();
    await _saveSettings();
    await _startNetwork();
    notifyListeners();
  }

  Future<void> logout({String motivo = 'logout do usuário'}) async {
    if (connectedVoiceChannelId != null) {
      await disconnectVoice();
    }
    // Anuncia status offline antes de desconectar
    await _sendPresence(isOffline: true);
    await AuthService.clearSession(motivo: motivo);
    _stopNetwork();
    currentSession = null;
    // As chaves dos contatos são informação desta conta: não têm o que ficar
    // na memória depois de sair. O arquivo continua no disco para o próximo
    // login, e o par privado desta instalação jamais sai dele.
    activeDirectPeerId = null;
    _chavesDosPares.clear();
    _publicaParaAnunciar = null;
    currentUser = UserModel(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      username: 'Usuário',
      status: UserStatus.offline,
    );
    isAuthenticated = false;
    notifyListeners();
  }

  // --- Atualizações ---------------------------------------------------------

  /// Consulta o site e guarda o que ele anuncia como versão mais nova.
  ///
  /// Roda na abertura do aplicativo e no botão "Verificar agora". Falha de
  /// rede apenas fica guardada: nada aqui interrompe o que a pessoa estava
  /// fazendo.
  Future<void> verificarAtualizacao() async {
    if (verificandoAtualizacao || baixandoAtualizacao) return;
    verificandoAtualizacao = true;
    notifyListeners();

    final resultado = await UpdateService.verificar(atual: AppVersion.atual);
    if (_isDisposed) return;

    verificandoAtualizacao = false;
    atualizacaoDisponivel = resultado.manifesto;
    erroAoVerificarAtualizacao = resultado.erro;
    atualizacoesConferidas = resultado.erro == null;
    notifyListeners();
  }

  /// Baixa o instalador novo, confere a soma e reinicia o aplicativo por cima.
  ///
  /// Recusa rodar durante uma chamada: trocar os arquivos no meio de uma
  /// conversa de voz derruba a sala inteira, e essa decisão é de quem usa.
  Future<void> baixarEInstalarAtualizacao() async {
    final manifesto = atualizacaoDisponivel;
    if (manifesto == null || baixandoAtualizacao) return;
    if (connectedVoiceChannelId != null) {
      erroAoVerificarAtualizacao =
          'Saia da chamada de voz antes de atualizar: reiniciar o aplicativo '
          'no meio da chamada derruba a sala para todo mundo.';
      notifyListeners();
      return;
    }

    baixandoAtualizacao = true;
    erroAoVerificarAtualizacao = null;
    progressoDoDownload = 0;
    notifyListeners();

    try {
      final instalador = await UpdateService.baixar(
        manifesto,
        onProgress: (fracao) {
          if (_isDisposed) return;
          progressoDoDownload = fracao;
          notifyListeners();
        },
      );
      await UpdateService.instalarEReiniciar(instalador.path);
      AppLog.write('Update',
          'aplicativo encerrado para instalar a v${manifesto.version}');
      // O processo morre agora: o que estava adiado para o disco precisava
      // sair antes, ou a conversa da última janela se perderia na atualização.
      await _escreverPendenciasEmDisco();
      // O buffer do log morre com o processo: sem escoar antes, a última linha
      // — justamente a que diz que a instalação começou — nunca chega ao disco.
      await AppLog.encerrar();
      // O executável em uso não pode ser substituído por dentro: quem troca os
      // arquivos é o instalador, já destacado deste processo.
      exit(0);
    } catch (e) {
      AppLog.write('Update', 'atualização abortada: $e');
      if (_isDisposed) return;
      baixandoAtualizacao = false;
      progressoDoDownload = null;
      erroAoVerificarAtualizacao =
          e is UpdateException ? e.mensagem : 'Falha ao atualizar: $e';
      notifyListeners();
    }
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
      try {
        _publicaParaAnunciar ??= await DirectCrypto.chavePublicaAtual();
      } catch (e) {
        AppLog.write('Direct', 'sem identidade própria para anunciar: $e');
      }

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
        // A chave de conversa direta vai junto na presença: é por ela que cada
        // amigo consegue cifrar um papo privado sem pedir licença a servidor
        // nenhum. Não é segredo — o segredo é o par privado, que nunca sai
        // desta máquina.
        if (_publicaParaAnunciar != null) 'dmPub': _publicaParaAnunciar,
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
        if (_deletedMessageIds.contains(msg.id)) continue;
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
      _saveChatHistorySoon();
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
  bool _trackMemberSlots(Server origin, String memberId) {
    if (memberId.isEmpty || memberId == currentUser.id) return false;
    if (origin.memberIds.contains(memberId)) return false;

    origin.memberIds.add(memberId);
    _saveServers();
    _mqtt.subscribe(ServerCrypto.presenceSlotTopic(origin.inviteCode, memberId));
    _mqtt.subscribe(ServerCrypto.historySlotTopic(origin.inviteCode, memberId));
    return true;
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

  /// Anuncia a estrutura do servidor.
  ///
  /// A mensagem é retida e o broker guarda apenas a última de cada tópico: se
  /// qualquer membro pudesse publicar, um membro com uma revisão antiga
  /// sobrescreveria a atual e reverteria os canais de todo mundo. Por isso só
  /// publica quem tem permissão de mexer na estrutura.
  ///
  /// Os cargos viajam junto, mas apenas quando é o Dono que publica. Um membro
  /// que escrevesse a própria tabela de cargos no pacote estaria se promovendo
  /// sozinho, e é exatamente contra isso que a checagem do lado de fora
  /// (`adoptRoles`) protege: sem o `publishedBy` batendo com o `ownerId`, a
  /// tabela é ignorada.
  Future<void> _publishServerInfo(Server srv) async {
    if (srv.inviteCode.trim().isEmpty) return;
    if (!srv.isSynced) return; // não propaga uma estrutura provisória

    final isOwner = srv.isOwnedBy(currentUser.id);
    final podeEditarEstrutura = isOwner ||
        srv.hasPermission(currentUser.id, Permissions.manageChannels) ||
        srv.hasPermission(currentUser.id, Permissions.manageServer);
    if (!podeEditarEstrutura) return;

    final payload = {
      'action': 'server_info',
      'serverId': srv.id,
      'name': srv.name,
      'description': srv.description,
      'colorHex': srv.colorHex,
      'ownerId': srv.ownerId,
      'publishedBy': currentUser.id,
      'channels': srv.channels.map((c) => c.toJson()).toList(),
      if (isOwner) 'roles': srv.roles.map((r) => r.toJson()).toList(),
      if (isOwner) 'memberRoles': srv.memberRoles,
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
        await _processInboxPayload(data);
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

  /// Processa eventos da caixa de entrada pessoal: amizades e conversa direta.
  Future<void> _processInboxPayload(Map<String, dynamic> data) async {
    final action = data['action'] as String?;
    if (action == 'dm') {
      await _processDirectMessage(data);
      return;
    }
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

  /// Aplica um estado de presença recebido, de um servidor ou da caixa de
  /// presença de um amigo.
  ///
  /// Dois canais descrevem o mesmo usuário e cada um sabe só uma parte: o
  /// heartbeat do servidor [servidorDoPacote] cala a voz de propósito quando a
  /// pessoa está em outro servidor, e a presença pessoal é global. Misturá-los
  /// sem critério era o que fazia alguém desaparecer da sala de voz na tela do
  /// outro sem ter saído — o pacote do servidor vizinho, mais novo, apagava o que
  /// o servidor da chamada acabava de dizer.
  ///
  /// A idade anunciada pelo remetente decide o que é "agora": [_lastSeen] guarda
  /// o carimbo do pacote, e a varredura de presença quem está offline. Uma cópia
  /// retida antiga que chega depois de uma recente continua sendo prova de que
  /// ninguém publica ali há muito tempo.
  ///
  /// E a gravação em disco deixou de ser por pacote: um heartbeat por membro a
  /// cada 10 segundos reescrevia o diretório inteiro por nada.
  ///
  /// Devolve `true` quando o resultado muda algo na tela. A marca de tempo fica
  /// de fora da comparação de propósito: ela muda a cada batida do heartbeat e
  /// nunca aparece enquanto a pessoa está online, então compará-la reacenderia
  /// a árvore inteira a cada pacote, mesmo sem nada visível ter mudado.
  bool _aplicarPresenca(UserModel user, int sentAt, {String? servidorDoPacote}) {
    final uid = user.id;
    final anterior = _onlineUsers[uid];
    _lastSeen[uid] = sentAt > 0 ? sentAt : DateTime.now().millisecondsSinceEpoch;

    final conhecido = _knownUsers[uid];
    final mudouIdentidade = conhecido == null ||
        conhecido.username != user.username ||
        conhecido.displayName != user.displayName ||
        conhecido.avatar != user.avatar;
    _knownUsers[uid] = user;
    if (mudouIdentidade) _saveKnownUsers();

    // O pacote só sabe de chamada se veio do servidor onde a pessoa está na voz,
    // ou se é o pessoal, que sempre sabe. Fora disso ele não tem o direito de
    // limpar o que o outro canal acaba de anunciar.
    final sabeDaChamada =
        servidorDoPacote == null || servidorDoPacote == anterior?.currentVoiceServerId;
    if (!sabeDaChamada &&
        user.currentVoiceChannelId == null &&
        anterior?.currentVoiceChannelId != null) {
      user.currentVoiceChannelId = anterior!.currentVoiceChannelId;
      user.currentVoiceServerId = anterior.currentVoiceServerId;
      user.isMuted = anterior.isMuted;
      user.isDeafened = anterior.isDeafened;
    }

    final visivel = _resumoVisivel(anterior) != _resumoVisivel(user);
    _onlineUsers[uid] = user;
    return visivel;
  }

  static String _resumoVisivel(UserModel? u) => u == null
      ? 'ausente'
      : '${u.status.name}|${u.displayName}|${u.username}|${u.avatar}'
          '|${u.currentVoiceChannelId}|${u.currentVoiceServerId}'
          '|${u.isMuted}|${u.isDeafened}|${u.isScreenSharing}';

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

      _aplicarPresenca(user, sentAt);

      // Atualiza também o amigo na lista local se encontrado
      final friendIndex = friends.indexWhere((f) => f.username.toLowerCase() == username.toLowerCase());
      if (friendIndex != -1) {
        friends[friendIndex] = user;
      }

      // A chave da conversa direta chega junto da presença, e só depois do
      // cadastro atualizado: é o ID do amigo na nossa lista que nomeia a
      // conversa, então registrar a chave por outro ID deixaria a conversa sem
      // chave justamente para quem a abriu.
      final publicaDoAmigo = data['dmPub'] as String?;
      if (publicaDoAmigo != null && publicaDoAmigo.isNotEmpty && friendIndex != -1) {
        _registrarChaveDoPar(user, publicaDoAmigo);
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

    // Quem entrou pelo convite não conhece o Dono — e é exatamente ele que
    // manda aqui: sem esse campo preenchido, nada de cargos é adotado e nem o
    // túmulo do servidor seria acatado. Preenche-se uma única vez: depois de
    // conhecido, o Dono não se troca por um pacote vindo do broker, que é
    // cifrado com a chave que qualquer membro tem.
    final donoRecebido = data['ownerId'] as String? ?? '';
    if (origin.ownerId.isEmpty && donoRecebido.isNotEmpty) {
      origin.ownerId = donoRecebido;
      _saveServers();
      notifyListeners();
    }

    final rawChannels = data['channels'] as List<dynamic>? ?? [];
    final incomingRevision = data['revision'] as int? ?? 1;

    // Cargos: aceitos apenas de quem é o Dono deste servidor, e nunca de uma
    // revisão mais velha que a que já temos. Sem as duas condições, um membro
    // se promoveria publicando a própria tabela, ou um pacote velho regravado
    // do broker derrubaria um cargo recém-revogado.
    final rawRoles = data['roles'] as List<dynamic>?;
    final publishedBy = data['publishedBy'] as String? ?? '';
    if (rawRoles != null && origin.isOwnedBy(publishedBy) && incomingRevision >= origin.revision) {
      final rawMemberRoles = (data['memberRoles'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, value.toString()),
          ) ??
          <String, String>{};
      origin.adoptRoles(
        newRoles: rawRoles.map((r) => ServerRole.fromJson(r as Map<String, dynamic>)).toList(),
        newMemberRoles: rawMemberRoles,
      );
      _saveServers();
      notifyListeners();
    }

    if (rawChannels.isEmpty) return;

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
    _saveChatHistorySoon();
    notifyListeners();

    // Se estávamos numa sala de voz que só existia na estrutura provisória, o
    // usuário está sozinho numa sala que ninguém mais enxerga: avisa e sai.
    if (wasVoiceChannel != null && !newChannels.any((c) => c.id == wasVoiceChannel)) {
      voiceErrorMessage =
          'Os canais deste servidor foram sincronizados. Entre novamente na sala de voz.';
      disconnectVoice();
    }
  }

  /// Porta de entrada do lado receptor do protocolo, para os testes de
  /// autorização (quem pode publicar cargos, túmulo e expulsão).
  @visibleForTesting
  void processNetworkPayload(Map<String, dynamic> data, Server origin) =>
      _processNetworkPayload(data, origin);

  /// Porta de entrada da caixa de entrada pessoal, para exercê-la sem broker.
  @visibleForTesting
  Future<void> processInboxPayload(Map<String, dynamic> data) =>
      _processInboxPayload(data);

  /// Porta de entrada da presença de amigo, que é de onde vem a chave da
  /// conversa privada.
  @visibleForTesting
  void processFriendPresencePayload(Map<String, dynamic> data) =>
      _processFriendPresencePayload(data);

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
    if (action == 'server_destroyed') {
      // O túmulo chega retido no mesmo tópico da estrutura. Aceitá-lo de
      // qualquer um seria permitir que um membro apagasse o servidor na máquina
      // de todos os outros; só a palavra do Dono desfaz o servidor.
      final publisher = data['publishedBy'] as String? ?? '';
      if (publisher.isEmpty) return;
      // Um esqueleto criado por convite recente não tem Dono conhecido e nunca
      // viu estrutura sincronizada: para ele vale o túmulo em que o publicador
      // se declara dono, porque é a única informação que restou daquele
      // servidor. Sem isso, a pessoa ficaria com um servidor morto e vazio na
      // barra lateral para sempre.
      final donoDeclarado = data['ownerId'] as String? ?? '';
      final aceito = origin.isOwnedBy(publisher) ||
          (!origin.isSynced && origin.ownerId.isEmpty && donoDeclarado == publisher);
      if (!aceito) return;
      _forgetServer(origin);
      return;
    }
    if (action == 'member_kicked') {
      final target = data['targetUserId'] as String? ?? '';
      if (target.isEmpty || target != currentUser.id) return;
      final publisher = data['publishedBy'] as String? ?? '';
      if (publisher == currentUser.id) return;
      // Mesma razão do túmulo: a ordem só vale se quem a deu tinha a permissão
      // de expulsar naquele servidor.
      if (!origin.hasPermission(publisher, Permissions.kickMembers)) return;
      _forgetServer(origin);
      return;
    }
    if (action == 'message_delete') {
      _processMessageDelete(data, origin);
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
        if (!_deletedMessageIds.contains(newMsg.id) &&
            !destino.any((m) => m.id == newMsg.id)) {
          destino.add(newMsg);
          if (destino.length > _channelMessageCap) {
            destino.removeRange(0, destino.length - _channelMessageCap);
          }
          // Escrita adiada: o retrato retido no broker traz estas mensagens de
          // volta na próxima inicialização, então nenhuma delas se perde aqui.
          _saveChatHistorySoon();
          // Passa a servir esta mensagem a quem entrar depois.
          _scheduleHistoryPublish(origin.id);

          if (newMsg.authorId.isNotEmpty && newMsg.authorId != currentUser.id) {
            _registerKnownAuthor(newMsg);
            _saveKnownUsers();
            _trackMemberSlots(origin, newMsg.authorId);

            // Avisa quando a mensagem marca este usuário. Só para mensagem
            // alheia e recém-chegada: um retrato de histórico pode trazer
            // marcações antigas, e elas não devem tocar de novo.
            if (mentionsUser(newMsg.text, currentUser.username) && !isServerMuted(origin.id)) {
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
        final visivel = _aplicarPresenca(user, sentAt, servidorDoPacote: origin.id);
        final novoMembro = _trackMemberSlots(origin, uid);

        // Batida de heartbeat de membro que continua exatamente onde estava não
        // é notícia para a tela: reacender a árvore a cada uma delas era o que
        // mantinha o aplicativo desenhando o servidor inteiro parado.
        if (visivel || novoMembro) notifyListeners();
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

  /// Estrutura com a qual todo servidor nasce. Não há escolha de template:
  /// uma base única torna os canais algo que se administra depois, pelos
  /// cargos, em vez de uma decisão irrevogável tomada na criação.
  static List<Channel> defaultChannels(String serverId) => [
        Channel(id: '$serverId-c-geral', name: 'geral', type: ChannelType.text, topic: 'Bate-papo geral'),
        Channel(id: '$serverId-c-anuncios', name: 'anúncios', type: ChannelType.text, topic: 'Comunicados do servidor'),
        Channel(id: '$serverId-v-geral', name: '🔊 Sala de Voz', type: ChannelType.voice, userLimit: 15),
      ];

  Future<Server> createServer({
    required String name,
    String description = '',
    String colorHex = '22C55E',
  }) async {
    final randomCode = _uuid.v4().substring(0, 8);
    final inviteCode = 'papo-$randomCode';
    final topicHash = ServerCrypto.topicIdFor(inviteCode);
    final serverId = 'srv-$topicHash';

    final channels = defaultChannels(serverId);

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
      roles: ServerRole.defaults(),
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

  /// Sai deste servidor nesta máquina. O servidor continua existindo para os
  /// demais membros — quem quer acabar com ele para todos usa [destroyServer].
  Future<bool> deleteServer(String serverId) async {
    final srv = serverById(serverId);
    if (srv == null) return false;
    _forgetServer(srv);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Cargos e permissões
  // ---------------------------------------------------------------------------

  Server? serverById(String serverId) {
    for (final s in servers) {
      if (s.id == serverId) return s;
    }
    return null;
  }

  /// Toda mudança de estrutura precisa subir a revisão e ser republicada: o
  /// receptor só troca a sua tabela quando chega algo mais novo, então uma
  /// revisão parada no tempo faria o cargo novo nunca chegar a ninguém.
  Future<void> _propagateStructure(Server srv) async {
    srv.revision++;
    await _saveServers();
    await _publishServerInfo(srv);
    notifyListeners();
  }

  /// A regra anti-escalada: ninguém entrega a outro um poder que não tem. Sem
  /// isso, um Moderador com 'gerenciar_cargos' se faria Dono de fato criando um
  /// cargo com todas as permissões e se atribuindo a ele.
  bool _possoConceder(Server srv, Set<String> permissions) {
    for (final p in permissions) {
      if (!srv.hasPermission(currentUser.id, p)) return false;
    }
    return true;
  }

  bool can(String serverId, String permission) =>
      serverById(serverId)?.hasPermission(currentUser.id, permission) ?? false;

  /// Nome exibido do cargo. O Dono não é um cargo da tabela: é quem criou o
  /// servidor, e aparece como tal em qualquer lista.
  String roleNameFor(String serverId, String userId) {
    final srv = serverById(serverId);
    if (srv == null) return 'Membro';
    if (srv.isOwnedBy(userId)) return 'Dono';
    return srv.roleOf(userId)?.name ?? 'Membro';
  }

  /// Cor do cargo, ou null para quem não tem cargo nenhum — assim a interface
  /// pinta de cor só quem realmente foi promovido.
  Color? roleColorFor(String serverId, String userId) {
    final srv = serverById(serverId);
    if (srv == null || srv.isOwnedBy(userId)) return null;
    return srv.roleOf(userId)?.color;
  }

  List<ServerRole> rolesOf(String serverId) => serverById(serverId)?.roles ?? const [];

  /// Só mexe num cargo quem tem, pessoalmente, todos os poderes dele. Do
  /// contrário, um Moderador que ganhasse 'gerenciar_cargos' reescreveria o
  /// Administrador para se colocar acima do Dono — ou apagaria o cargo alheio
  /// para tirar poder de quem está acima dele.
  bool canEditRole(String serverId, String roleId) {
    final srv = serverById(serverId);
    if (srv == null) return false;
    if (!srv.hasPermission(currentUser.id, Permissions.manageRoles)) return false;
    final role = _roleIn(srv, roleId);
    if (role == null) return false;
    return _possoConceder(srv, role.permissions);
  }

  Future<bool> createRole(
    String serverId, {
    required String name,
    required String colorHex,
    required Set<String> permissions,
  }) async {
    final srv = serverById(serverId);
    if (srv == null) return false;
    if (!srv.hasPermission(currentUser.id, Permissions.manageRoles)) return false;
    if (!_possoConceder(srv, permissions)) return false;

    srv.roles.add(
      ServerRole(
        id: 'role-${_uuid.v4().substring(0, 8)}',
        name: name.trim(),
        colorHex: colorHex,
        permissions: permissions,
      ),
    );
    await _propagateStructure(srv);
    return true;
  }

  Future<bool> updateRole(
    String serverId,
    String roleId, {
    String? name,
    String? colorHex,
    Set<String>? permissions,
  }) async {
    final srv = serverById(serverId);
    if (srv == null) return false;
    final role = _roleIn(srv, roleId);
    if (role == null) return false;
    if (!canEditRole(serverId, roleId)) return false;

    if (permissions != null && !_possoConceder(srv, permissions)) return false;

    if (name != null && name.trim().isNotEmpty) role.name = name.trim();
    if (colorHex != null) role.colorHex = colorHex;
    if (permissions != null) {
      role.permissions
        ..clear()
        ..addAll(permissions);
    }
    await _propagateStructure(srv);
    return true;
  }

  ServerRole? _roleIn(Server srv, String roleId) {
    for (final r in srv.roles) {
      if (r.id == roleId) return r;
    }
    return null;
  }

  Future<bool> deleteRole(String serverId, String roleId) async {
    final srv = serverById(serverId);
    if (srv == null) return false;
    if (!canEditRole(serverId, roleId)) return false;

    final index = srv.roles.indexWhere((r) => r.id == roleId);
    if (index == -1) return false;
    srv.roles.removeAt(index);
    // Ninguém fica apontando para um cargo que deixou de existir.
    srv.memberRoles.removeWhere((_, assigned) => assigned == roleId);
    await _propagateStructure(srv);
    return true;
  }

  /// Atribui (ou remove, com roleId nulo) o cargo de um membro.
  Future<bool> assignRole(String serverId, String userId, String? roleId) async {
    final srv = serverById(serverId);
    if (srv == null) return false;
    if (!srv.hasPermission(currentUser.id, Permissions.manageRoles)) return false;
    // O Dono não tem cargo: tirá-lo do comando por um clique seria possível se
    // ele entrasse nesse mapa.
    if (srv.isOwnedBy(userId)) return false;

    if (roleId == null || roleId.isEmpty) {
      srv.memberRoles.remove(userId);
      await _propagateStructure(srv);
      return true;
    }

    final role = _roleIn(srv, roleId);
    if (role == null) return false;
    if (!_possoConceder(srv, role.permissions)) return false;

    srv.memberRoles[userId] = roleId;
    await _propagateStructure(srv);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Canais
  // ---------------------------------------------------------------------------

  /// Texto ASCII do nome do canal para compor o ID.
  ///
  /// O ID é o nome da sala no LiveKit e circula entre os membros, então ele
  /// precisa ser estável e legível: sem a transliteração, "Táticas" virava
  /// `t-ticas` (o acento contava como separador).
  static String _slugDoCanal(String nome) {
    const transliteracao = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n', 'ý': 'y',
    };
    var s = nome.toLowerCase();
    transliteracao.forEach((de, para) => s = s.replaceAll(de, para));
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return s.isEmpty ? 'canal' : s;
  }

  Future<bool> addChannel(
    String serverId, {
    required String name,
    required ChannelType type,
    String topic = '',
    int userLimit = 15,
  }) async {
    final srv = serverById(serverId);
    if (srv == null) return false;
    if (!srv.hasPermission(currentUser.id, Permissions.manageChannels)) return false;

    final limpo = name.trim();
    if (limpo.isEmpty) return false;
    if (srv.channels.any((c) => c.name.toLowerCase() == limpo.toLowerCase())) return false;

    // O ID nasce aqui e é este ID que circula no server_info: como a sala do
    // LiveKit leva o nome do canal, um ID gerado por cabeça em cada máquina
    // faria dois membros falarem em salas diferentes dentro do mesmo servidor.
    final id = '${srv.id}-${type == ChannelType.voice ? 'v' : 'c'}-${_slugDoCanal(limpo)}-${_uuid.v4().substring(0, 4)}';

    srv.channels.add(
      Channel(
        id: id,
        name: limpo,
        type: type,
        topic: topic.trim(),
        userLimit: type == ChannelType.voice ? userLimit : 15,
      ),
    );
    await _propagateStructure(srv);
    return true;
  }

  Future<bool> deleteChannel(String serverId, String channelId) async {
    final srv = serverById(serverId);
    if (srv == null) return false;
    if (!srv.hasPermission(currentUser.id, Permissions.manageChannels)) return false;
    // Um servidor sem canal nenhum não tem onde escrever nem para onde ir.
    if (srv.channels.length <= 1) return false;

    Channel? canal;
    for (final c in srv.channels) {
      if (c.id == channelId) {
        canal = c;
        break;
      }
    }
    if (canal == null) return false;
    srv.channels.remove(canal);

    _messages.remove(channelId);
    _lastReadAt.remove(channelId);
    await _saveChatHistory();
    await _saveReadMarks();

    if (connectedVoiceChannelId == channelId) {
      await disconnectVoice();
    }
    if (activeChannelId == channelId) {
      final fallback = srv.channels.firstWhere(
        (c) => c.type == ChannelType.text,
        orElse: () => srv.channels.first,
      );
      activeChannelId = fallback.id;
    }
    await _propagateStructure(srv);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Membros
  // ---------------------------------------------------------------------------

  /// Expulsa um membro. O aviso vai pelo tópico de chat, que só os membros do
  /// servidor conseguem decifrar; quem recebe confere a permissão de quem
  /// publicou antes de acatar, e o expulsado remove o servidor do próprio
  /// cliente — os dados dele no broker são limpos por ele mesmo, porque a
  /// presença e o histórico de cada um são compartimentos assinados por ele.
  Future<bool> kickMember(String serverId, String userId) async {
    final srv = serverById(serverId);
    if (srv == null) return false;
    if (!srv.hasPermission(currentUser.id, Permissions.kickMembers)) return false;
    if (srv.isOwnedBy(userId) || userId == currentUser.id) return false;

    srv.memberIds.remove(userId);
    srv.memberRoles.remove(userId);
    await _saveServers();

    if (srv.inviteCode.trim().isNotEmpty) {
      try {
        final envelope = await ServerCrypto.encryptPayload(srv.inviteCode, {
          'action': 'member_kicked',
          'serverId': srv.id,
          'targetUserId': userId,
          'publishedBy': currentUser.id,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        _mqtt.publishEncrypted(ServerCrypto.chatTopic(srv.inviteCode), envelope);
      } catch (e) {
        debugPrint('Erro ao avisar expulsão de $userId: $e');
      }
    }
    notifyListeners();
    return true;
  }

  /// Apaga uma mensagem de qualquer autor. O próprio autor sempre pode apagar a
  /// sua; apagar a alheia exige a permissão.
  bool canDeleteMessage(String serverId, ChatMessage message) {
    if (message.isSystem) return false;
    if (message.authorId == currentUser.id) return true;
    return serverById(serverId)?.hasPermission(currentUser.id, Permissions.manageMessages) ?? false;
  }

  Future<bool> deleteMessage(String serverId, String channelId, String messageId) async {
    final srv = serverById(serverId);
    if (srv == null) return false;

    final mensagens = _messages[channelId];
    if (mensagens == null) return false;
    ChatMessage? msg;
    for (final m in mensagens) {
      if (m.id == messageId) {
        msg = m;
        break;
      }
    }
    if (msg == null) return false;

    final ehMinha = msg.authorId == currentUser.id;
    if (!ehMinha && !srv.hasPermission(currentUser.id, Permissions.manageMessages)) return false;

    _forgetMessage(messageId);
    _scheduleHistoryPublish(serverId);

    if (srv.inviteCode.trim().isNotEmpty) {
      try {
        final envelope = await ServerCrypto.encryptPayload(srv.inviteCode, {
          'action': 'message_delete',
          'serverId': srv.id,
          'channelId': channelId,
          'messageId': messageId,
          'publishedBy': currentUser.id,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        _mqtt.publishEncrypted(ServerCrypto.chatTopic(srv.inviteCode), envelope);
      } catch (e) {
        debugPrint('Erro ao publicar apagamento de mensagem: $e');
      }
    }
    notifyListeners();
    return true;
  }

  /// Apaga uma mensagem a pedido de outro membro.
  ///
  /// A ordem só é acatada quando dá para provar aqui que quem a deu tinha
  /// direito: a mensagem precisa estar nesta máquina, e o autor dela tem de ser
  /// quem publicou ou quem publicado tem de deter a permissão. Sem a mensagem
  /// local não há como conferir a autoria, e marcar um ID qualquer como apagado
  /// seria permitir que um membro censurasse a conversa dos outros.
  void _processMessageDelete(Map<String, dynamic> data, Server origin) {
    final messageId = data['messageId'] as String? ?? '';
    if (messageId.isEmpty || _deletedMessageIds.contains(messageId)) return;
    final publisher = data['publishedBy'] as String? ?? '';
    if (publisher.isEmpty || publisher == currentUser.id) return;

    final channelId = data['channelId'] as String?;
    final candidatos = channelId == null
        ? _messages.values
        : (_messages[channelId] == null ? const <List<ChatMessage>>[] : [_messages[channelId]!]);

    ChatMessage? alvo;
    for (final lista in candidatos) {
      for (final m in lista) {
        if (m.id == messageId) {
          alvo = m;
          break;
        }
      }
      if (alvo != null) break;
    }
    if (alvo == null) return;

    final autorizado = alvo.authorId == publisher ||
        origin.hasPermission(publisher, Permissions.manageMessages);
    if (!autorizado) return;

    _forgetMessage(messageId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Destruição do servidor
  // ---------------------------------------------------------------------------

  /// Exclui o servidor em definitivo, para todos. Só o Dono pode.
  ///
  /// Não basta apagar da própria máquina: a estrutura e os compartimentos de
  /// presença e histórico de cada membro ficam retidos no broker, e qualquer um
  /// que entrasse pelo convite ainda os encontraria. Por isso a exclusão limpa
  /// todos os tópicos retidos que o Dono é capaz de endereçar e deixa no lugar
  /// da estrutura um túmulo — a última mensagem retida do tópico de info passa
  /// a ser o aviso de destruição, que faz quem estava offline apagar ao voltar.
  Future<bool> destroyServer(String serverId) async {
    final index = servers.indexWhere((s) => s.id == serverId);
    if (index == -1) return false;
    final srv = servers[index];
    if (!srv.isOwnedBy(currentUser.id)) return false;

    final code = srv.inviteCode.trim();
    if (code.isNotEmpty) {
      await _publishServerDestroyed(srv);
      for (final memberId in srv.memberIds) {
        _mqtt.clearRetained(ServerCrypto.presenceSlotTopic(code, memberId));
        _mqtt.clearRetained(ServerCrypto.historySlotTopic(code, memberId));
      }
      _mqtt.clearRetained(ServerCrypto.presenceTopic(code));
      _mqtt.clearRetained(ServerCrypto.historyTopic(code));
    }

    _forgetServer(srv);
    return true;
  }

  Future<void> _publishServerDestroyed(Server srv) async {
    if (srv.inviteCode.trim().isEmpty) return;
    try {
      final envelope = await ServerCrypto.encryptPayload(srv.inviteCode, {
        'action': 'server_destroyed',
        'serverId': srv.id,
        'publishedBy': currentUser.id,
        'ownerId': srv.ownerId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      _mqtt.publishEncrypted(ServerCrypto.serverInfoTopic(srv.inviteCode), envelope, retain: true);
    } catch (e) {
      debugPrint('Erro ao publicar destruição de ${srv.id}: $e');
    }
  }

  /// Tira o servidor desta máquina e apaga o que é nosso sobre ele: histórico,
  /// marcas de leitura e as assinaturas. Usada pelo Dono que destruiu e pelo
  /// membro que foi expulso ou recebeu o túmulo.
  void _forgetServer(Server srv) {
    // Retira a presença e o retrato de histórico deste usuário do servidor: sem
    // isso ele continuaria listado como membro para quem entrasse depois, e os
    // dados dele seguiriam servidos num tópico do qual ele saiu. Cada um limpa
    // os próprios compartimentos porque são assinados com a chave própria.
    final code = srv.inviteCode.trim();
    if (code.isNotEmpty) {
      _mqtt.clearRetained(ServerCrypto.presenceSlotTopic(code, currentUser.id));
      _mqtt.clearRetained(ServerCrypto.historySlotTopic(code, currentUser.id));
    }

    servers.removeWhere((s) => s.id == srv.id);
    for (final canal in srv.channels) {
      _messages.remove(canal.id);
      _lastReadAt.remove(canal.id);
    }
    if (connectedVoiceChannelId != null && srv.channels.any((c) => c.id == connectedVoiceChannelId)) {
      disconnectVoice();
    }
    _saveServers();
    _saveChatHistory();
    _saveReadMarks();

    if (servers.isEmpty) {
      activeServerId = '';
      activeChannelId = '';
      isHomePageActive = true;
    } else if (activeServerId == srv.id) {
      selectServer(servers.first.id);
    }
    _subscribeToOwnServers();
    _sendPresence();
    notifyListeners();
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

  /// Onde o chat de um canal deve abrir: o índice da primeira mensagem que
  /// ainda não tinha sido vista, ou null para abrir no fim da conversa.
  ///
  /// Precisava ser calculado aqui, no instante da troca, e não na tela: a
  /// próxima linha move a marca de leitura para agora, e depois disso não existe
  /// mais como saber onde a pessoa tinha parado.
  ({String canal, int? indice})? aberturaDoCanal;

  /// Índice da primeira mensagem ainda não vista do canal, ou null quando não
  /// há nada pendente.
  ///
  /// Canal nunca aberto devolve null de propósito: "nada lido" ali são duzentas
  /// mensagens para trás, e o lugar certo para abrir é o fim, não o começo.
  int? primeiroNaoLidoDe(String channelId) {
    final desde = _lastReadAt[channelId];
    if (desde == null || desde <= 0) return null;
    final mensagens = _messages[channelId];
    if (mensagens == null || mensagens.isEmpty) return null;
    for (var i = 0; i < mensagens.length; i++) {
      if (mensagens[i].sentAt > desde) return i;
    }
    return null;
  }

  void selectChannel(String channelId) {
    if (channelId != activeChannelId) {
      aberturaDoCanal = (canal: channelId, indice: primeiroNaoLidoDe(channelId));
    }
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

  /// Marca todos os canais de um servidor como lidos de uma vez, gravando o
  /// disco uma única vez: chamar markChannelRead por canal faria uma escrita
  /// por canal pelo simples fechar de um menu.
  void markServerRead(String serverId) {
    final index = servers.indexWhere((s) => s.id == serverId);
    if (index == -1) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final canal in servers[index].channels) {
      _lastReadAt[canal.id] = now;
    }
    _saveReadMarks();
    notifyListeners();
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

  /// Nada segurava ninguém de apertar Enter trinta vezes em cinco segundos e
  /// encher o canal. O respiro é curto o bastante para não aparecer no uso
  /// normal de uma conversa e longo o bastante para o spam não passar.
  static const Duration _respiroPorMensagem = Duration(milliseconds: 800);
  static const int _tetoNaJanela = 12;
  static const Duration _janelaDeObservacao = Duration(seconds: 15);
  final List<DateTime> _enviosRecentes = [];

  /// Quantos milissegundos faltam para o próximo envio poder sair. Zero libera.
  ///
  /// Não há cronômetro na tela: o que a pessoa vê é o botão de envio ficar
  /// mudo por um instante e o texto continuar no campo, esperando.
  int esperaParaEnviarMs([DateTime? momento]) {
    final agora = momento ?? DateTime.now();
    final recentes =
        _enviosRecentes.where((t) => agora.difference(t) <= _janelaDeObservacao).toList();
    if (recentes.isEmpty) return 0;

    var ms = 0;
    final descanso = agora.difference(recentes.last);
    if (descanso < _respiroPorMensagem) {
      ms = (_respiroPorMensagem - descanso).inMilliseconds;
    }
    if (recentes.length >= _tetoNaJanela) {
      final ateLiberar =
          (_janelaDeObservacao - agora.difference(recentes.first)).inMilliseconds;
      if (ateLiberar > ms) ms = ateLiberar;
    }
    return ms > 0 ? ms : 0;
  }

  bool get podeEnviar => esperaParaEnviarMs() == 0;

  void _registrarEnvio([DateTime? momento]) {
    final agora = momento ?? DateTime.now();
    _enviosRecentes.removeWhere((t) => agora.difference(t) > _janelaDeObservacao);
    _enviosRecentes.add(agora);
  }

  /// Manda uma mensagem para o canal aberto. Devolve false quando o respiro de
  /// envio segurou a mensagem — aí o chamador mantém o texto no campo.
  bool sendMessage(String text, {String? gifUrl, String? replyToAuthor, String? replyToText}) {
    final corpo = text.trim();
    final gif = gifUrl?.trim() ?? '';
    if (corpo.isEmpty && gif.isEmpty) return false;
    // Um GIF que não é endereço não é imagem: a mensagem sairia vazia para o
    // outro lado.
    if (gif.isNotEmpty && !(gif.startsWith('https://') || gif.startsWith('http://'))) return false;
    if (esperaParaEnviarMs() > 0) return false;
    _registrarEnvio();

    final newMsg = ChatMessage(
      id: _uuid.v4(),
      authorId: currentUser.id,
      author: currentUser.displayNameOrUsername,
      authorDisplayName: currentUser.displayName,
      authorUsername: currentUser.username,
      authorAvatar: currentUser.avatar,
      text: corpo,
      timestamp: 'Hoje às ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      gifUrl: gif.isEmpty ? null : gif,
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
    return true;
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
    // Ensurdecer tem de silenciar o que entra. Até aqui o botão só mutava o
    // microfone, que é o que sai: o ícone trocava e a pessoa continuava ouvindo
    // a sala inteira.
    _voiceService.definirEnsurdecido(currentUser.isDeafened);
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

  // ===========================================================================
  // CONVERSAS DIRETAS — papo privado entre duas pessoas, sem servidor no meio
  // ===========================================================================

  /// Onde uma conversa privada mora dentro do histórico. O prefixo 'dm:' nunca
  /// colide com um ID de canal, então a mesma lista de arquivos serve os dois.
  static String directKey(String peerId) => 'dm:$peerId';

  List<ChatMessage> directMessages(String peerId) =>
      List.unmodifiable(_messages[directKey(peerId)] ?? const []);

  /// A conversa aberta neste momento, ou null quando a pessoa está vendo a lista.
  UserModel? get activeDirectPeer => _amigoPorId(activeDirectPeerId);

  void openDirectChat(String peerId) {
    if (_amigoPorId(peerId) == null) return;
    activeDirectPeerId = peerId;
    markChannelRead(directKey(peerId));
    notifyListeners();
  }

  void closeDirectChat() {
    if (activeDirectPeerId == null) return;
    activeDirectPeerId = null;
    notifyListeners();
  }

  /// Mensagens recebidas desta conversa que a pessoa ainda não abriu.
  int unreadDirectFor(String peerId) {
    final mensagens = _messages[directKey(peerId)];
    if (mensagens == null || mensagens.isEmpty) return 0;
    final desde = _lastReadAt[directKey(peerId)] ?? 0;
    var total = 0;
    for (final m in mensagens) {
      if (m.sentAt > desde && m.authorId != currentUser.id && !m.isSystem) total++;
    }
    return total;
  }

  /// Amigos com conversa em andamento, da mais recente para a mais antiga.
  List<ConversaDireta> get directConversations {
    final conversas = <ConversaDireta>[];
    for (final f in friends) {
      final mensagens = _messages[directKey(f.id)];
      if (mensagens == null || mensagens.isEmpty) continue;
      conversas.add(ConversaDireta(
        peer: f,
        ultima: mensagens.last,
        naoLidas: unreadDirectFor(f.id),
      ));
    }
    conversas.sort((a, b) => b.ultima.sentAt.compareTo(a.ultima.sentAt));
    return conversas;
  }

  /// Chave pública X25519 do contato, tal como ele mesmo a anunciou.
  String? chavePublicaDoPar(String peerId) => _chavesDosPares[peerId];

  /// Impressão digital da chave do contato, para conferir por outro canal.
  String? impressaoDoPar(String peerId) {
    final chave = _chavesDosPares[peerId];
    return chave == null ? null : DirectCrypto.impressao(chave);
  }

  /// Por que a conversa não pode enviar agora, ou null se pode.
  ///
  /// Existe porque a mensagem privada não fica guardada em lugar nenhum: não há
  /// servidor de mensagens diretas, o broker só repete o que publicar agora.
  /// Prometer entrega para um contato offline seria mentira.
  String? bloqueioDeEnvioDireto(String peerId) {
    if (!isNetworkOnline) return 'Sem conexão com a malha. Aguarde a reconexão para enviar.';
    final amigo = _amigoPorId(peerId);
    if (amigo == null) return 'Este contato não está mais na sua lista de amigos.';
    if (_chavesDosPares[peerId] == null) {
      return 'Aguarde ${amigo.displayNameOrUsername} abrir o PapoCall: é na presença dele que a chave da conversa chega.';
    }
    final aoVivo = _onlineUsers[peerId];
    if (aoVivo == null || aoVivo.status == UserStatus.offline) {
      return '${amigo.displayNameOrUsername} está offline. A conversa privada acontece com os dois on-line, como o chat dos servidores.';
    }
    return null;
  }

  /// Envia uma mensagem privada. Devolve o motivo quando não foi possível, ou
  /// null quando a mensagem saiu.
  Future<String?> sendDirectMessage(String peerId, String text) async {
    final conteudo = text.trim();
    if (conteudo.isEmpty) return null;

    final bloqueio = bloqueioDeEnvioDireto(peerId);
    if (bloqueio != null) return bloqueio;

    // O mesmo respiro do canal vale aqui; a interface desabilita o botão antes
    // de chegar neste ponto, e a recusa só aparece se alguém chamar direto.
    if (esperaParaEnviarMs() > 0) return 'Espere um instante antes de mandar outra.';
    _registrarEnvio();

    final amigo = _amigoPorId(peerId)!;
    final agora = DateTime.now();
    final mensagem = ChatMessage(
      id: _uuid.v4(),
      authorId: currentUser.id,
      author: currentUser.displayNameOrUsername,
      authorDisplayName: currentUser.displayName,
      authorUsername: currentUser.username,
      authorAvatar: currentUser.avatar,
      text: conteudo,
      timestamp: 'Hoje às ${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}',
    );

    final chave = directKey(peerId);
    _messages.putIfAbsent(chave, () => []).add(mensagem);
    markChannelRead(chave);
    await _saveChatHistory();
    notifyListeners();

    if (!await _publicarMensagemDireta(amigo, mensagem)) {
      // Não saiu, então não aparece. Numa conversa privada, deixar o balão na
      // tela fingindo que o amigo leu é pior do que recusar o envio.
      _messages[chave]?.removeWhere((m) => m.id == mensagem.id);
      await _saveChatHistory();
      notifyListeners();
      return 'A malha caiu neste instante. A mensagem não saiu; tente de novo.';
    }
    return null;
  }

  Future<bool> _publicarMensagemDireta(UserModel amigo, ChatMessage mensagem) async {
    final publicaDoPar = _chavesDosPares[amigo.id];
    if (publicaDoPar == null) return false;
    try {
      final minha = await DirectCrypto.identidade();
      final envelope = await DirectCrypto.cifrar(
        minha: minha,
        de: currentUser.username,
        para: amigo.username,
        publicaDoParB64: publicaDoPar,
        conteudo: {
          'id': mensagem.id,
          'texto': mensagem.text,
          'enviadoEm': mensagem.sentAt,
        },
      );

      // Duas camadas, cada uma com um trabalho: o envelope acima só o par abre;
      // o transporte abaixo é o que faz a mensagem caber na caixa de entrada
      // cifrada pelo nome de usuário, onde ela já é esperada.
      final transporte = await ServerCrypto.encryptInboxPayload(amigo.username, {
        'action': 'dm',
        'envelope': envelope,
        'timestamp': mensagem.sentAt,
      });
      return _mqtt.publishEncrypted(
        ServerCrypto.userInboxDmTopic(amigo.username, currentUser.username),
        transporte,
      );
    } catch (e) {
      AppLog.write('Direct', 'falha ao publicar mensagem direta: $e');
      return false;
    }
  }

  /// Abre um envelope de conversa direta recém-chegado.
  Future<void> _processDirectMessage(Map<String, dynamic> data) async {
    final bruto = data['envelope'] as String?;
    if (bruto == null) return;

    final aberto = await DirectCrypto.decifrar(
      minha: await DirectCrypto.identidade(),
      meuUsuario: currentUser.username,
      envelope: bruto,
    );
    if (aberto == null) return;

    // Só um amigo tem a chave desta conversa; se ele não está mais na lista, a
    // conversa acabou e o que chega daqui pra frente é lixo.
    final amigo = _amigoPorUsuario(aberto.de);
    if (amigo == null) {
      AppLog.write('Direct', 'mensagem descartada: remetente não é amigo (${aberto.de})');
      return;
    }

    final chave = directKey(amigo.id);
    final destino = _messages.putIfAbsent(chave, () => []);

    final id = aberto.conteudo['id'] as String? ?? '';
    if (id.isEmpty || destino.any((m) => m.id == id)) return;
    if (_deletedMessageIds.contains(id)) return;

    _registrarChaveDoPar(amigo, aberto.publicaDoEnvelope);

    // O carimbo vem do relógio de quem enviou. Adiantado, ele deixaria a
    // conversa marcada como não lida para sempre; atrasado, enterraria a
    // mensagem no meio do histórico antigo. Vale o menor dos dois.
    final enviadoEm = aberto.conteudo['enviadoEm'] as int? ?? 0;
    final agora = DateTime.now().millisecondsSinceEpoch;

    final mensagem = ChatMessage(
      id: id,
      authorId: amigo.id,
      author: amigo.displayNameOrUsername,
      authorDisplayName: amigo.displayName,
      authorUsername: amigo.username,
      authorAvatar: amigo.avatar,
      text: (aberto.conteudo['texto'] as String? ?? '').trim(),
      timestamp: 'Hoje às ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      sentAt: (enviadoEm <= 0 || enviadoEm > agora) ? agora : enviadoEm,
    );

    destino.add(mensagem);
    if (destino.length > _channelMessageCap) {
      destino.removeRange(0, destino.length - _channelMessageCap);
    }
    await _saveChatHistory();

    if (activeDirectPeerId == amigo.id && isWindowFocused && isHomePageActive) {
      markChannelRead(chave);
    } else {
      SoundService.playMention();
    }
    notifyListeners();
  }

  /// Registra a chave pública que o contato anuncia — na presença dele, ou
  /// dentro do envelope que ele acabou de mandar.
  ///
  /// Trocar de chave no meio de uma conversa é exatamente o que um atacante
  /// enfiado no meio faria, então a troca ganha uma linha na conversa em vez de
  /// passar em branco. A troca legítima também existe: é o que acontece quando o
  /// amigo reinstala o aplicativo e o par X25519 dele nasce de novo.
  void _registrarChaveDoPar(UserModel amigo, String publicaB64) {
    if (!_ehChaveX25519(publicaB64)) {
      AppLog.write('Direct', 'chave anunciada por ${amigo.username} descartada: não é X25519');
      return;
    }
    final anterior = _chavesDosPares[amigo.id];
    if (anterior == publicaB64) return;
    _chavesDosPares[amigo.id] = publicaB64;
    _saveDirectKeys();
    if (anterior == null) return;

    final destino = _messages[directKey(amigo.id)];
    if (destino == null || destino.isEmpty) return;
    destino.add(ChatMessage(
      id: 'chave-mudou-${amigo.id}-${DateTime.now().millisecondsSinceEpoch}',
      authorId: '',
      author: 'PapoCall',
      text: 'A chave deste contato mudou. Impressão agora: '
          '${DirectCrypto.impressao(publicaB64)} — confira com ele por outro canal.',
      timestamp: destino.last.timestamp,
      isSystem: true,
    ));
    _saveChatHistory();
  }

  /// Uma chave pública X25519 tem exatamente 32 bytes.
  ///
  /// A presença de onde ela vem é texto que qualquer um pode publicar num broker
  /// público. Guardar qualquer string dali é levar lixo para a cifragem e para a
  /// tela, onde `impressao()` arrebentaria.
  bool _ehChaveX25519(String publicaB64) {
    try {
      return base64Decode(publicaB64).length == 32;
    } on FormatException {
      return false;
    }
  }

  UserModel? _amigoPorId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final f in friends) {
      if (f.id == id) return f;
    }
    return null;
  }

  UserModel? _amigoPorUsuario(String usuario) {
    final alvo = usuario.trim().toLowerCase();
    if (alvo.isEmpty) return null;
    for (final f in friends) {
      if (f.username.trim().toLowerCase() == alvo) return f;
    }
    return null;
  }

  Future<void> _saveDirectKeys() async {
    try {
      await _getDirectKeysFile().writeAsString(jsonEncode(_chavesDosPares));
    } catch (e) {
      debugPrint('Erro ao salvar chaves de conversa: $e');
    }
  }

  Future<void> _loadDirectKeys() async {
    try {
      final file = _getDirectKeysFile();
      if (!file.existsSync()) return;
      final content = await file.readAsString();
      if (content.isEmpty) return;
      final raw = jsonDecode(content);
      if (raw is! Map) return;
      _chavesDosPares.clear();
      raw.forEach((k, v) {
        if (k is String && v is String && _ehChaveX25519(v)) _chavesDosPares[k] = v;
      });
    } catch (e) {
      debugPrint('Erro ao carregar chaves de conversa: $e');
    }
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
    // A conversa privada morre junto com a amizade: sem o outro lado na lista
    // não há para quem cifrar, e manter a conversa aqui seria esconder do dono
    // um papo que ele não pode mais continuar.
    if (activeDirectPeerId == friendId) activeDirectPeerId = null;
    if (_chavesDosPares.remove(friendId) != null) _saveDirectKeys();
    _messages.remove(directKey(friendId));
    _lastReadAt.remove(directKey(friendId));
    await _saveChatHistory();
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

    // Quem abre a lista pode não estar no roster que chegou pelo ar: servidor
    // de outra pessoa ainda não sincronizado. Em vez de se inserir no model
    // durante o build, a lista de exibição é que se monta com a gente na
    // frente — o model fica como a rede entregou.
    final ids = srv.memberIds.contains(currentUser.id)
        ? srv.memberIds
        : [currentUser.id, ...srv.memberIds];

    final online = <UserModel>[];
    final offline = <UserModel>[];

    for (final memberId in ids) {
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
        // O servidor pode listar contas que já foram excluídas. Mostrar o ID
        // cru na tela não ajuda o dono a decidir nada; o id continua no model
        // para o "expulsar" funcionar.
        offline.add(UserModel(
          id: memberId,
          username: 'conta-removida',
          displayName: 'Conta removida',
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

  Future<AuthSession?>? _renovacaoEmAndamento;

  /// Um envio do token de renovação que saiu desta máquina sem resposta.
  ///
  /// O backend rotaciona a cada uso: se aquele pedido chegou e a resposta se
  /// perdeu, o token em `session.dat` já está queimado lá fora e o reenvio cai
  /// na detecção de reuso, que revoga todas as sessões da conta e é o que
  /// derrubava o login. A dúvida vale só para este processo: reiniciar o app
  /// tenta de novo com um token que o usuário ainda tem no disco, e é a saída
  /// honesta para uma situação em que nenhum dos dois lados tem certeza.
  bool _renovacaoIncerta = false;

  /// Renova o access token da sessão HTTP, no máximo uma renovação por vez.
  ///
  /// O backend rotaciona o refresh token a cada uso e, se receber um token já
  /// consumido, revoga TODAS as sessões da conta (TOKEN_REUSE_DETECTED). Duas
  /// renovações paralelas deslogavam o usuário por completo — era o efeito
  /// "minha conta sumiu".
  Future<AuthSession?> renewSession() {
    final emAndamento = _renovacaoEmAndamento;
    if (emAndamento != null) return emAndamento;
    final futura = _renewSessionOnce();
    _renovacaoEmAndamento = futura;
    futura.whenComplete(() {
      if (identical(_renovacaoEmAndamento, futura)) _renovacaoEmAndamento = null;
    });
    return futura;
  }

  Future<AuthSession?> _renewSessionOnce() async {
    final antiga = currentSession;
    if (antiga == null) return null;
    if (_renovacaoIncerta) {
      AppLog.write('Auth',
          'renovação bloqueada: o último envio do token de renovação não teve resposta e pode já ter sido consumido');
      return null;
    }

    final resultado = await AuthService.refreshSession(antiga);
    switch (resultado.outcome) {
      case RefreshOutcome.renewed:
        final renovada = resultado.session!;
        _renovacaoIncerta = false;
        currentSession = AuthSession(
          accessToken: renovada.accessToken,
          refreshToken: renovada.refreshToken,
          user: currentSession?.user ?? renovada.user,
        );
        return currentSession;
      case RefreshOutcome.rejected:
        AppLog.write('Auth', 'login encerrado pelo servidor: ${resultado.reason}');
        unawaited(logout(
          motivo: 'o servidor recusou o token de renovação (${resultado.reason})',
        ));
        return null;
      case RefreshOutcome.uncertain:
        // Não apaga nada e não insiste: a próxima oportunidade de enviar este
        // token é um processo novo, aberto pelo usuário.
        _renovacaoIncerta = true;
        return null;
      case RefreshOutcome.transientFailure:
        // O pedido nem saiu daqui: a sessão continua válida e a próxima
        // tentativa é igual a esta. Derrubar o login por um capricho da rede é
        // o que fazia a conta "desaparecer".
        return null;
    }
  }

  /// O servidor cujo catálogo contém este canal — ou `null` se nenhum dos meus
  /// servidores o tem.
  ///
  /// É a checagem de participação que a interface precisava: a presença de um amigo
  /// traz o id do canal em que ele está, e o id do canal é o nome da sala no
  /// LiveKit. Sem perguntar "esse canal é meu?", qualquer presença de amigo vira
  /// convite para entrar e ouvir.
  Server? servidorDoCanal(String? canalId) {
    if (canalId == null || canalId.isEmpty) return null;
    for (final srv in servers) {
      if (srv.channels.any((c) => c.id == canalId)) return srv;
    }
    return null;
  }

  /// Entra num canal de voz e devolve o motivo quando não conseguiu, para o
  /// chamador mostrar na tela. Sem isso a falha era silenciosa: o ícone
  /// simplesmente voltava para o estado desconectado.
  Future<String?> connectVoice(String channelId) async {
    if (isConnectingVoice) return null;
    if (connectedVoiceChannelId == channelId) return null;

    // Só se entra no canal de voz de um servidor em que se está. O nome da sala no
    // LiveKit é o id do canal e o backend assina token para qualquer sala, então
    // sem esta guarda bastava conhecer o id de um canal alheio — a presença de um
    // amigo entrega o dele — para ouvir a conversa de gente que não te chamou.
    if (servidorDoCanal(channelId) == null) {
      return 'Você não faz parte do servidor desse canal de voz.';
    }

    isConnectingVoice = true;
    voiceErrorMessage = null;
    notifyListeners();

    try {
      // A identity do LiveKit passa a ser definida pelo backend a partir do JWT,
      // e não mais montada aqui, para impedir personificação de outro usuário.
      // O access token dura 15 minutos: renovar antes de pedir a autorização é
      // o que evita o "sessão expirou" no meio de uma tentativa de entrar.
      AuthSession? sessao = currentSession;
      if (sessao != null &&
          !AuthService.accessTokenValid(sessao.accessToken)) {
        sessao = await renewSession() ?? sessao;
        // Sem token válido e com a renovação em dúvida, insistir só acumula
        // requisições que o backend vai recusar. Melhor dizer logo o que
        // resolver: abrir o app de novo recomeça a tentativa do zero.
        if (_renovacaoIncerta &&
            !AuthService.accessTokenValid(sessao.accessToken)) {
          return 'O servidor não confirmou sua sessão. Feche e abra o PapoCall de novo; '
              'se continuar, saia e entre com sua senha.';
        }
      }

      final success = await _voiceService.joinVoice(
        roomName: channelId,
        accessToken: sessao?.accessToken ?? '',
        renewSession: renewSession,
      );

      if (success) {
        connectedVoiceChannelId = channelId;
        currentUser.currentVoiceChannelId = channelId;
        voiceErrorMessage = null;
        // A pessoa pode ter saído da sala ensurdecida e voltar assim: a faixa
        // de cada amigo já chega desligada, sem esperar por um clique no botão.
        await _voiceService.definirEnsurdecido(currentUser.isDeafened);
        SoundService.playJoinCall();
      } else {
        connectedVoiceChannelId = null;
        currentUser.currentVoiceChannelId = null;
        voiceErrorMessage = _voiceService.lastErrorMessage;
        if (voiceErrorMessage == null || voiceErrorMessage!.isEmpty) {
          voiceErrorMessage = 'Falha ao conectar à chamada de voz.';
        }
      }
    } catch (e) {
      debugPrint('Erro ao conectar no LiveKit para o canal $channelId: $e');
      connectedVoiceChannelId = null;
      currentUser.currentVoiceChannelId = null;
      voiceErrorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isConnectingVoice = false;
      _sendPresence();
      notifyListeners();
    }
    return voiceErrorMessage;
  }

  void setWatchingScreenShare(bool watching) {
    if (isWatchingScreenShare == watching) return;
    isWatchingScreenShare = watching;
    if (watching) {
      SoundService.playScreenWatchStart();
    } else {
      // Sair da tela do outro também fecha o teatro e a tela cheia: quem volta
      // a entrar na transmissão espera encontrá-la do jeito padrão.
      SoundService.playScreenWatchStop();
      modoDeExibicao = ModoDeExibicao.normal;
    }
    notifyListeners();
  }

  Future<bool> startScreenShare(
    String sourceId, {
    String nomeDaFonte = '',
    int width = 1920,
    int height = 1080,
    int fps = 30,
  }) async {
    final ok = await _voiceService.startScreenShare(
      sourceId,
      width: width,
      height: height,
      fps: fps,
    );
    if (ok) {
      transmissaoAtual = (
        sourceId: sourceId,
        nome: nomeDaFonte,
        width: width,
        height: height,
        fps: fps,
      );
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

  /// Recomeça a transmissão com outra janela, resolução ou framerate.
  ///
  /// Trocar a faixa no lugar (o `restartTrack` do SDK) preservaria o cartão de
  /// quem assiste, mas ele pega a primeira faixa do stream novo — com o áudio do
  /// sistema junto, isso pode ser o áudio no lugar do vídeo. Parar e publicar de
  /// novo é o caminho que não depende de sorte: quem assiste vê o cartão piscar
  /// e voltar, e o que volta é o que foi pedido.
  Future<bool> reconfigurarTransmissao({
    String? sourceId,
    String? nomeDaFonte,
    int? width,
    int? height,
    int? fps,
  }) async {
    final atual = transmissaoAtual;
    if (!isScreenSharing || atual == null) return false;
    await _voiceService.stopScreenShare();
    currentUser.isScreenSharing = false;
    return startScreenShare(
      sourceId ?? atual.sourceId,
      nomeDaFonte: nomeDaFonte ?? atual.nome,
      width: width ?? atual.width,
      height: height ?? atual.height,
      fps: fps ?? atual.fps,
    );
  }

  Future<void> stopScreenShare() async {
    await _voiceService.stopScreenShare();
    currentUser.isScreenSharing = false;
    transmissaoAtual = null;
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
    transmissaoAtual = null;
    modoDeExibicao = ModoDeExibicao.normal;
    _ocupantesDaSala = const [];
    _ultimoPingNotificado = -1;
    _sendPresence();
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final s in _vozAssinaturas) {
      s.cancel();
    }
    _vozAssinaturas.clear();
    _pingSubscription?.cancel();
    _pingSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _mqttSubscription?.cancel();
    _mqttSubscription = null;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _presenceSweepTimer?.cancel();
    _historyPublishTimer?.cancel();
    _gravacaoEmDiscoTimer?.cancel();
    _gravacaoEmDiscoTimer = null;
    _updateCheckTimer?.cancel();
    _voiceService.dispose();
    _mqtt.dispose();
    super.dispose();
  }
}
