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

  MqttServerClient? _client;
  bool _isConnected = false;
  final Set<String> _subscribedTopics = {};

  final StreamController<MqttEnvelope> _messagesController = StreamController.broadcast();
  Stream<MqttEnvelope> get messageStream => _messagesController.stream;

  bool get isConnected => _isConnected;

  Future<bool> connect(String clientId) async {
    disconnect();

    // 1. TLS nativo na porta 8883 (mqtts).
    final tlsSuccess = await _tryConnectTls(clientId);
    if (tlsSuccess) return true;

    // 2. Fallback para WebSocket seguro na porta 8084 (caso a 8883 esteja bloqueada na rede do usuário).
    // Não existe fallback em texto puro: o payload já é cifrado ponta a ponta,
    // mas o TLS ainda protege os metadados (quais tópicos, quando, de qual IP).
    debugPrint('[MQTT] Tentando fallback para WebSocket seguro (wss)...');
    return await _tryConnectWs(clientId);
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
        _isConnected = true;
        _setupMessageListener(client);
        _resubscribeAll();
        debugPrint('[MQTT] Conectado via TLS 8883 com sucesso!');
        return true;
      }
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
        _isConnected = true;
        _setupMessageListener(client);
        _resubscribeAll();
        debugPrint('[MQTT] Conectado via WebSocket 8084 com sucesso!');
        return true;
      }
    } catch (e) {
      debugPrint('[MQTT] Falha na conexão WebSocket: $e');
    }
    return false;
  }

  void _configureCallbacks(MqttServerClient client) {
    client.onConnected = () {
      _isConnected = true;
      debugPrint('[MQTT] Callback: Conectado.');
      _resubscribeAll();
    };
    client.onDisconnected = () {
      _isConnected = false;
      debugPrint('[MQTT] Callback: Desconectado.');
    };
    client.onAutoReconnected = () {
      _isConnected = true;
      debugPrint('[MQTT] Callback: Reconectado automaticamente.');
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
    _subscribedTopics.add(topic);
    if (_client != null && _isConnected) {
      _client!.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  /// Publica um envelope já cifrado. Este serviço nunca recebe texto em claro.
  void publishEncrypted(String topic, String encryptedEnvelope) {
    if (_client != null && _isConnected) {
      try {
        final builder = MqttClientPayloadBuilder();
        builder.addString(encryptedEnvelope);
        _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      } catch (e) {
        debugPrint('[MQTT] Erro ao publicar em $topic: $e');
      }
    } else {
      debugPrint('[MQTT] Tentativa de publicar em $topic com cliente desconectado.');
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

  void disconnect() {
    _isConnected = false;
    _subscribedTopics.clear();
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
  }
}
