import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/models/channel.dart';
import 'package:papocall/models/server.dart';
import 'package:papocall/models/user_model.dart';
import 'package:papocall/providers/app_state.dart';

import 'app_sandbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  const idFantasma = 'eb79a05f-4c2a-4f4f-9a1c-0d3e5a7b9c01';
  const idLegado = 'user-1789865208666';

  AppState monta(String donoId) {
    final srv = Server(
      id: 'srv-membros',
      name: 'Servidor Membros',
      inviteCode: '',
      ownerId: donoId,
      memberIds: [
        donoId,
        idFantasma,
        idLegado,
      ],
      channels: [Channel(id: 'c-1', name: 'geral', type: ChannelType.text)],
    );
    return AppState()
      ..currentUser = UserModel(id: donoId, username: 'dono')
      ..servers.add(srv)
      ..activeServerId = srv.id;
  }

  test('membro sem conta conhecida vira "Conta removida" e não vaza o id', () {
    final agrupado = monta('dono').getServerMembersGrouped('srv-membros');
    final offline = agrupado['offline']!;

    expect(offline.map((u) => u.displayNameOrUsername), contains('Conta removida'));
    expect(offline.any((u) => u.displayNameOrUsername.contains(idFantasma)), isFalse);
    expect(offline.any((u) => u.handle.contains(idLegado.replaceFirst('user-', ''))), isFalse);
    expect(offline.any((u) => u.initials == 'EB'), isFalse);
  });

  test('a linha removível mantém o id real para o "expulsar" funcionar', () {
    final offline = monta('dono').getServerMembersGrouped('srv-membros')['offline']!;
    expect(offline.map((u) => u.id), containsAll(<String>[idFantasma, idLegado]));
  });

  test('o dono e os demais continuam listados, um rótulo por linha órfã', () {
    final agrupado = monta('dono').getServerMembersGrouped('srv-membros');
    final todos = <String>[
      ...agrupado['online']!.map((u) => u.displayNameOrUsername),
      ...agrupado['offline']!.map((u) => u.displayNameOrUsername),
    ];

    expect(todos, contains('dono'));
    expect(todos.where((n) => n == 'Conta removida'), hasLength(2));
    expect(todos, hasLength(3));
  });
}
