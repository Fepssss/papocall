import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/services/direct_crypto.dart';
import 'package:papocall/utils/app_paths.dart';

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

  test('cada conta tem a sua identidade, e a memória não passa de uma para a outra',
      () async {
    // Aqui a troca é feita só no caminho da pasta, sem o esquecerIdentidade que
    // a troca de conta de verdade chama: é o cache que tem de se tocar de quem é
    // a conta em vigor, ou a segunda conta assinaria com a chave privada da
    // primeira.
    AppPaths.conta = 'conta-a';
    final daContaA = await DirectCrypto.chavePublicaAtual();

    AppPaths.conta = 'conta-b';
    expect(await DirectCrypto.chavePublicaAtual(), isNot(daContaA));
  });

  group('a chave fixada do contato', () {
    /// O caso que a conferência fecha: um estranho que saiba só os apelidos — e
    /// a chave da caixa de entrada, que se calcula a partir do apelido — cifra o
    /// que quiser com a própria chave pública e assina como se fosse o amigo.
    Future<String> envelopeDoEstranho({
      required SimpleKeyPair estranho,
      required SimpleKeyPair vitima,
    }) async =>
        DirectCrypto.cifrar(
          minha: estranho,
          de: 'alice',
          para: 'bob',
          publicaDoParB64: await _publica(vitima),
          conteudo: {'texto': 'fala o que eu quero'},
        );

    test('recusa o envelope de quem escreve com outra chave', () async {
      final alice = await _novaIdentidade();
      final bob = await _novaIdentidade();
      final estranho = await _novaIdentidade();

      final forjado = await envelopeDoEstranho(estranho: estranho, vitima: bob);

      // Sem a conferência, isto aqui abriria — e é exatamente o ataque: o texto
      // entraria na conversa como fala da Alice e a chave do estranho seria
      // adotada como a dela.
      expect(
        await DirectCrypto.decifrar(
            minha: bob, meuUsuario: 'bob', envelope: forjado),
        isNotNull,
      );
      expect(
        await DirectCrypto.decifrar(
          minha: bob,
          meuUsuario: 'bob',
          envelope: forjado,
          publicaConhecida: await _publica(alice),
        ),
        isNull,
      );
    });

    test('deixa passar o que a própria pessoa cifrou', () async {
      final alice = await _novaIdentidade();
      final bob = await _novaIdentidade();

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
        publicaConhecida: await _publica(alice),
      );
      expect(aberto, isNotNull);
      expect(aberto!.publicaDoEnvelope, await _publica(alice));
    });

    test('o primeiro envelope, sem chave fixada ainda, é aceito', () async {
      // É o contato que escreve antes de a presença dele chegar. A chave que
      // abriu este envelope passa a ser a conferida em todos os seguintes.
      final alice = await _novaIdentidade();
      final bob = await _novaIdentidade();

      final envelope = await DirectCrypto.cifrar(
        minha: alice,
        de: 'alice',
        para: 'bob',
        publicaDoParB64: await _publica(bob),
        conteudo: {'texto': 'primeira fala'},
      );

      expect(
        await DirectCrypto.decifrar(
            minha: bob, meuUsuario: 'bob', envelope: envelope),
        isNotNull,
      );
    });

    test('envelope com chave pública truncada é descartado', () async {
      final bob = await _novaIdentidade();
      final alice = await _novaIdentidade();

      final envelope = await DirectCrypto.cifrar(
        minha: alice,
        de: 'alice',
        para: 'bob',
        publicaDoParB64: await _publica(bob),
        conteudo: {'texto': 'segredo'},
      );
      final json = jsonDecode(envelope) as Map<String, dynamic>;
      json['pub'] = base64Encode(List<int>.filled(31, 7));

      expect(
        await DirectCrypto.decifrar(
            minha: bob, meuUsuario: 'bob', envelope: jsonEncode(json)),
        isNull,
      );
    });
  });

  test('o autor declarado sai do envelope sem precisar abri-lo', () async {
    final alice = await _novaIdentidade();
    final bob = await _novaIdentidade();

    final envelope = await DirectCrypto.cifrar(
      minha: alice,
      de: 'Alice',
      para: 'bob',
      publicaDoParB64: await _publica(bob),
      conteudo: {'texto': 'oi'},
    );

    // É com este apelido cru que se procura a chave fixada antes de decifrar.
    expect(DirectCrypto.remetenteDeclarado(envelope), 'alice');
    expect(DirectCrypto.remetenteDeclarado('{"acao":"outra"}'), isNull);
    expect(DirectCrypto.remetenteDeclarado('texto solto'), isNull);
  });
}
