import 'package:flutter_test/flutter_test.dart';
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
