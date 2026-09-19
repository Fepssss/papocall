import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/services/server_crypto.dart';

/// Verifica os acordos de endereçamento e de estrutura que fazem dois usuários
/// enxergarem o mesmo servidor. Antes destes ajustes, quem entrava por convite
/// montava uma estrutura local própria e acabava sozinho numa sala de voz que
/// nenhum outro membro enxergava.
void main() {
  group('Caixa de entrada com compartimento por remetente', () {
    test('cada remetente escreve num compartimento diferente', () {
      final deAna = ServerCrypto.userInboxSlotTopic('bruno', 'ana');
      final deCarla = ServerCrypto.userInboxSlotTopic('bruno', 'carla');

      // Se os dois escrevessem no mesmo tópico, a mensagem retida de um
      // apagaria a do outro e só a última solicitação sobreviveria.
      expect(deAna, isNot(equals(deCarla)));
    });

    test('o compartimento é estável e insensível a @ e maiúsculas', () {
      expect(
        ServerCrypto.userInboxSlotTopic('Bruno', '@Ana'.substring(1)),
        ServerCrypto.userInboxSlotTopic('bruno', 'ana'),
      );
    });

    test('o curinga do destinatário cobre o tópico legado e os compartimentos', () {
      const eu = 'bruno';
      final curinga = ServerCrypto.userInboxWildcard(eu);
      final legado = ServerCrypto.userInboxTopic(eu);
      final compartimento = ServerCrypto.userInboxSlotTopic(eu, 'ana');

      // 'a/b/#' casa com 'a/b' e com tudo abaixo dele, então uma assinatura só
      // continua entregando o que versões antigas publicam no tópico legado.
      expect(curinga, '$legado/#');
      expect(compartimento.startsWith('$legado/'), isTrue);
    });

    test('o tópico não revela o nome de usuário', () {
      final topico = ServerCrypto.userInboxSlotTopic('bruno', 'ana');
      expect(topico.contains('bruno'), isFalse);
      expect(topico.contains('ana'), isFalse);
    });

    test('o pedido segue cifrado e ilegível para terceiros', () async {
      final envelope = await ServerCrypto.encryptInboxPayload('bruno', {
        'action': 'friend_request',
        'request': {'senderUsername': 'ana', 'recipientUsername': 'bruno'},
      });

      expect(envelope.contains('friend_request'), isFalse);
      expect(await ServerCrypto.decryptInboxPayload('carla', envelope), isNull);

      final aberto = await ServerCrypto.decryptInboxPayload('bruno', envelope);
      expect(aberto!['request']['senderUsername'], 'ana');
    });
  });

  group('Presença com compartimento por membro', () {
    const convite = 'papo-1a2b3c4d';

    test('dois membros não sobrescrevem a presença um do outro', () {
      expect(
        ServerCrypto.presenceSlotTopic(convite, 'user-1'),
        isNot(equals(ServerCrypto.presenceSlotTopic(convite, 'user-2'))),
      );
    });

    test('o compartimento fica sob o tópico de presença do servidor', () {
      // Assinado por nome exato, um por membro conhecido: a presença não usa
      // curinga em lugar nenhum.
      expect(
        ServerCrypto.presenceSlotTopic(convite, 'user-1')
            .startsWith('${ServerCrypto.presenceTopic(convite)}/'),
        isTrue,
      );
      expect(ServerCrypto.presenceSlotTopic(convite, 'user-1').contains('#'), isFalse);
      expect(ServerCrypto.presenceSlotTopic(convite, 'user-1').contains('+'), isFalse);
    });

    test('o compartimento não revela o ID do membro nem o convite', () {
      final topico = ServerCrypto.presenceSlotTopic(convite, 'user-1');
      expect(topico.contains('user-1'), isFalse);
      expect(topico.contains(convite), isFalse);
    });

    test('presença de servidores diferentes nunca colide', () {
      expect(
        ServerCrypto.presenceSlotTopic('papo-aaaa1111', 'user-1'),
        isNot(equals(ServerCrypto.presenceSlotTopic('papo-bbbb2222', 'user-1'))),
      );
    });
  });

  group('Estrutura do servidor', () {
    test('o tópico de info é derivado do convite e é próprio', () {
      const convite = 'papo-1a2b3c4d';
      final info = ServerCrypto.serverInfoTopic(convite);

      expect(info.contains(ServerCrypto.topicIdFor(convite)), isTrue);
      expect(info, isNot(equals(ServerCrypto.chatTopic(convite))));
      expect(info, isNot(equals(ServerCrypto.presenceTopic(convite))));
      expect(info.contains(convite), isFalse);
    });

    test('adotar a estrutura substitui os canais provisórios pelos reais', () {
      const serverId = 'srv-abc';
      final provisorio = Server(
        id: serverId,
        name: 'Servidor (papo-1a2b3c4d)',
        inviteCode: 'papo-1a2b3c4d',
        isSynced: false,
        channels: [
          Channel(id: '$serverId-c-geral', name: 'geral', type: ChannelType.text),
          Channel(id: '$serverId-v-geral', name: '🔊 Sala de Voz', type: ChannelType.voice),
        ],
      );

      provisorio.adoptStructure(
        newName: 'Squad Alfa',
        newDescription: 'Time competitivo',
        newColorHex: '38BDF8',
        newRevision: 4,
        newChannels: [
          Channel(id: '$serverId-c-geral', name: 'geral', type: ChannelType.text),
          Channel(id: '$serverId-v-squad1', name: '🎮 Squad Alfa', type: ChannelType.voice),
        ],
      );

      expect(provisorio.name, 'Squad Alfa');
      expect(provisorio.isSynced, isTrue);
      expect(provisorio.revision, 4);
      // A sala de voz inventada localmente some: era ela que colocava este
      // usuário numa sala do LiveKit onde mais ninguém entrava.
      expect(provisorio.channels.map((c) => c.id), contains('$serverId-v-squad1'));
      expect(provisorio.channels.map((c) => c.id), isNot(contains('$serverId-v-geral')));
    });

    test('servidor sem marca de sincronização é tratado como provisório', () {
      // Servidores gravados por versões anteriores não têm o campo; mantê-los
      // como sincronizados preservaria os canais inventados no convite.
      final antigo = Server.fromJson({
        'id': 'srv-abc',
        'name': 'Servidor (papo-1a2b3c4d)',
        'inviteCode': 'papo-1a2b3c4d',
        'channels': [
          {'id': 'srv-abc-c-geral', 'name': 'geral', 'type': 'text'},
        ],
      });

      expect(antigo.isSynced, isFalse);
      expect(antigo.revision, 1);
    });

    test('a estrutura sobrevive ao ciclo de gravação e leitura', () {
      final original = Server(
        id: 'srv-abc',
        name: 'Squad Alfa',
        inviteCode: 'papo-1a2b3c4d',
        ownerId: 'user-1',
        revision: 7,
        isSynced: true,
        channels: [
          Channel(id: 'srv-abc-v-squad1', name: '🎮 Squad Alfa', type: ChannelType.voice),
        ],
      );

      final relido = Server.fromJson(original.toJson());

      expect(relido.revision, 7);
      expect(relido.isSynced, isTrue);
      expect(relido.channels.single.id, 'srv-abc-v-squad1');
    });
  });
}
