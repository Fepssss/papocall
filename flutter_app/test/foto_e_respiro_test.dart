import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:papocall/providers/app_state.dart';
import 'package:papocall/utils/app_paths.dart';
import 'package:papocall/utils/foto_de_perfil.dart';

import 'app_sandbox.dart';

/// A foto de perfil — do byte cru ao campo que viaja na presença — e o respiro
/// que segura rajada de mensagem.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppDataSandbox();

  Uint8List pngQuadrado(int lado) {
    final imagem = img.Image(width: lado, height: lado);
    img.fill(imagem, color: img.ColorRgb8(12, 128, 210));
    return img.encodePng(imagem);
  }

  Map<String, dynamic> configLida() =>
      jsonDecode(AppPaths.file('settings.json').readAsStringSync());

  test('uma foto qualquer vira JPEG de 128 px, dentro do teto', () {
    final resultado = prepararFotoDePerfil(pngQuadrado(900));

    expect(resultado.erro, isNull);
    final avatar = resultado.avatar!;
    expect(avatar, startsWith('data:image/jpeg;base64,'));
    expect(avatar.length, lessThanOrEqualTo(tetoDeBytesDaFoto));

    final deVolta = img.decodeImage(base64Decode(avatar.split(',').last))!;
    expect(deVolta.width, ladoDaFoto);
    expect(deVolta.height, ladoDaFoto);
  });

  test('arquivo que não é imagem é recusado com motivo, sem estourar', () {
    final resultado = prepararFotoDePerfil(Uint8List.fromList(utf8.encode('isso não é png nem jpg')));

    expect(resultado.avatar, isNull);
    expect(resultado.erro, isNotNull);
    expect(resultado.erro, isNotEmpty);
  });

  test('a foto aceita entra no modelo, no disco e na próxima presença', () async {
    final state = AppState();

    final erro = await state.definirFotoDePerfil(pngQuadrado(640));
    expect(erro, isNull);
    expect(state.currentUser.avatar, startsWith('data:image/jpeg;base64,'));
    expect(configLida()['avatar'], state.currentUser.avatar);

    await state.removerFotoDePerfil();
    expect(state.currentUser.avatar, isEmpty);
    expect(configLida()['avatar'], '');
  });

  test('a foto recusada deixa o perfil como estava', () async {
    final state = AppState();

    final erro = await state.definirFotoDePerfil(Uint8List.fromList([1, 2, 3, 4]));
    expect(erro, isNotNull);
    expect(state.currentUser.avatar, isEmpty);
  });

  test('a segunda mensagem na hora não sai, e o texto continua no campo', () {
    final state = AppState();

    expect(state.podeEnviar, isTrue);
    expect(state.sendMessage('primeira'), isTrue);
    expect(state.esperaParaEnviarMs(), greaterThan(0));
    expect(state.sendMessage('segunda em cima'), isFalse);
  });

  test('um endereço que não é http não vira mensagem vazia', () {
    final state = AppState();

    expect(state.sendMessage('', gifUrl: 'giphy.gif'), isFalse);
    expect(state.activeMessages, isEmpty);
  });
}
