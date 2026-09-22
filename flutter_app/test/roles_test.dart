import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/chat_message.dart';
import 'package:papocall/models/role.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/models/user_model.dart';
import 'package:papocall/providers/app_state.dart';
import 'app_sandbox.dart';

/// Monta um servidor com o `me` como dono ou como membro e um cargo de teste.
Server buildServer({
  required String me,
  String owner = 'dono',
  List<ServerRole>? roles,
  Map<String, String> memberRoles = const {},
}) {
  return Server(
    id: 'srv-role',
    name: 'Servidor de Cargos',
    inviteCode: '',
    ownerId: owner,
    memberIds: [owner, me, 'terceiro'],
    roles: roles ?? ServerRole.defaults(),
    memberRoles: Map.of(memberRoles),
    channels: [
      Channel(id: 'c-1', name: 'geral', type: ChannelType.text),
      Channel(id: 'c-2', name: 'voz', type: ChannelType.voice),
    ],
  );
}

AppState buildApp(String userId, Server server) {
  return AppState()
    ..currentUser = UserModel(id: userId, username: 'eu')
    ..servers.add(server);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  group('Server.hasPermission', () {
    test('Dono tem toda permissão sem precisar de cargo', () {
      final srv = buildServer(me: 'dono');
      for (final p in Permissions.all) {
        expect(srv.hasPermission('dono', p.key), isTrue, reason: p.key);
      }
    });

    test('membro sem cargo não tem nenhuma', () {
      final srv = buildServer(me: 'terceiro');
      expect(srv.hasPermission('terceiro', Permissions.manageChannels), isFalse);
    });

    test('cargo concede exatamente o que lista', () {
      final srv = buildServer(
        me: 'terceiro',
        roles: [
          ServerRole(id: 'r1', name: 'Só canais', colorHex: '22C55E', permissions: {
            Permissions.manageChannels,
          }),
        ],
        memberRoles: const {'terceiro': 'r1'},
      );
      expect(srv.hasPermission('terceiro', Permissions.manageChannels), isTrue);
      expect(srv.hasPermission('terceiro', Permissions.kickMembers), isFalse);
    });

    test('cargo apontado para um ID inexistente não concede nada', () {
      final srv = buildServer(me: 'terceiro', memberRoles: const {'terceiro': 'fantasma'});
      expect(srv.hasPermission('terceiro', Permissions.manageChannels), isFalse);
    });
  });

  test('adoptRoles descarta atribuição de cargo que deixou de existir', () {
    final srv = buildServer(me: 'terceiro', memberRoles: const {'terceiro': 'role-mod'});
    srv.adoptRoles(
      newRoles: [ServerRole(id: 'outro', name: 'Outro', colorHex: '22C55E')],
      newMemberRoles: {'terceiro': 'role-mod', 'dono': 'outro'},
    );
    expect(srv.memberRoles, {'dono': 'outro'});
    expect(srv.memberRoles.containsKey('terceiro'), isFalse);
  });

  group('anti-escalada de cargos', () {
    test('sem Gerenciar cargos não se cria cargo', () async {
      final state = buildApp('terceiro', buildServer(me: 'terceiro'));
      final ok = await state.createRole(
        'srv-role',
        name: 'Poderoso',
        colorHex: '22C55E',
        permissions: {Permissions.manageChannels},
      );
      expect(ok, isFalse);
      expect(state.rolesOf('srv-role').length, 2);
    });

    test('cargo novo não pode carregar poder que o criador não tem', () async {
      // Moderador: tem canais, mas não tem 'gerenciar_cargos' nem 'expulsar'.
      final state = buildApp(
        'terceiro',
        buildServer(
          me: 'terceiro',
          roles: [
            ServerRole(id: 'r-mod', name: 'Mod', colorHex: '38BDF8', permissions: {
              Permissions.manageChannels,
            }),
            ServerRole(id: 'r-role', name: 'Gerente', colorHex: '8B5CF6', permissions: {
              Permissions.manageRoles,
            }),
          ],
          memberRoles: const {'terceiro': 'r-role'},
        ),
      );
      final ok = await state.createRole(
        'srv-role',
        name: 'Quase Dono',
        colorHex: 'EF4444',
        permissions: {Permissions.manageRoles, Permissions.manageServer},
      );
      expect(ok, isFalse);
      expect(state.rolesOf('srv-role').any((r) => r.name == 'Quase Dono'), isFalse);
    });

    test('Dono cria cargo com qualquer combinação', () async {
      final state = buildApp('dono', buildServer(me: 'dono'));
      final ok = await state.createRole(
        'srv-role',
        name: 'Veterano',
        colorHex: 'F59E0B',
        permissions: {Permissions.manageChannels, Permissions.kickMembers},
      );
      expect(ok, isTrue);
      expect(state.rolesOf('srv-role').length, 3);
    });

    test('não se edita um cargo mais poderoso que quem edita', () {
      final state = buildApp(
        'terceiro',
        buildServer(
          me: 'terceiro',
          roles: [
            ServerRole(id: 'r-role', name: 'Gerente', colorHex: '8B5CF6', permissions: {
              Permissions.manageRoles,
            }),
            ServerRole(id: 'r-mod', name: 'Mod', colorHex: '38BDF8', permissions: {
              Permissions.manageRoles,
              Permissions.manageChannels,
            }),
          ],
          memberRoles: const {'terceiro': 'r-role'},
        ),
      );
      // O próprio cargo, sim; o que tem um poder a mais, não.
      expect(state.canEditRole('srv-role', 'r-role'), isTrue);
      expect(state.canEditRole('srv-role', 'r-mod'), isFalse);
      expect(state.canEditRole('srv-role', 'fantasma'), isFalse);
    });
  });

  group('atribuição', () {
    test('Dono não entra no mapa de cargos', () async {
      final state = buildApp('dono', buildServer(me: 'dono'));
      final ok = await state.assignRole('srv-role', 'dono', 'role-mod');
      expect(ok, isFalse);
      expect(state.serverById('srv-role')!.memberRoles.containsKey('dono'), isFalse);
    });

    test('atribuir cargo vira "Nenhum" quando o ID é nulo', () async {
      final state = buildApp('dono', buildServer(me: 'dono', memberRoles: const {'terceiro': 'role-mod'}));
      expect(state.roleNameFor('srv-role', 'terceiro'), 'Moderador');
      await state.assignRole('srv-role', 'terceiro', null);
      expect(state.roleNameFor('srv-role', 'terceiro'), 'Membro');
      expect(state.roleColorFor('srv-role', 'terceiro'), isNull);
    });

    test('Dono aparece como Dono', () {
      final state = buildApp('terceiro', buildServer(me: 'terceiro'));
      expect(state.roleNameFor('srv-role', 'dono'), 'Dono');
    });
  });

  group('canais', () {
    test('membro sem permissão não cria nem apaga', () async {
      final state = buildApp('terceiro', buildServer(me: 'terceiro'));
      expect(await state.addChannel('srv-role', name: 'novo', type: ChannelType.text), isFalse);
      expect(await state.deleteChannel('srv-role', 'c-1'), isFalse);
      expect(state.serverById('srv-role')!.channels.length, 2);
    });

    test('canal criado vale para todos com o mesmo ID', () async {
      final state = buildApp('dono', buildServer(me: 'dono'));
      final ok = await state.addChannel('srv-role', name: 'Táticas', type: ChannelType.text);
      expect(ok, isTrue);
      final criado = state.serverById('srv-role')!.channels.last;
      // O nome da sala do LiveKit é o ID do canal: ele tem de nascer uma única vez.
      expect(criado.id, startsWith('srv-role-c-taticas-'));
    });

    test('último canal não é apagado', () async {
      final state = buildApp(
        'dono',
        buildServer(me: 'dono')
          ..channels.removeWhere((c) => c.id == 'c-2'),
      );
      expect(state.serverById('srv-role')!.channels.length, 1);
      expect(await state.deleteChannel('srv-role', 'c-1'), isFalse);
      expect(state.serverById('srv-role')!.channels.length, 1);
    });
  });

  group('expulsão e apagamento', () {
    test('sem a permissão não se expulsa', () async {
      final state = buildApp('terceiro', buildServer(me: 'terceiro'));
      expect(await state.kickMember('srv-role', 'dono'), isFalse);
    });

    test('Dono não é expulsa nem expulsa a si mesma', () async {
      final state = buildApp(
        'terceiro',
        buildServer(me: 'terceiro', memberRoles: const {'terceiro': 'role-admin'}),
      );
      expect(state.can('srv-role', Permissions.kickMembers), isTrue);
      expect(await state.kickMember('srv-role', 'dono'), isFalse);
      expect(await state.kickMember('srv-role', 'terceiro'), isFalse);
    });

    test('apagar mensagem alheia exige a permissão', () async {
      final state = buildApp('terceiro', buildServer(me: 'terceiro'));
      expect(state.canDeleteMessage('srv-role', _msg('m1', 'terceiro')), isTrue);
      expect(state.canDeleteMessage('srv-role', _msg('m2', 'dono')), isFalse);

      final comPoder = buildApp(
        'terceiro',
        buildServer(me: 'terceiro', memberRoles: const {'terceiro': 'role-admin'}),
      );
      expect(comPoder.canDeleteMessage('srv-role', _msg('m2', 'dono')), isTrue);
    });
  });

  group('lado receptor do server_info', () {
    Server buildEsqueleto() => Server(
          id: 'srv-esq',
          name: 'Servidor (papo-esq)',
          inviteCode: '',
          isSynced: false,
          memberIds: ['terceiro'],
          channels: [
            Channel(id: 'srv-esq-c-geral', name: 'geral', type: ChannelType.text),
          ],
        );

    Map<String, dynamic> infoDeDono({String publisher = 'dono', String ownerId = 'dono'}) => {
          'action': 'server_info',
          'publishedBy': publisher,
          'ownerId': ownerId,
          'name': 'Servidor Real',
          'description': '',
          'colorHex': '22C55E',
          'revision': 5,
          'memberIds': ['dono', 'terceiro'],
          'channels': [
            {'id': 'srv-esq-c-geral', 'name': 'geral', 'type': 'text'},
            {'id': 'srv-esq-v-voz', 'name': 'Sala de Voz', 'type': 'voice'},
          ],
          'roles': [
            ServerRole(id: 'r1', name: 'Mod', colorHex: '38BDF8', permissions: {
              Permissions.manageChannels,
            }).toJson(),
          ],
          'memberRoles': {'terceiro': 'r1'},
        };

    test('esqueleto do convite aprende quem é o Dono e adota os cargos', () {
      final esqueleto = buildEsqueleto();
      final state = buildApp('terceiro', esqueleto);

      state.processNetworkPayload(infoDeDono(), esqueleto);

      expect(esqueleto.ownerId, 'dono');
      expect(esqueleto.isSynced, isTrue);
      expect(state.roleNameFor('srv-esq', 'terceiro'), 'Mod');
      expect(state.can('srv-esq', Permissions.manageChannels), isTrue);
      expect(state.can('srv-esq', Permissions.kickMembers), isFalse);
    });

    test('tabela de cargos de quem não é o Dono não vale nada', () {
      final esqueleto = buildEsqueleto();
      final state = buildApp('terceiro', esqueleto);
      state.processNetworkPayload(infoDeDono(), esqueleto);

      // Um membro tem a chave do grupo e poderia reescrever a tabela: sem a
      // conferência do publicador ele se daria Administrador.
      final forjado = infoDeDono(publisher: 'terceiro');
      forjado['roles'] = [
        ServerRole(id: 'r1', name: 'Mod', colorHex: '38BDF8', permissions: {
          Permissions.manageChannels,
          Permissions.kickMembers,
          Permissions.manageRoles,
          Permissions.manageServer,
        }).toJson(),
      ];
      state.processNetworkPayload(forjado, esqueleto);

      expect(state.roleNameFor('srv-esq', 'terceiro'), 'Mod');
      expect(state.can('srv-esq', Permissions.kickMembers), isFalse);
    });

    test('o Dono conhecido não é trocado por outro publicado no broker', () {
      final esqueleto = buildEsqueleto();
      final state = buildApp('terceiro', esqueleto);
      state.processNetworkPayload(infoDeDono(), esqueleto);

      state.processNetworkPayload(infoDeDono(publisher: 'usurpador', ownerId: 'usurpador'), esqueleto);
      expect(esqueleto.ownerId, 'dono');
    });

    test('esqueleto aceita o túmulo que se declara do Dono', () {
      final esqueleto = buildEsqueleto();
      final state = buildApp('terceiro', esqueleto);

      state.processNetworkPayload({
        'action': 'server_destroyed',
        'serverId': 'srv-esq',
        'publishedBy': 'dono',
        'ownerId': 'dono',
      }, esqueleto);

      expect(state.servers, isEmpty);
    });

    test('quem conhece o Dono só apaga o servidor pela palavra dele', () {
      final state = buildApp('terceiro', buildServer(me: 'terceiro'));

      state.processNetworkPayload({
        'action': 'server_destroyed',
        'serverId': 'srv-role',
        'publishedBy': 'terceiro',
        'ownerId': 'terceiro',
      }, state.serverById('srv-role')!);

      expect(state.servers.length, 1);
    });
  });

  group('destruição do servidor', () {
    test('só o Dono destrói', () async {
      final state = buildApp(
        'terceiro',
        buildServer(me: 'terceiro', memberRoles: const {'terceiro': 'role-admin'}),
      );
      // Administrador tem Gerenciar servidor, mas o túmulo só sai da mão do Dono.
      expect(state.can('srv-role', Permissions.manageServer), isTrue);
      expect(await state.destroyServer('srv-role'), isFalse);
      expect(state.servers.length, 1);
    });

    test('Dono destrói e o servidor some desta máquina', () async {
      final state = buildApp('dono', buildServer(me: 'dono'));
      expect(await state.destroyServer('srv-role'), isTrue);
      expect(state.servers, isEmpty);
    });
  });

  // O sintoma reclamado: expulsa alguém e algumas pessoas continuam vendo a
  // pessoa na lista de membros. A lista vivia sendo só acrescida por quem
  // recebia o server_info, então a poda do Dono nunca chegava a ninguém.
  group('roster autoritativo do server_info', () {
    Server srvLocal({required List<String> memberIds, int revision = 3}) => Server(
          id: 'srv-roster',
          name: 'Servidor',
          inviteCode: 'papo-roster',
          ownerId: 'dono',
          memberIds: memberIds,
          roles: ServerRole.defaults(),
          revision: revision,
          channels: [Channel(id: 'c-1', name: 'geral', type: ChannelType.text)],
        );

    Map<String, dynamic> infoDe({
      required List<String> memberIds,
      String publisher = 'dono',
      int revision = 4,
    }) =>
        {
          'action': 'server_info',
          'publishedBy': publisher,
          'ownerId': 'dono',
          'name': 'Servidor',
          'colorHex': '22C55E',
          'revision': revision,
          'memberIds': memberIds,
          'channels': [
            {'id': 'c-1', 'name': 'geral', 'type': 'text'},
          ],
        };

    test('a lista do Dono poda quem ele tirou do servidor', () {
      final srv = srvLocal(memberIds: ['dono', 'eu', 'fantasma']);
      final state = buildApp('eu', srv);

      state.processNetworkPayload(
        infoDe(memberIds: ['dono', 'eu']),
        srv,
      );

      expect(srv.memberIds, containsAll(['dono', 'eu']));
      expect(srv.memberIds, isNot(contains('fantasma')));
    });

    test('a lista de quem não pode expulsar continua sendo só acréscimo', () {
      // Um membro comum (ou um atacante com a chave do convite) republica sem o
      // expulso: sem o poder de expulsar, ele não tem como tirar ninguém de
      // ninguém.
      final srv = srvLocal(memberIds: ['dono', 'eu', 'fantasma']);
      final state = buildApp('eu', srv);

      state.processNetworkPayload(
        infoDe(memberIds: ['dono', 'eu'], publisher: 'curioso'),
        srv,
      );

      expect(srv.memberIds, contains('fantasma'));
    });

    test('revisão mais velha que a minha nunca poda', () {
      // Um pacote velho regravado no broker não tem poder de tirar ninguém da
      // lista de hoje: só uma revisão que não é mais velha que a nossa chega a
      // ser tratada como a lista. O que ele ainda pode fazer é acrescentar,
      // como sempre fez — a poda de verdade volta na próxima publicação do Dono.
      final srv = srvLocal(memberIds: ['dono', 'eu', 'fantasma'], revision: 9);
      final state = buildApp('eu', srv);

      state.processNetworkPayload(
        infoDe(memberIds: ['dono', 'eu'], revision: 4),
        srv,
      );

      expect(srv.memberIds, contains('fantasma'));
    });

    test('quem é expulso offline sai do servidor ao receber a lista do Dono', () {
      final srv = srvLocal(memberIds: ['dono', 'eu', 'fantasma']);
      final state = buildApp('fantasma', srv);

      state.processNetworkPayload(
        infoDe(memberIds: ['dono', 'eu']),
        srv,
      );

      expect(state.servers, isEmpty);
    });

    test('lista que se diz do Dono mas não tem o Dono não vale nada', () {
      // O envelope é cifrado com a chave que qualquer membro do servidor tem,
      // então "publishedBy" é declarado, não provado. A lista autoritativa
      // precisa ser auto-coerente: quem se diz Dono tem de estar na própria
      // lista. Sem isso, um membro apagaria os outros da tela de todo mundo.
      final srv = srvLocal(memberIds: ['dono', 'eu', 'fantasma']);
      final state = buildApp('eu', srv);

      state.processNetworkPayload(
        infoDe(memberIds: ['eu']),
        srv,
      );

      expect(srv.memberIds, containsAll(['dono', 'eu', 'fantasma']));
      expect(state.servers, hasLength(1));
    });
  });
}

ChatMessage _msg(String id, String authorId) => ChatMessage(
      id: id,
      authorId: authorId,
      author: 'autor',
      text: 'oi',
      timestamp: 'agora',
    );
