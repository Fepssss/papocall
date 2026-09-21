// Verificação ponta a ponta da malha de sincronização, contra o broker real.
//
// Rode com:  dart run tool/verify_sync.dart
//
// Fica fora de `flutter test` de propósito: o runner de testes do Flutter não
// abre sockets de verdade, então lá tudo dava timeout mesmo com o app correto.
// Este script usa o ServerCrypto real (o mesmo que o app usa para derivar os
// tópicos e cifrar os envelopes), de modo que o que ele valida é exatamente o
// protocolo que roda em produção.
//
// Cobre as três falhas que deixavam a experiência unilateral:
//   1. solicitação de amizade enviada com o destinatário offline se perdia;
//   2. quem entrava por convite não recebia a estrutura real do servidor e
//      acabava numa sala de voz que nenhum outro membro enxergava;
//   3. a presença de um membro sobrescrevia a do outro, escondendo quem estava
//      online no servidor;
//   4. não havia histórico: quem entrava num servidor via o canal vazio, mesmo
//      com anos de conversa acumulada nos outros membros.

import 'dart:async';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:papocall/services/server_crypto.dart';

// Broker alvo. Antes estas duas linhas diziam `broker.emqx.io`, e era verdade;
// agora o destino é o broker dedicado, informado por argumento ou ambiente, e a
// conexão leva a credencial de sessão que `POST /mqtt/credentials` devolve.
String _host = '';
int _port = 8883;
String _usuario = '';
String _senha = '';

var _falhas = 0;

void _checa(String descricao, bool condicao) {
  stdout.writeln('   ${condicao ? '[ok]  ' : '[FALHA]'} $descricao');
  if (!condicao) _falhas++;
}

Future<MqttServerClient> _conectar(String id) async {
  final client = MqttServerClient(_host, id);
  client.port = _port;
  client.secure = true;
  client.keepAlivePeriod = 20;
  client.logging(on: false);

  final mensagem = MqttConnectMessage().withClientIdentifier(id).startClean();
  if (_usuario.isNotEmpty && _senha.isNotEmpty) {
    mensagem.authenticateAs(_usuario, _senha);
  }
  client.connectionMessage = mensagem;

  final status = await client.connect().timeout(const Duration(seconds: 12));
  if (status?.state != MqttConnectionState.connected) {
    throw StateError('nao foi possivel conectar em $_host:$_port');
  }
  return client;
}

void _publicar(MqttServerClient c, String topico, String payload, {bool retain = false}) {
  final builder = MqttClientPayloadBuilder()..addString(payload);
  c.publishMessage(topico, MqttQos.atLeastOnce, builder.payload!, retain: retain);
}

void _limparRetido(MqttServerClient c, String topico) {
  c.publishMessage(topico, MqttQos.atLeastOnce, MqttClientPayloadBuilder().payload!, retain: true);
}

/// Assina [topicos] e coleta o que chegar por [janela].
Future<List<MapEntry<String, String>>> _colher(
  MqttServerClient c,
  List<String> topicos,
  Duration janela,
) async {
  final recebidas = <MapEntry<String, String>>[];
  final sub = c.updates?.listen((eventos) {
    for (final e in eventos) {
      final msg = e.payload as MqttPublishMessage;
      if (msg.payload.message.isEmpty) continue;
      recebidas.add(
        MapEntry(e.topic, MqttPublishPayload.bytesToStringAsString(msg.payload.message)),
      );
    }
  });
  for (final t in topicos) {
    c.subscribe(t, MqttQos.atLeastOnce);
  }
  await Future<void>.delayed(janela);
  await sub?.cancel();
  return recebidas;
}

Future<void> _cenarioAmizadeOffline(String sufixo) async {
  stdout.writeln('\n1. Solicitacao de amizade com o destinatario offline');

  final remetente = 'ana_$sufixo';
  final destinatario = 'bruno_$sufixo';
  final slot = ServerCrypto.userInboxSlotTopic(destinatario, remetente);

  // Ana envia. Bruno nem está conectado.
  final ana = await _conectar('pc_ana_$sufixo');
  final envelope = await ServerCrypto.encryptInboxPayload(destinatario, {
    'action': 'friend_request',
    'request': {
      'id': 'req-$sufixo',
      'senderUsername': remetente,
      'recipientUsername': destinatario,
    },
  });
  _publicar(ana, slot, envelope, retain: true);
  await Future<void>.delayed(const Duration(seconds: 2));
  ana.disconnect();

  // Só agora Bruno abre o app pela primeira vez.
  final bruno = await _conectar('pc_bruno_$sufixo');
  final recebidas = await _colher(
    bruno,
    [ServerCrypto.userInboxWildcard(destinatario)],
    const Duration(seconds: 4),
  );

  _checa('o pedido estava esperando na caixa de entrada', recebidas.isNotEmpty);

  if (recebidas.isNotEmpty) {
    final aberto = await ServerCrypto.decryptInboxPayload(destinatario, recebidas.first.value);
    _checa('o pedido foi decifrado pelo destinatario', aberto != null);
    _checa('veio de quem enviou', aberto?['request']?['senderUsername'] == remetente);
    _checa(
      'um terceiro nao consegue ler o pedido',
      await ServerCrypto.decryptInboxPayload('intruso_$sufixo', recebidas.first.value) == null,
    );
  }

  // Ao responder, o compartimento é limpo: sem isso o mesmo pedido voltaria
  // como "nova solicitacao" a cada reconexao.
  _limparRetido(bruno, slot);
  await Future<void>.delayed(const Duration(seconds: 2));
  bruno.disconnect();

  final depois = await _conectar('pc_bruno2_$sufixo');
  final sobrou = await _colher(
    depois,
    [ServerCrypto.userInboxWildcard(destinatario)],
    const Duration(seconds: 4),
  );
  _checa('o pedido respondido nao volta na proxima conexao', sobrou.isEmpty);
  depois.disconnect();
}

Future<void> _cenarioEstruturaServidor(String sufixo) async {
  stdout.writeln('\n2. Estrutura do servidor para quem entra por convite');

  final convite = 'papo-t$sufixo';
  final infoTopic = ServerCrypto.serverInfoTopic(convite);
  const canalVozReal = 'srv-x-v-squad1';

  final dono = await _conectar('pc_dono_$sufixo');
  final envelope = await ServerCrypto.encryptPayload(convite, {
    'action': 'server_info',
    'name': 'Squad Alfa',
    'colorHex': '22C55E',
    'revision': 3,
    'channels': [
      {'id': 'srv-x-c-geral', 'name': 'geral', 'type': 'text'},
      {'id': canalVozReal, 'name': '🎮 Squad Alfa', 'type': 'voice'},
    ],
  });
  _publicar(dono, infoTopic, envelope, retain: true);
  await Future<void>.delayed(const Duration(seconds: 2));

  // O dono sai de cena por completo antes de alguem entrar pelo convite.
  dono.disconnect();

  final convidado = await _conectar('pc_convidado_$sufixo');
  final recebidas = await _colher(convidado, [infoTopic], const Duration(seconds: 4));

  _checa('a estrutura chegou mesmo com o dono offline', recebidas.isNotEmpty);

  if (recebidas.isNotEmpty) {
    final aberto = await ServerCrypto.decryptPayload(convite, recebidas.first.value);
    _checa('o nome real do servidor veio junto', aberto?['name'] == 'Squad Alfa');
    // Este ID vira o nome da sala do LiveKit: os dois lados precisam chegar
    // exatamente ao mesmo valor para se ouvirem.
    final canais = (aberto?['channels'] as List?) ?? [];
    final idsVoz = canais.where((c) => c['type'] == 'voice').map((c) => c['id']).toList();
    _checa('o ID da sala de voz e o do criador', idsVoz.contains(canalVozReal));
    _checa('nao ha sala de voz inventada localmente', !idsVoz.contains('srv-x-v-geral'));
  }

  _limparRetido(convidado, infoTopic);
  await Future<void>.delayed(const Duration(seconds: 1));
  convidado.disconnect();
}

Future<void> _cenarioPresenca(String sufixo) async {
  stdout.writeln('\n3. Presenca simultanea de varios membros no servidor');

  final convite = 'papo-p$sufixo';
  final membros = ['user-a-$sufixo', 'user-b-$sufixo', 'user-c-$sufixo'];

  final publicador = await _conectar('pc_presenca_$sufixo');
  for (final uid in membros) {
    final envelope = await ServerCrypto.encryptPayload(convite, {
      'action': 'presence',
      'userId': uid,
      'username': uid,
      'status': 'online',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    _publicar(publicador, ServerCrypto.presenceSlotTopic(convite, uid), envelope, retain: true);
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  publicador.disconnect();

  // O app assina o topico compartilhado (heartbeats ao vivo, para descobrir
  // quem ainda nao conhece) e, por nome exato, o compartimento de cada membro
  // ja conhecido. Nenhum curinga em nenhum dos dois.
  final novato = await _conectar('pc_novato_$sufixo');
  final assinaturas = [
    ServerCrypto.presenceTopic(convite),
    for (final uid in membros) ServerCrypto.presenceSlotTopic(convite, uid),
  ];
  _checa(
    'nenhuma assinatura de presenca usa curinga',
    assinaturas.every((t) => !t.contains('#') && !t.contains('+')),
  );

  final recebidas = await _colher(novato, assinaturas, const Duration(seconds: 5));

  final vistos = <String>{};
  for (final r in recebidas) {
    final aberto = await ServerCrypto.decryptPayload(convite, r.value);
    final uid = aberto?['userId'] as String?;
    if (uid != null) vistos.add(uid);
  }

  // Com um unico topico de presenca compartilhado retido, so o ultimo membro
  // sobreviveria: era por isso que a lista de membros online ficava vazia ou
  // mostrava uma pessoa so.
  _checa('os tres membros apareceram de imediato (vistos: ${vistos.length})', vistos.length == 3);
  for (final uid in membros) {
    _checa('  $uid visivel', vistos.contains(uid));
  }

  for (final uid in membros) {
    _limparRetido(novato, ServerCrypto.presenceSlotTopic(convite, uid));
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  novato.disconnect();
}

Future<void> _cenarioHistorico(String sufixo) async {
  stdout.writeln('\n4. Historico de mensagens para quem entra depois');

  final convite = 'papo-h$sufixo';
  const canal = 'srv-h-c-geral';
  final ana = 'user-ana-$sufixo';
  final bruno = 'user-bruno-$sufixo';

  Map<String, dynamic> msg(String id, String autor, String texto, int t) => {
        'id': id,
        'authorId': autor,
        'author': autor,
        'text': texto,
        'timestamp': 'Hoje',
        'sentAt': t,
      };

  final base = DateTime.now().millisecondsSinceEpoch - 60000;

  // Ana conhece as tres primeiras mensagens; Bruno conhece a segunda em diante,
  // mais uma que Ana nunca viu. Nenhum dos dois tem a conversa inteira.
  final publicador = await _conectar('pc_hist_$sufixo');

  final retratoAna = await ServerCrypto.encryptPayload(convite, {
    'action': 'history_snapshot',
    'channels': {
      canal: [
        msg('m1', ana, 'primeira', base),
        msg('m2', bruno, 'segunda', base + 1000),
        msg('m3', ana, 'terceira', base + 2000),
      ],
    },
  });
  _publicar(publicador, ServerCrypto.historySlotTopic(convite, ana), retratoAna, retain: true);

  final retratoBruno = await ServerCrypto.encryptPayload(convite, {
    'action': 'history_snapshot',
    'channels': {
      canal: [
        msg('m2', bruno, 'segunda', base + 1000),
        msg('m3', ana, 'terceira', base + 2000),
        msg('m4', bruno, 'quarta', base + 3000),
      ],
    },
  });
  _publicar(publicador, ServerCrypto.historySlotTopic(convite, bruno), retratoBruno, retain: true);

  await Future<void>.delayed(const Duration(seconds: 2));
  publicador.disconnect();

  // O recem-chegado sabe o roster pela estrutura do servidor e assina o
  // compartimento de cada membro pelo nome exato.
  final novato = await _conectar('pc_histnovato_$sufixo');
  final assinaturas = [
    ServerCrypto.historySlotTopic(convite, ana),
    ServerCrypto.historySlotTopic(convite, bruno),
  ];
  _checa(
    'nenhuma assinatura de historico usa curinga',
    assinaturas.every((t) => !t.contains('#') && !t.contains('+')),
  );

  final recebidas = await _colher(novato, assinaturas, const Duration(seconds: 5));

  // Intercala como o app faz: uniao por id, ordenada pela data de envio.
  final porId = <String, Map<String, dynamic>>{};
  for (final r in recebidas) {
    final aberto = await ServerCrypto.decryptPayload(convite, r.value);
    final canais = aberto?['channels'] as Map<String, dynamic>?;
    final lista = canais?[canal] as List<dynamic>?;
    if (lista == null) continue;
    for (final m in lista) {
      porId[m['id'] as String] = m as Map<String, dynamic>;
    }
  }
  final ordenadas = porId.values.toList()
    ..sort((a, b) => (a['sentAt'] as int).compareTo(b['sentAt'] as int));

  _checa('os dois retratos chegaram (${recebidas.length} de 2)', recebidas.length == 2);
  // Um compartimento unico e compartilhado guardaria so o ultimo retrato: o
  // recem-chegado perderia 'primeira', que so a Ana conhecia.
  _checa('a conversa completa foi reconstruida (${ordenadas.length} de 4)', ordenadas.length == 4);
  _checa(
    'sem mensagem repetida e na ordem certa',
    ordenadas.map((m) => m['text']).join(',') == 'primeira,segunda,terceira,quarta',
  );

  for (final t in assinaturas) {
    _limparRetido(novato, t);
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  novato.disconnect();
}

Future<void> main(List<String> argv) async {
  for (var i = 0; i < argv.length - 1; i++) {
    switch (argv[i]) {
      case '--host':
        _host = argv[++i];
      case '--port':
        _port = int.tryParse(argv[++i]) ?? _port;
      case '--user':
        _usuario = argv[++i];
      case '--pass':
        _senha = argv[++i];
    }
  }
  _host = _host.isNotEmpty ? _host : (Platform.environment['PAPOCALL_MQTT_HOST'] ?? '');
  _usuario = _usuario.isNotEmpty ? _usuario : (Platform.environment['PAPOCALL_MQTT_USER'] ?? '');
  _senha = _senha.isNotEmpty ? _senha : (Platform.environment['PAPOCALL_MQTT_PASS'] ?? '');

  if (_host.isEmpty) {
    stderr.writeln('falta o broker: --host <broker> (ou PAPOCALL_MQTT_HOST), '
        'e --user/--pass com a credencial saída de POST /mqtt/credentials.');
    exit(2);
  }

  final sufixo = DateTime.now().millisecondsSinceEpoch.toString().substring(6);
  stdout.writeln('Verificando a malha de sincronizacao do PapoCall em $_host:$_port');
  if (_usuario.isEmpty) {
    stdout.writeln('sem credencial: o broker dedicado recusa tudo, e é isto que vai aparecer aqui.');
  }

  try {
    await _cenarioAmizadeOffline(sufixo);
    await _cenarioEstruturaServidor(sufixo);
    await _cenarioPresenca(sufixo);
    await _cenarioHistorico(sufixo);
  } catch (e) {
    stdout.writeln('\nERRO durante a verificacao: $e');
    _falhas++;
  }

  stdout.writeln(
    _falhas == 0 ? '\nTudo certo: a malha entrega o que deve entregar.' : '\n$_falhas verificacao(oes) falharam.',
  );
  exit(_falhas == 0 ? 0 : 1);
}
