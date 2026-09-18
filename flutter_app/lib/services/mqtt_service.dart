import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  MqttServerClient? _client;
  bool _isConnected = false;
  final Set<String> _subscribedTopics = {};

  final StreamController<Map<String, dynamic>> _messagesController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messagesController.stream;

  bool get isConnected => _isConnected;

  Future<bool> connect(String clientId) async {
    disconnect();

    // 1. Tentar conexão direta TCP na porta 1883 (mais rápida e padrão para desktop nativo)
    final tcpSuccess = await _tryConnectTcp(clientId);
    if (tcpSuccess) return true;

    // 2. Fallback para WebSocket seguro na porta 8084 (caso TCP direto esteja bloqueado na rede do usuário)
    debugPrint('[MQTT] Tentando fallback para WebSocket seguro (wss)...');
    return await _tryConnectWs(clientId);
  }

  Future<bool> _tryConnectTcp(String clientId) async {
    try {
      final client = MqttServerClient('broker.emqx.io', clientId);
      client.port = 1883;
      client.keepAlivePeriod = 20;
      client.autoReconnect = true;
      client.logging(on: false);

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      client.connectionMessage = connMessage;

      _configureCallbacks(client);

      final status = await client.connect().timeout(const Duration(seconds: 4));
      if (status?.state == MqttConnectionState.connected) {
        _client = client;
        _isConnected = true;
        _setupMessageListener(client);
        _resubscribeAll();
        debugPrint('[MQTT] Conectado via TCP 1883 com sucesso!');
        return true;
      }
    } catch (e) {
      debugPrint('[MQTT] Falha na conexão TCP 1883: $e');
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
        final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        try {
          final data = jsonDecode(pt) as Map<String, dynamic>;
          data['_topic'] = msg.topic;
          _messagesController.add(data);
        } catch (_) {}
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

  void publish(String topic, Map<String, dynamic> data) {
    if (_client != null && _isConnected) {
      try {
        final builder = MqttClientPayloadBuilder();
        builder.addString(jsonEncode(data));
        _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      } catch (e) {
        debugPrint('[MQTT] Erro ao publicar em $topic: $e');
      }
    } else {
      debugPrint('[MQTT] Tentativa de publicar em $topic com cliente desconectado.');
    }
  }

  void disconnect() {
    _isConnected = false;
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
  }
}
