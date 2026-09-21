import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Recorta, reduz e comprime a foto que a pessoa escolheu para o perfil.
///
/// A foto viaja dentro de cada pacote de presença — para cada servidor e para
/// cada amigo, a cada batimento de dez segundos. Um PNG de 128 px tirado de uma
/// câmera qualquer pesa dezenas de kilobytes, e isso afogaria a malha por uma
/// bobagem. Por isso existe um teto, e ele é verificado aqui, antes de a
/// imagem chegar em qualquer outro lugar do aplicativo.
const int ladoDaFoto = 128;
const int tetoDeBytesDaFoto = 9 * 1024;

/// Resultado: [avatar] pronto para ir no modelo, ou [erro] dito em português.
typedef RetratoPreparado = ({String? avatar, String? erro});

RetratoPreparado prepararFotoDePerfil(Uint8List origem) {
  if (origem.isEmpty) {
    return (avatar: null, erro: 'Não veio arquivo nenhum dessa imagem.');
  }

  // Os decodificadores do pacote `image` abrem o arquivo por dentro e, num
  // arquivo truncado, leem um byte que não existe e lançam RangeError no meio
  // do isolate. O arquivo escolhido pela pessoa é entrada de fora: ele é
  // tentado, não confiado — por isso o try abraça a decodificação inteira.
  final String dados;
  try {
    final lida = img.decodeImage(origem);
    if (lida == null || lida.width < 8 || lida.height < 8) {
      return (avatar: null, erro: 'Essa imagem não pôde ser lida. Tente um JPG ou PNG comum.');
    }

    // Recorte central quadrado: foto de retrato é quadrada, e esticar para
    // caber deformaria o rosto de quem escolheu.
    final menor = lida.width < lida.height ? lida.width : lida.height;
    final quadrada = img.copyCrop(
      lida,
      x: ((lida.width - menor) / 2).round(),
      y: ((lida.height - menor) / 2).round(),
      width: menor,
      height: menor,
    );
    final reduzida = img.copyResize(quadrada, width: ladoDaFoto, height: ladoDaFoto);

    var comprimida = img.encodeJpg(reduzida, quality: 72);
    if (_pesoDaFoto(comprimida) > tetoDeBytesDaFoto) {
      comprimida = img.encodeJpg(reduzida, quality: 45);
    }
    dados = 'data:image/jpeg;base64,${base64Encode(comprimida)}';
  } catch (_) {
    return (avatar: null, erro: 'Esse arquivo não é uma imagem legível. Tente um JPG ou PNG comum.');
  }

  if (dados.length > tetoDeBytesDaFoto) {
    return (
      avatar: null,
      erro: 'A foto não coube no tamanho de perfil. Escolha uma imagem mais simples.',
    );
  }
  return (avatar: dados, erro: null);
}

/// O peso real do que vai trafegar: o base64 é maior que o JPEG, e é ele que
/// viaja dentro de cada pacote de presença.
int _pesoDaFoto(List<int> jpeg) => 'data:image/jpeg;base64,${base64Encode(jpeg)}'.length;
