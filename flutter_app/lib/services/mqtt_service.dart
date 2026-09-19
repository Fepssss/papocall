import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

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

  MqttServerClient? _client;
  bool _isConnected = false;
  String? _clientId;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _wantsConnection = false;

  final Set<String> _subscribedTopics = {};

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
  /// única falha no arranque (rede do usuário ainda subindo, broker público
  /// momentaneamente saturado) deixava o app isolado até ser reiniciado.
  Future<bool> connect(String clientId) async {
    _wantsConnection = true;
    _clientId = clientId;
    _retryTimer?.cancel();

    final ok = await _attemptConnect(clientId);
    if (!ok) _scheduleRetry();
    return ok;
  }

  Future<bool> _attemptConnect(String clientId) async {
    _teardownClient();

    // 1. TLS nativo na porta 8883 (mqtts).
    if (await _tryConnectTls(clientId)) return true;

    // 2. Fallback para WebSocket seguro na porta 8084 (caso a 8883 esteja bloqueada na rede do usuário).
    // Não existe fallback em texto puro: o payload já é cifrado ponta a ponta,
    // mas o TLS ainda protege os metadados (quais tópicos, quando, de qual IP).
    debugPrint('[MQTT] Tentando fallback para WebSocket seguro (wss)...');
    return await _tryConnectWs(clientId);
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
      // Cada tentativa usa um sufixo novo no clientId: o broker público derruba
      // a sessão anterior quando o mesmo identificador reaparece, o que geraria
      // um laço de desconexões entre a tentativa nova e a conexão zumbi antiga.
      final base = id.length > 4 ? id.substring(0, id.length - 4) : id;
      final freshId = '$base${DateTime.now().millisecondsSinceEpoch % 10000}';
      final ok = await _attemptConnect(freshId);
      if (!ok) _scheduleRetry();
    });
  }

  Future<bool> _tryConnectTls(String clientId) async {
    try {
      final client = MqttServerClient('broker.emqx.io', clientId);
      client.port = 8883;
      client.secure = true;
      client.keepAlivePeriod = 20;
      client.autoReconnect = true;
      client.logging(on: false);

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      client.connectionMessage = connMessage;

      _configureCallbacks(client);

      final status = await client.connect().timeout(const Duration(seconds: 6));
      if (status?.state == MqttConnectionState.connected) {
        _client = client;
        _retryAttempt = 0;
        _setupMessageListener(client);
        _setConnected(true);
        _resubscribeAll();
        debugPrint('[MQTT] Conectado via TLS 8883 com sucesso!');
        return true;
      }
      try {
        client.disconnect();
      } catch (_) {}
    } catch (e) {
      debugPrint('[MQTT] Falha na conexão TLS 8883: $e');
    }
    return false;
  }

  Future<bool> _tryConnectWs(String clientId) async {
    try {
      final client = MqttServerClient.withPort('wss://broker.emqx.io/mqtt', clientId, 8084);
      client.useWebSocket = true;
      client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      client.keepAlivePeriod = 20;
      client.autoReconnect = true;
      client.logging(on: false);

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      client.connectionMessage = connMessage;

      _configureCallbacks(client);

      final status = await client.connect().timeout(const Duration(seconds: 5));
      if (status?.state == MqttConnectionState.connected) {
        _client = client;
        _retryAttempt = 0;
        _setupMessageListener(client);
        _setConnected(true);
        _resubscribeAll();
        debugPrint('[MQTT] Conectado via WebSocket 8084 com sucesso!');
        return true;
      }
      try {
        client.disconnect();
      } catch (_) {}
    } catch (e) {
      debugPrint('[MQTT] Falha na conexão WebSocket: $e');
    }
    return false;
  }

  void _configureCallbacks(MqttServerClient client) {
    client.onConnected = () {
      debugPrint('[MQTT] Callback: Conectado.');
      _setConnected(true);
      _resubscribeAll();
    };
    client.onDisconnected = () {
      debugPrint('[MQTT] Callback: Desconectado.');
      _setConnected(false);
      // O autoReconnect do pacote cobre quedas momentâneas; se ele desistir
      // (cliente encerrado de vez), o backoff assume e tenta do zero.
      if (_wantsConnection && !client.autoReconnect) {
        _scheduleRetry();
      }
    };
    client.onAutoReconnected = () {
      debugPrint('[MQTT] Callback: Reconectado automaticamente.');
      _retryAttempt = 0;
      _retryTimer?.cancel();
      _setConnected(true);
      _resubscribeAll();
    };
  }

  void _setupMessageListener(MqttServerClient client) {
    client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        final recMess = msg.payload as MqttPublishMessage;

        // O broker é público: qualquer um pode publicar qualquer coisa nos
        // tópicos. Descarta payloads absurdos antes de alocar a string, para
        // que um terceiro não consiga inflar a memória do app.
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

  void subscribe(String topic) {
    final isNew = _subscribedTopics.add(topic);
    if (_client != null && _isConnected && isNew) {
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
  }

  void dispose() {
    disconnect();
    _messagesController.close();
    _connectionController.close();
  }
}
