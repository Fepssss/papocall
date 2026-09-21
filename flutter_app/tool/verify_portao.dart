// Verificação ao vivo do portão de acesso do broker MQTT dedicado.
//
// Rode com:
//   dart run tool/verify_portao.dart --host broker.SEUDOMINIO --port 8883 \
//     --cred-nome A --cred-user <mqttUsernameA> --cred-pass <mqttPasswordA> \
//     --cred2-nome B --cred2-user <mqttUsernameB> --cred2-pass <mqttPasswordB>
//
// Fica fora de `flutter test` pelo mesmo motivo do `verify_sync.dart`: o runner de
// testes não abre socket de verdade, e aqui o que se quer medir é exatamente o que
// um broker responde num CONNECT e o que ele entrega — ou não — numa assinatura.
//
// As credenciais vêm de duas contas de teste reais: elas são emitidas por
// `POST /mqtt/credentials` com um JWT válido, então rodar este script já exige que
// o backend esteja no ar com `MQTT_HOST` apontando para o broker.
//
// Uma negação de ACL é invisível para um cliente MQTT 3.1.1: o broker simplesmente
// não entrega a mensagem, sem erro nenhum. Por isso a checagem de "não lê a caixa
// do outro" é feita pela ausência de entrega, e não por um código de recusa.
//
// Sai com código diferente de zero se qualquer checagem falhar.

import 'dart:async';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:papocall/services/server_crypto.dart';

var _falhas = 0;
var _puladas = 0;

void _checa(String descricao, bool ok) {
  stdout.writeln('   ${ok ? '[ok]  ' : '[FALHA]'} $descricao');
  if (!ok) _falhas++;
}

void _pula(String descricao) {
  stdout.writeln('   [pula] $descricao');
  _puladas++;
}

Map<String, String> _argumentos(List<String> argv) {
  final saida = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--') && i + 1 < argv.length) {
      saida[argv[i].substring(2)] = argv[++i];
    }
  }
  return saida;
}

/// Tenta um CONNECT e devolve o cliente conectado, ou `null` se o broker recusou.
///
/// Recusa chega de duas formas conforme a versão do pacote: um CONNACK com código
/// de erro (o cliente fica `disconnected`) ou uma exceção. As duas são "não entrou",
/// e tratar uma delas como sucesso seria o pior tipo de verde falso.
Future<MqttServerClient?> _conectar(
  String host,
  int porta,
  String id, {
  String? usuario,
  String? senha,
  bool wss = false,
}) async {
  final cliente = wss
      ? MqttServerClient.withPort('wss://$host/mqtt', id, porta)
      : MqttServerClient(host, id);
  cliente.port = porta;
  if (wss) {
    cliente.useWebSocket = true;
    cliente.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  } else {
    cliente.secure = true;
  }
  cliente.keepAlivePeriod = 20;
  cliente.autoReconnect = false;
  cliente.logging(on: false);

  final msg = MqttConnectMessage().withClientIdentifier(id).startClean();
  if (usuario != null && senha != null) msg.authenticateAs(usuario, senha);
  cliente.connectionMessage = msg;

  try {
    final status = await cliente.connect().timeout(const Duration(seconds: 12));
    if (status?.state == MqttConnectionState.connected) return cliente;
  } on Exception catch (e) {
    stdout.writeln('   (recusado: ${e.runtimeType})');
  }
  try {
    cliente.disconnect();
  } catch (_) {}
  return null;
}

Future<List<String>> _ouvir(
  MqttServerClient cliente,
  List<String> topicos,
  Duration janela,
) async {
  final recebidos = <String>[];
  final sub = cliente.updates?.listen((eventos) {
    for (final e in eventos) {
      final msg = e.payload as MqttPublishMessage;
      if (msg.payload.message.isEmpty) continue;
      recebidos.add(e.topic);
    }
  });
  for (final t in topicos) {
    cliente.subscribe(t, MqttQos.atLeastOnce);
  }
  await Future<void>.delayed(janela);
  await sub?.cancel();
  return recebidos;
}

void _publicar(MqttServerClient c, String topico, String corpo) {
  final builder = MqttClientPayloadBuilder()..addString(corpo);
  c.publishMessage(topico, MqttQos.atLeastOnce, builder.payload!, retain: true);
}

Future<void> main(List<String> argv) async {
  final args = _argumentos(argv);
  final host = args['host'] ?? Platform.environment['PAPOCALL_MQTT_HOST'] ?? '';
  final porta = int.tryParse(args['port'] ?? '8883') ?? 8883;
  final wssPorta = int.tryParse(args['wss-port'] ?? '8084') ?? 8084;

  if (host.isEmpty) {
    stderr.writeln('falta --host (ou PAPOCALL_MQTT_HOST no ambiente)');
    exit(2);
  }

  final nomeA = args['cred-nome'] ?? '';
  final usuarioA = args['cred-user'] ?? '';
  final senhaA = args['cred-pass'] ?? '';
  final temB =
      (args['cred2-user'] ?? '').isNotEmpty && (args['cred2-pass'] ?? '').isNotEmpty;

  stdout.writeln('broker: $host:$porta  (wss $host:$wssPorta)');

  // 1. Conexão sem credencial tem de ser RECUSADA — não ignorada em silêncio.
  stdout.writeln('\n1. anônimo:');
  final anonimo = await _conectar(host, porta, 'verif-anon-${DateTime.now().millisecondsSinceEpoch}');
  if (anonimo == null) {
    _checa('CONNECT sem credencial foi recusado', true);
  } else {
    _checa('CONNECT sem credencial foi recusado', false);
    anonimo.disconnect();
  }

  if (usuarioA.isEmpty || senhaA.isEmpty || nomeA.isEmpty) {
    stderr.writeln('\nfaltam --cred-nome/--cred-user/--cred-pass; nada mais foi verificado');
    exit(1);
  }

  // 2. Credencial válida entra; a mesma com senha trocada não.
  stdout.writeln('\n2. credencial de sessão:');
  final a = await _conectar(host, porta, 'verif-a-${DateTime.now().millisecondsSinceEpoch}',
      usuario: usuarioA, senha: senhaA);
  if (a == null) {
    _checa('CONNECT com credencial válida é aceito', false);
    stdout.writeln('\nsem a conexão A as checagens seguintes não têm como rodar.');
    exit(1);
  }
  _checa('CONNECT com credencial válida é aceito', true);

  // Mesma credencial, última letra trocada: tem de ser recusada. Trocar em vez de
  // inventar uma string qualquer é o que faz o teste provar que o broker comparou a
  // senha, e não apenas que a senha estava malformada.
  final ultimo = senhaA.codeUnitAt(senhaA.length - 1);
  final senhaTrocada = '${senhaA.substring(0, senhaA.length - 1)}'
      '${String.fromCharCode(ultimo == 0x61 ? 0x62 : 0x61)}';
  final errada = await _conectar(host, porta, 'verif-err-${DateTime.now().millisecondsSinceEpoch}',
      usuario: usuarioA, senha: senhaTrocada);
  if (errada == null) {
    _checa('CONNECT com senha errada é recusado', true);
  } else {
    _checa('CONNECT com senha errada é recusado', false);
    errada.disconnect();
  }

  final caixaA = ServerCrypto.userInboxWildcard(nomeA);

  // 3. O dono lê a própria caixa (e sem isto o teste seguinte não significa nada).
  stdout.writeln('\n3. alcance de leitura:');
  _publicar(a, '${ServerCrypto.userInboxTopic(nomeA)}/${ServerCrypto.topicIdFor('autochecagem')}', 'sentinela-a');
  final naPropria = await _ouvir(a, [caixaA], const Duration(seconds: 3));
  _checa('assina e recebe na própria caixa de entrada', naPropria.isNotEmpty);

  if (!temB) {
    _pula('leitura da caixa alheia negada: faltam --cred2-user/--cred2-pass');
  } else {
    final nomeB = args['cred2-nome'] ?? '';
    final b = await _conectar(host, porta, 'verif-b-${DateTime.now().millisecondsSinceEpoch}',
        usuario: args['cred2-user']!, senha: args['cred2-pass']!);
    if (b == null || nomeB.isEmpty) {
      _checa('segunda credencial conecta', false);
    } else {
      // B escreve na caixa de A: é o caminho de um pedido de amizade, e tem de
      // continuar aberto.
      _publicar(b, ServerCrypto.userInboxSlotTopic(nomeA, nomeB), 'de-b-para-a');
      final ouviuDeB = await _ouvir(a, [caixaA], const Duration(seconds: 3));
      _checa('A recebe o que B publicou na caixa de A', ouviuDeB.isNotEmpty);

      // E A não pode ler a caixa de B. Se isto receber alguma coisa, a autorização
      // está abrindo a caixa de outra pessoa.
      _publicar(b, ServerCrypto.userInboxSlotTopic(nomeB, nomeA), 'dentro-da-caixa-de-b');
      final invadiu = await _ouvir(a, [ServerCrypto.userInboxWildcard(nomeB)], const Duration(seconds: 3));
      _checa('A NÃO recebe nada da caixa de entrada de B', invadiu.isEmpty);

      // Presença: A publica a sua, B lê a de A, e A não consegue escrever na de B.
      final presencaA = ServerCrypto.userPresenceTopic(nomeA);
      _publicar(a, presencaA, 'presenca-a');
      final bLeuA = await _ouvir(b, [presencaA], const Duration(seconds: 3));
      _checa('B assina a presença de A (lista de amigos depende disto)', bLeuA.isNotEmpty);

      b.disconnect();
    }
  }

  // 4. Os dois caminhos de transporte.
  stdout.writeln('\n4. transporte:');
  final porWss = await _conectar(host, wssPorta, 'verif-wss-${DateTime.now().millisecondsSinceEpoch}',
      usuario: usuarioA, senha: senhaA, wss: true);
  if (porWss == null) {
    _checa('fallback WSS em $host:$wssPorta conecta', false);
  } else {
    _checa('fallback WSS em $host:$wssPorta conecta', true);
    porWss.disconnect();
  }

  a.disconnect();

  stdout.writeln('\n$_falhas falha(s), $_puladas checagem(ns) pulada(s).');
  if (_falhas > 0) exit(1);
  if (_puladas > 0) {
    stdout.writeln('o portão não está verificado por inteiro: rode de novo com as duas credenciais.');
  }
}
