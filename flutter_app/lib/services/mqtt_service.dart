import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  MqttServerClient? _client;
  bool _isConnected = false;

  final StreamController<Map<String, dynamic>> _messagesController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messagesController.stream;

  bool get isConnected => _isConnected;

  Future<bool> connect(String clientId) async {
    try {
      _client = MqttServerClient.withPort('broker.emqx.io', clientId, 8084);
      _client!.useWebSocket = true;
      _client!.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      _client!.keepAlivePeriod = 20;
      _client!.autoReconnect = true;
      _client!.logging(on: false);

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      _client!.connectionMessage = connMessage;

      final status = await _client!.connect();
      if (status?.state == MqttConnectionState.connected) {
        _isConnected = true;
        debugPrint('[MQTT] Conectado com sucesso ao broker broker.emqx.io:8084');

        _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
          for (final msg in messages) {
            final recMess = msg.payload as MqttPublishMessage;
            final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
            try {
              final data = jsonDecode(pt) as Map<String, dynamic>;
              data['_topic'] = msg.topic;
              _messagesController.add(data);
            } catch (e) {
              // Ignore non-json packets
            }
          }
        });

        return true;
      }
    } catch (e) {
      debugPrint('[MQTT] Erro ao conectar: $e');
    }
    return false;
  }

  void subscribe(String topic) {
    if (_client != null && _isConnected) {
      _client!.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void publish(String topic, Map<String, dynamic> data) {
    if (_client != null && _isConnected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(data));
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    }
  }

  void disconnect() {
    _isConnected = false;
    _client?.disconnect();
    _client = null;
  }
}
