import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/services/direct_crypto.dart';

import 'app_sandbox.dart';

Future<SimpleKeyPair> _novaIdentidade() => X25519().newKeyPair();

Future<String> _publica(SimpleKeyPair par) async {
  final dados = await par.extract();
  return base64Encode(dados.publicKey.bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  test('as duas pontas abrem a própria conversa e ninguém mais', () async {
    final alice = await _novaIdentidade();
    final bob = await _novaIdentidade();
    final carol = await _novaIdentidade();

    final envelope = await DirectCrypto.cifrar(
      minha: alice,
      de: 'alice',
      para: 'bob',
      publicaDoParB64: await _publica(bob),
      conteudo: {'texto': 'oi, é privado'},
    );

    final aberto = await DirectCrypto.decifrar(
      minha: bob,
      meuUsuario: 'bob',
      envelope: envelope,
    );
    expect(aberto, isNotNull);
    expect(aberto!.de, 'alice');
    expect(aberto.conteudo['texto'], 'oi, é privado');

    // Carol tem a caixa de entrada dela, não a desta conversa: a chave é do par.
    final tentativa = await DirectCrypto.decifrar(
      minha: carol,
      meuUsuario: 'bob',
      envelope: envelope,
    );
    expect(tentativa, isNull);
  });

  test('envelope endereçado a outra pessoa é descartado', () async {
    final alice = await _novaIdentidade();
    final bob = await _novaIdentidade();

    final envelope = await DirectCrypto.cifrar(
      minha: alice,
      de: 'alice',
      para: 'bob',
      publicaDoParB64: await _publica(bob),
      conteudo: {'texto': 'segredo'},
    );

    expect(
      await DirectCrypto.decifrar(minha: bob, meuUsuario: 'carol', envelope: envelope),
      isNull,
    );
  });

  test('texto adulterado não passa na verificação', () async {
    final alice = await _novaIdentidade();
    final bob = await _novaIdentidade();

    final envelope = await DirectCrypto.cifrar(
      minha: alice,
      de: 'alice',
      para: 'bob',
      publicaDoParB64: await _publica(bob),
      conteudo: {'texto': 'segredo'},
    );

    final json = jsonDecode(envelope) as Map<String, dynamic>;
    final bytes = base64Decode(json['c'] as String);
    bytes[0] = bytes[0] ^ 0xFF;
    json['c'] = base64Encode(bytes);

    expect(
      await DirectCrypto.decifrar(
        minha: bob,
        meuUsuario: 'bob',
        envelope: jsonEncode(json),
      ),
      isNull,
    );
  });

  test('a identidade da instalação é a mesma ao reler o disco', () async {
    final primeira = await DirectCrypto.chavePublicaAtual();
    final segunda = await DirectCrypto.chavePublicaAtual();

    expect(primeira, isNotEmpty);
    expect(segunda, primeira);

    // A impressão é o que as duas pessoas conferem por outro canal.
    expect(DirectCrypto.impressao(primeira).length, 19);
  });
}
