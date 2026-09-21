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

  /// Um GIF de verdade, com vários quadros e durações — é o que o aplicativo
  /// recebe quando a pessoa escolhe um perfil que se mexe. O codificador aqui
  /// usa octree sem dithering porque o padrão (neural + Floyd-Steinberg) gastava
  /// mais tempo montando a massa do teste do que o código testado.
  Uint8List gifAnimado(int quadros, {int lado = 300, int duracaoCent = 10}) {
    final codificador = img.GifEncoder(
      quantizerType: img.QuantizerType.octree,
      dither: img.DitherKernel.none,
    );
    for (var i = 0; i < quadros; i++) {
      final quadro = img.Image(width: lado, height: lado);
      img.fill(quadro, color: img.ColorRgb8(20 + i * 8, 90, 200 - i * 6));
      codificador.addFrame(quadro, duration: duracaoCent);
    }
    return codificador.finish()!;
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

  test('um GIF animado continua animado, reduzido e dentro do teto', () {
    final resultado = prepararFotoDePerfil(gifAnimado(6));

    expect(resultado.erro, isNull);
    final avatar = resultado.avatar!;
    expect(avatar, startsWith('data:image/gif;base64,'));
    expect(avatar.length, lessThanOrEqualTo(tetoDeBytesDoGif));

    final deVolta = img.decodeGif(base64Decode(avatar.split(',').last))!;
    expect(deVolta.hasAnimation, isTrue);
    expect(deVolta.numFrames, greaterThan(1));
    expect(deVolta.width, ladoDoGif);
    expect(deVolta.height, ladoDoGif);
  });

  test('GIF grande demais é recusado pelo cabeçalho, sem decodificar nada', () {
    // 40 quadros de 700 px estouram o orçamento de pixels: a recusa tem de
    // vir do cabeçalho, rápida, e não de 13 segundos de decodificação.
    final resultado = prepararFotoDePerfil(gifAnimado(40, lado: 700, duracaoCent: 20));

    expect(resultado.avatar, isNull);
    expect(resultado.erro, contains('grande demais'));
  });

  test('GIF de um quadro só vira JPEG, que é menor', () {
    final resultado = prepararFotoDePerfil(gifAnimado(1));

    expect(resultado.erro, isNull);
    expect(resultado.avatar, startsWith('data:image/jpeg;base64,'));
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
