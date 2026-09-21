import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'mqtt_credential_service.dart';

/// Mensagem bruta recebida do broker, ainda cifrada.
/// A decifragem acontece em [ServerCrypto], não aqui: este serviço é apenas
/// transporte e nunca tem acesso ao conteúdo em claro.
class MqttEnvelope {
  final String topic;
  final String payload;

  const MqttEnvelope({required this.topic, required this.payload});
}

class MqttService {
  /// Teto de tamanho por mensagem recebida (256 KB).
  static const int _maxPayloadBytes = 256 * 1024;

  /// Espera entre tentativas de reconexão, com teto de 30s.
  static const int _retryBaseSeconds = 3;
  static const int _retryMaxSeconds = 30;

  // ----------------------------------------------------------------------------
  // Onde o broker fica.
  //
  // Não existe mais host de broker escrito neste arquivo: o endereço chega do
  // backend junto da credencial (`MQTT_HOST` no servidor), e estes defaults de
  // build só servem para desenvolvimento e para o caso de o painel ainda não ter
  // sido configurado. Nenhum deles é segredo — é um endereço público.
  // ----------------------------------------------------------------------------
  static const String _hostFromEnv = String.fromEnvironment('PAPOCALL_MQTT_HOST');
  static const int _portaFromEnv =
      int.fromEnvironment('PAPOCALL_MQTT_PORT', defaultValue: 8883);
  static const String _wssFromEnv = String.fromEnvironment('PAPOCALL_MQTT_WSS_URL');
  static const int _wssPortaFromEnv =
      int.fromEnvironment('PAPOCALL_MQTT_WSS_PORT', defaultValue: 8084);

  /// Injetado por `AppState`: pede uma credencial nova ao backend.
  ///
  /// Fica sendo callback, e não o serviço chamando o serviço, por dois motivos:
  /// quem tem o access token e sabe renová-lo é o `AppState` (a renovação é
  /// single-flight, e renovar por conta própria queimaria o refresh token), e assim
  /// o ciclo de reconexão continua dono da própria decisão de quando buscar.
  Future<MqttCredential?> Function()? obterCredencial;

  /// Renova com esta antecedência para a troca não cair no meio de um CONNECT.
  static const Duration _folgaDeRenovacao = Duration(minutes: 5);

  MqttCredential? _credencial;

  String get _host {
    final informada = _credencial?.host ?? '';
    return informada.isNotEmpty ? informada : _hostFromEnv;
  }

  int get _porta {
    final informada = _credencial?.port ?? 0;
    return informada > 0 ? informada : _portaFromEnv;
  }

  String get _wssUrl {
    final informada = _credencial?.wssUrl ?? '';
    return informada.isNotEmpty ? informada : _wssFromEnv;
  }

  /// A porta do WSS vem embutida na URL; sem ela, usa-se a do build.
  int get _wssPorta {
    try {
      return Uri.parse(_wssUrl).port;
    } catch (_) {
      return _wssPortaFromEnv;
    }
  }

  MqttServerClient? _client;
  bool _isConnected = false;
  String? _clientId;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _wantsConnection = false;

  final Set<String> _subscribedTopics = {};

  /// Assinatura do stream de mensagens do cliente atual. Precisa ser cancelada
  /// quando o cliente morre, senão cada reconexão acumula um ouvinte órfão.
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final StreamController<MqttEnvelope> _messagesController = StreamController.broadcast();
  Stream<MqttEnvelope> get messageStream => _messagesController.stream;

  /// Emite true/false a cada transição de conectividade com o broker.
  ///
  /// A UI depende disso: até a v1.0.0m uma falha de conexão deixava o app
  /// silenciosamente mudo e surdo, sem nenhum indício visível de que as
  /// mensagens e presenças não estavam saindo nem chegando.
  final StreamController<bool> _connectionController = StreamController.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isConnected => _isConnected;

  void _setConnected(bool value) {
    if (_isConnected == value) return;
    _isConnected = value;
    if (!_connectionController.isClosed) {
      _connectionController.add(value);
    }
  }

  /// Conecta ao broker e mantém a conexão viva indefinidamente.
  ///
  /// Se as duas portas falharem, agenda nova tentativa com backoff: antes, uma
  /// única falha no arranque (rede do usuário ainda subindo, broker saturado)
  /// deixava o app isolado até ser reiniciado.
  Future<bool> connect(String clientId) async {
    _wantsConnection = true;
    _clientId = clientId;
    _retryTimer?.cancel();

    final ok = await _attemptConnect(clientId);
    if (!ok) _scheduleRetry();
    return ok;
  }

  /// Credencial de sessão, buscando uma nova quando não há ou está perto de vencer.
  ///
  /// `null` significa "agora não dá" — o backend frio, uma renovação que falhou,
  /// o logout no meio. Nesse caso a tentativa não parte: um CONNECT sem credencial
  /// num broker que não aceita anônimo só produziria um erro de leitura ambígua,
  /// e o backoff já trata isto como o que é, uma tentativa a mais mais tarde.
  Future<MqttCredential?> _credencialValida() async {
    final atual = _credencial;
    if (atual != null && !atual.expirandoEm(_folgaDeRenovacao)) return atual;

    final buscar = obterCredencial;
    if (buscar == null) {
      debugPrint('[MQTT] Nenhum provedor de credencial injetado; não tento conectar.');
      return null;
    }

    try {
      final nova = await buscar();
      if (nova != null) _credencial = nova;
      return nova;
    } catch (e) {
      debugPrint('[MQTT] Falha ao buscar credencial: $e');
      return null;
    }
  }

  Future<bool> _attemptConnect(String clientId) async {
    _teardownClient();

    final credencial = await _credencialValida();
    if (credencial == null) return false;

    if (_host.isEmpty) {
      debugPrint('[MQTT] Broker não configurado: o servidor não devolveu MQTT_HOST '
          'e o build não recebeu --dart-define=PAPOCALL_MQTT_HOST.');
      return false;
    }

    // Cada tentativa usa um sufixo novo no clientId: o broker derruba a sessão
    // anterior quando o mesmo identificador reaparece, o que geraria um laço de
    // desconexões entre a tentativa nova e a conexão zumbi antiga.
    final base = clientId.length > 4 ? clientId.substring(0, clientId.length - 4) : clientId;
    final attemptId = '$base${DateTime.now().microsecondsSinceEpoch % 10000}';

    // 1. TLS nativo (mqtts) na porta informada pelo backend.
    if (await _tryConnectTls(attemptId, credencial)) return true;

    // 2. Fallback para WebSocket seguro, caso a porta nativa esteja bloqueada na
    //    rede do usuário. Não existe fallback em texto puro, nem aqui nem no
    //    broker: o TLS protege os metadados (quais tópicos, quando, de qual IP)
    //    que a criptografia de conteúdo não esconde.
    if (_wssUrl.isEmpty) {
      debugPrint('[MQTT] Sem URL WSS configurada; não tento o fallback.');
      return false;
    }
    debugPrint('[MQTT] Tentando fallback para WebSocket seguro (wss)...');
    return await _tryConnectWs(attemptId, credencial);
  }

  void _scheduleRetry() {
    if (!_wantsConnection) return;
    _retryTimer?.cancel();

    var seconds = _retryBaseSeconds * (1 << (_retryAttempt > 4 ? 4 : _retryAttempt));
    if (seconds > _retryMaxSeconds) seconds = _retryMaxSeconds;
    _retryAttempt++;

    debugPrint('[MQTT] Reconectando em ${seconds}s (tentativa $_retryAttempt)...');
    _retryTimer = Timer(Duration(seconds: seconds), () async {
      if (!_wantsConnection) return;
      final id = _clientId;
      if (id == null) return;
      final ok = await _attemptConnect(id);
      if (!ok) _scheduleRetry();
    });
  }

  Future<bool> _tryConnectTls(String clientId, MqttCredential credencial) async {
    MqttServerClient? client;
    try {
      client = MqttServerClient(_host, clientId);
      client.port = _porta;
      client.secure = true;
      client.keepAlivePeriod = 20;
      client.autoReconnect = false;
      client.logging(on: false);

      // Sem will: a spec MQTT exige Will QoS 0 quando a Will Flag é 0. Passar
      // withWillQos sem tópico de will faz o broker encerrar o CONNECT sem
      // nunca responder CONNACK — as três portas falhavam igual.
      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(credencial.username, credencial.password)
          .startClean();
      client.connectionMessage = connMessage;

      _configureCallbacks(client);

      final status = await client.connect().timeout(const Duration(seconds: 6));
      if (status?.state == MqttConnectionState.connected) {
        _client = client;
        _retryAttempt = 0;
        _setupMessageListener(client);
        _setConnected(true);
        _resubscribeAll();
        debugPrint('[MQTT] Conectado via TLS nativo ($_host:$_porta) com sucesso!');
        return true;
      }
    } catch (e) {
      debugPrint('[MQTT] Falha na conexão TLS nativa: $e');
    }
    _discard(client);
    return false;
  }

  Future<bool> _tryConnectWs(String clientId, MqttCredential credencial) async {
    MqttServerClient? client;
    try {
      client = MqttServerClient.withPort(_wssUrl, clientId, _wssPorta);
      client.useWebSocket = true;
      client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      client.keepAlivePeriod = 20;
      client.autoReconnect = false;
      client.logging(on: false);

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(credencial.username, credencial.password)
          .startClean();
      client.connectionMessage = connMessage;

      _configureCallbacks(client);

      final status = await client.connect().timeout(const Duration(seconds: 5));
      if (status?.state == MqttConnectionState.connected) {
        _client = client;
        _retryAttempt = 0;
        _setupMessageListener(client);
        _setConnected(true);
        _resubscribeAll();
        debugPrint('[MQTT] Conectado via WebSocket seguro ($_wssUrl) com sucesso!');
        return true;
      }
    } catch (e) {
      debugPrint('[MQTT] Falha na conexão WebSocket: $e');
    }
    _discard(client);
    return false;
  }

  /// Derruba um cliente de uma tentativa que não foi adotada.
  ///
  /// Um connect() que estoura o timeout continua existindo: se ele completar
  /// depois, ocupa o clientId e derruba a conexão boa que veio a seguir.
  void _discard(MqttServerClient? client) {
    if (client == null) return;
    try {
      client.disconnect();
    } catch (_) {}
  }

  void _configureCallbacks(MqttServerClient client) {
    // Callback de uma tentativa já descartada não pode mexer no estado: sem essa
    // guarda, um zumbi atrasado flipava a conectividade da UI e reassinava
    // tópicos no cliente errado.
    bool isCurrent() => identical(_client, client);

    client.onConnected = () {
      debugPrint('[MQTT] Callback: Conectado.');
      if (!isCurrent()) return;
      _setConnected(true);
      _resubscribeAll();
    };
    client.onDisconnected = () {
      debugPrint('[MQTT] Callback: Desconectado.');
      if (!isCurrent()) return;
      _setConnected(false);
      _updatesSub?.cancel();
      _updatesSub = null;
      _client = null;
      // O autoReconnect do pacote está desligado de propósito (ele reinsiste com
      // o mesmo clientId e colide com a tentativa nova), então o backoff próprio
      // é o único caminho de recuperação.
      if (_wantsConnection) _scheduleRetry();
    };
  }

  void _setupMessageListener(MqttServerClient client) {
    // Uma assinatura por cliente: sem cancelar a anterior, cada ciclo de
    // reconexão deixava para trás um listener vivo, o stream controller dele e
    // o socket do cliente morto. Numa rede instável isso cresce sem teto — foi
    // o que o Windows apontou como vazamento de memória no processo.
    _updatesSub?.cancel();
    _updatesSub = client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        final recMess = msg.payload as MqttPublishMessage;

        // O broker já não aceita anônimo, mas continua sendo um repetidor que
        // não confiamos: qualquer cliente com credencial — ou o próprio operador
        // do broker — pode publicar o que quiser. Daí o teto abaixo, que existe
        // para um terceiro não inflar a memória do app, e a verificação de MAC no
        // ServerCrypto, que é o que realmente descarta a mensagem forjada.
        if (recMess.payload.message.length > _maxPayloadBytes) continue;

        // Payload vazio é o marcador de "limpe o retido" deste tópico e não
        // representa mensagem nenhuma.
        if (recMess.payload.message.isEmpty) continue;

        final raw = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        _messagesController.add(MqttEnvelope(topic: msg.topic, payload: raw));
      }
    });
  }

  void _resubscribeAll() {
    if (_client != null && _isConnected) {
      for (final topic in _subscribedTopics) {
        _client!.subscribe(topic, MqttQos.atLeastOnce);
      }
    }
  }

  /// Assina [topic], ainda que ele já esteja na nossa lista.
  ///
  /// Reenviar é de propósito. Com um broker que autoriza, uma assinatura negada é
  /// invisível para nós: sem resposta de erro, "eu já pedi essa assinatura" não é
  /// prova nenhuma de que ela está ativa. Um SUBSCRIBE repetido no mesmo tópico é
  /// idempotente pela spec, e é o que deixa a reconciliação depois de conectar
  /// consertar uma autorização que chegou atrasada.
  void subscribe(String topic) {
    _subscribedTopics.add(topic);
    if (_client != null && _isConnected) {
      _client!.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void unsubscribe(String topic) {
    if (!_subscribedTopics.remove(topic)) return;
    try {
      _client?.unsubscribe(topic);
    } catch (_) {}
  }

  /// Ajusta as assinaturas para exatamente [desired], mexendo só na diferença.
  ///
  /// Reassinar tudo do zero a cada reconexão gerava um par unsubscribe/subscribe
  /// no mesmo tópico: se o ACK do unsubscribe chegasse depois do subscribe, o
  /// broker deixava o app sem aquela assinatura — silenciosamente surdo naquele
  /// servidor ou na própria caixa de entrada.
  void syncSubscriptions(Set<String> desired) {
    final obsolete = _subscribedTopics.difference(desired);
    for (final topic in obsolete) {
      try {
        _client?.unsubscribe(topic);
      } catch (_) {}
    }
    _subscribedTopics.removeAll(obsolete);

    for (final topic in desired) {
      subscribe(topic);
    }
  }

  /// Publica um envelope já cifrado. Este serviço nunca recebe texto em claro.
  ///
  /// [retain] pede ao broker que guarde a última mensagem do tópico e a entregue
  /// a quem assinar depois. É o que faz uma solicitação de amizade ou uma
  /// presença chegar a quem estava offline no instante do envio.
  bool publishEncrypted(String topic, String encryptedEnvelope, {bool retain = false}) {
    if (_client == null || !_isConnected) {
      debugPrint('[MQTT] Tentativa de publicar em $topic com cliente desconectado.');
      return false;
    }
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(encryptedEnvelope);
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: retain);
      return true;
    } catch (e) {
      debugPrint('[MQTT] Erro ao publicar em $topic: $e');
      return false;
    }
  }

  /// Apaga a mensagem retida de um tópico publicando um payload vazio retido.
  bool clearRetained(String topic) {
    if (_client == null || !_isConnected) return false;
    try {
      final empty = MqttClientPayloadBuilder();
      _client!.publishMessage(topic, MqttQos.atLeastOnce, empty.payload!, retain: true);
      return true;
    } catch (e) {
      debugPrint('[MQTT] Erro ao limpar retido de $topic: $e');
      return false;
    }
  }

  void unsubscribeAll() {
    for (final topic in _subscribedTopics) {
      try {
        _client?.unsubscribe(topic);
      } catch (_) {}
    }
    _subscribedTopics.clear();
  }

  void _teardownClient() {
    _updatesSub?.cancel();
    _updatesSub = null;
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
  }

  void disconnect() {
    _wantsConnection = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    _setConnected(false);
    _subscribedTopics.clear();
    _teardownClient();
    // A senha é da sessão de login: encerrada a sessão, nada de guardá-la para a
    // próxima conta que abrir neste aparelho.
    _credencial = null;
  }

  void dispose() {
    disconnect();
    _messagesController.close();
    _connectionController.close();
  }
}
