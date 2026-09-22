import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/chat_message.dart';
import 'package:papocall/models/role.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/utils/app_paths.dart';

import 'app_sandbox.dart';

/// Quem sai, e quem entra depois.
///
/// O bug reclamado: criar uma conta nova no mesmo computador vinha com os
/// amigos da conta anterior na tela. A causa era uma pasta só para todas as
/// contas — e dentro dela também estava a chave privada do chat privado, o que
/// faz do vazamento uma questão de identidade, não de lista de nomes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  test('o que uma conta escolheu sobre uma pessoa não vale para a conta seguinte',
      () async {
    final state = AppState();

    await state.trocarDeConta('conta-a');
    await state.definirVolumeDoPar('alvo', 0.3);
    await state.definirParSilenciado('alvo', true);
    await state.definirVideoOculto('alvo', true);

    await state.trocarDeConta('conta-b');
    expect(state.volumeDoPar('alvo'), 1.0);
    expect(state.parSilenciado('alvo'), isFalse);
    expect(state.videoOcultoDe('alvo'), isFalse);
    // O serviço que entra na call fica sem a regra da outra conta: é ele que
    // aplica na faixa, e não a interface.
    expect(state.voiceService.volumesPorUsuario, isEmpty);
    expect(state.voiceService.silenciados, isEmpty);

    // Voltar para a conta A traz o que era dela de volta — a pasta não foi
    // tocada pela passagem da conta B.
    await state.trocarDeConta('conta-a');
    expect(state.volumeDoPar('alvo'), 0.3);
    expect(state.parSilenciado('alvo'), isTrue);
    expect(state.videoOcultoDe('alvo'), isTrue);
  });

  test('a pasta da conta não é montada a partir do que vem do servidor', () {
    // O id da conta chega do backend. Um nome de pasta montado com ele seria
    // porta para escrever fora da pasta do aplicativo.
    AppPaths.conta = '../../Segredo';
    final pasta = AppPaths.contaDados().path;
    expect(pasta.contains('Segredo'), isFalse);
    expect(pasta.contains('..'), isFalse);

    // A mesma conta cai sempre na mesma pasta: é por aí que os dados voltam.
    AppPaths.conta = 'conta-a';
    final a = AppPaths.contaDados().path;
    AppPaths.conta = 'conta-b';
    expect(AppPaths.contaDados().path, isNot(a));
    AppPaths.conta = 'conta-a';
    expect(AppPaths.contaDados().path, a);
  });

  test('o histórico sujo é gravado na conta de origem antes da troca', () async {
    // A gravação do histórico é adiada de propósito. Sem escoar antes de trocar
    // de conta, o que chegou nos últimos segundos ia cair no cofre de quem está
    // deslogado, e a conta voltaria na próxima abertura sem o que viu.
    final srv = Server(
      id: 'srv-conta',
      name: 'Squad',
      inviteCode: '',
      ownerId: 'eu',
      memberIds: ['eu'],
      roles: ServerRole.defaults(),
      channels: [Channel(id: 'c-texto', name: 'geral', type: ChannelType.text)],
    );
    final state = AppState();
    await state.trocarDeConta('conta-a');
    state.servers.add(srv);
    state.activeServerId = srv.id;
    state.selectChannel('c-texto');
    state.processNetworkPayload({
      'action': 'chat_message',
      'channelId': 'c-texto',
      'channelName': 'geral',
      'channelType': 'text',
      'serverId': srv.id,
      'message': ChatMessage(
        id: 'm1',
        authorId: 'amigo',
        author: 'Amigo',
        text: 'o que ficou sujo',
        timestamp: 'agora',
        sentAt: DateTime.now().millisecondsSinceEpoch,
      ).toJson(),
    }, srv);

    await state.trocarDeConta('conta-b');

    AppPaths.conta = 'conta-a';
    final gravadoDaA = AppPaths.contaFile('chat_history.json');
    expect(gravadoDaA.existsSync(), isTrue);
    expect(gravadoDaA.readAsStringSync(), contains('o que ficou sujo'));
    AppPaths.conta = 'conta-b';
    expect(AppPaths.contaFile('chat_history.json').existsSync(), isFalse);
  });

  test('gravações do mesmo arquivo não se atropelam nem somem no meio', () async {
    // As gravações saem de caminhos que não sabem um do outro — a marca de
    // leitura, o salvamento adiado do histórico, a fila de pedidos. Duas no mesmo
    // arquivo dividiam o temporário, uma delas morria no rename do Windows
    // ("arquivo em uso") e o estado daquela gravação se perdia.
    final state = AppState();
    await state.trocarDeConta('conta-a');
    // Os caminhos são tomados agora, e não depois de voltar atrás com a conta:
    // o estado desta troca continua vivo e qualquer gravação atrasada dele cairia
    // na pasta que a última atribuição apontar.
    final pastaDaContaA = AppPaths.contaDados();
    final arquivo = AppPaths.contaFile('read_marks.json');

    for (var i = 0; i < 20; i++) {
      state.markChannelRead('c-$i');
    }

    // A fila de gravação é assíncrona, e sob a carga de uma suíte inteira vinte
    // escritas encadeadas podem levar o que for preciso para terminar. O que se
    // cobra aqui é o estado final — a última escrita da fila é a que tem as vinte
    // marcas — e não a velocidade.
    var lido = <String, dynamic>{};
    for (var i = 0; i < 100 && lido.length < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      try {
        if (!arquivo.existsSync()) continue;
        lido = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {
        // O arquivo pode estar no meio de uma das vinte escritas: aqui é só a
        // próxima volta do laço, que espera a fila andar.
        continue;
      }
    }
    // Trocar de conta escoou o que ainda estava na fila.
    await state.trocarDeConta('conta-b');

    expect(lido.length, 20);
    // Nada de temporário sobrando daquele arquivo: o que sobra é escrito que
    // não chegou ao destino.
    expect(
      pastaDaContaA
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('read_marks.json') && f.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('quem saiu não reescreve os dados de quem saiu', () async {
    final state = AppState();
    await state.trocarDeConta('conta-a');
    await state.definirParSilenciado('alvo', true);
    final arquivoDaConta =
        AppPaths.contaFile('preferencias.json').readAsStringSync();

    await state.trocarDeConta(null);
    expect(state.parSilenciado('alvo'), isFalse);

    // Um salvamento atrasado, depois de a sessão ter acabado, escreve no cofre
    // de passagem de quem está deslogado: o arquivo da conta fica exatamente
    // como estava na saída.
    await state.definirParSilenciado('alvo', true);
    AppPaths.conta = 'conta-a';
    expect(AppPaths.contaFile('preferencias.json').readAsStringSync(),
        arquivoDaConta);
  });
}
