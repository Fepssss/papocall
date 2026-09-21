import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Recorta, reduz e comprime a imagem que a pessoa escolheu para o perfil.
///
/// A foto viaja dentro de cada pacote de presença — para cada servidor e para
/// cada amigo, a cada batimento de dez segundos. Um PNG de 128 px tirado de uma
/// câmera qualquer pesa dezenas de kilobytes, e isso afogaria a malha por uma
/// bobagem. Por isso existe um teto, e ele é verificado aqui, antes de a
/// imagem chegar em qualquer outro lugar do aplicativo.
const int ladoDaFoto = 128;
const int tetoDeBytesDaFoto = 9 * 1024;

/// Um GIF animado paga o mesmo batimento multiplicado pelos quadros, então ele
/// entra menor e com menos quadros: um retrato que se mexe precisa continuar
/// sendo um retrato, não um vídeo de 2 MB repetido a cada dez segundos.
const int ladoDoGif = 96;
const int tetoDeBytesDoGif = 16 * 1024;
const int tetoDeQuadros = 12;

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
  try {
    if (_ehGif(origem)) {
      // O cabeçalho entrega o tamanho e a contagem de quadros sem decodificar
      // nada. Sem esta checagem, um GIF grande pagava a decodificação inteira
      // para no fim não caber — foram 13 segundos para 40 quadros de 700 px.
      final leitor = img.GifDecoder();
      final info = leitor.startDecode(origem);
      if (info == null) {
        return (avatar: null, erro: 'Esse GIF não pôde ser lido. Tente outro arquivo.');
      }
      if (info.width * info.height * info.numFrames > orcamentoDePixels) {
        return (
          avatar: null,
          erro: 'Esse GIF é grande demais para um perfil. Escolha um menor ou mais curto.',
        );
      }

      final animacao = leitor.decode(origem);
      if (animacao != null && animacao.hasAnimation) {
        return _prepararGifAnimado(animacao);
      }
    }
    return _prepararParada(origem);
  } catch (_) {
    return (
      avatar: null,
      erro: 'Esse arquivo não é uma imagem legível. Tente um JPG, PNG ou GIF comum.',
    );
  }
}

/// Quanto de trabalho de decodificação um perfil pode custar, medido em
/// pixels-quadrado (largura × altura × quadros).
const int orcamentoDePixels = 4 * 1000 * 1000;

/// GIF que se mexe: reduz cada quadro e vai tentando com menos quadros e menos
/// pixels até caber no teto. O que não couber é recusado com motivo, em vez de
/// ser enviado pela metade.
///
/// A amostragem e o recorte acontecem uma vez só, sobre a imagem original, e as
/// tentativas seguintes partem do resultado já pequeno.
RetratoPreparado _prepararGifAnimado(img.Image animacao) {
  final base = _amostra(animacao.frames, tetoDeQuadros)
      .map((quadro) => (
            imagem: _recorte(quadro, ladoDoGif),
            // O codificador conta em centésimos; frameDuration vem em ms.
            duracao: quadro.frameDuration > 0 ? quadro.frameDuration ~/ 10 : 10,
          ))
      .toList();

  for (final plano in const [
    (lado: ladoDoGif, quadros: tetoDeQuadros),
    (lado: 80, quadros: 8),
    (lado: 64, quadros: 6),
  ]) {
    final quadros = _amostraDe(base, plano.quadros);
    final codificador = img.GifEncoder(
      quantizerType: img.QuantizerType.octree,
      dither: img.DitherKernel.none,
    )..repeat = animacao.loopCount;

    for (final quadro in quadros) {
      codificador.addFrame(
        plano.lado == ladoDoGif
            ? quadro.imagem
            : img.copyResize(quadro.imagem, width: plano.lado, height: plano.lado),
        duration: quadro.duracao,
      );
    }

    final bytes = codificador.finish();
    if (bytes == null) continue;

    final dados = _dataUri('image/gif', bytes);
    if (dados.length <= tetoDeBytesDoGif) return (avatar: dados, erro: null);
  }

  return (
    avatar: null,
    erro: 'Esse GIF não coube no perfil. Escolha um menor, mais curto, ou uma imagem parada.',
  );
}

RetratoPreparado _prepararParada(Uint8List origem) {
  final lida = img.decodeImage(origem);
  if (lida == null || lida.width < 8 || lida.height < 8) {
    return (avatar: null, erro: 'Essa imagem não pôde ser lida. Tente um JPG ou PNG comum.');
  }

  final reduzida = _recorte(lida, ladoDaFoto);
  var comprimida = img.encodeJpg(reduzida, quality: 72);
  if (_peso('image/jpeg', comprimida) > tetoDeBytesDaFoto) {
    comprimida = img.encodeJpg(reduzida, quality: 45);
  }

  final dados = _dataUri('image/jpeg', comprimida);
  if (dados.length > tetoDeBytesDaFoto) {
    return (
      avatar: null,
      erro: 'A foto não coube no tamanho de perfil. Escolha uma imagem mais simples.',
    );
  }
  return (avatar: dados, erro: null);
}

/// Recorte central quadrado, reduzido para [lado]: foto de retrato é quadrada,
/// e esticar para caber deformaria o rosto de quem escolheu.
img.Image _recorte(img.Image imagem, int lado) {
  final menor = imagem.width < imagem.height ? imagem.width : imagem.height;
  final quadrada = img.copyCrop(
    imagem,
    x: ((imagem.width - menor) / 2).round(),
    y: ((imagem.height - menor) / 2).round(),
    width: menor,
    height: menor,
  );
  return img.copyResize(quadrada, width: lado, height: lado);
}

/// Amostra a animação de forma espaçada: cortar os últimos quadros deixaria o
/// GIF contando só o começo do movimento.
List<img.Image> _amostra(List<img.Image> quadros, int maximo) {
  if (quadros.length <= maximo) return quadros;
  final passo = quadros.length / maximo;
  return List<img.Image>.generate(maximo, (i) => quadros[(i * passo).floor()]);
}

/// A mesma amostragem, agora sobre os quadros já reduzidos.
List<({img.Image imagem, int duracao})> _amostraDe(
  List<({img.Image imagem, int duracao})> quadros,
  int maximo,
) {
  if (quadros.length <= maximo) return quadros;
  final passo = quadros.length / maximo;
  return List.generate(maximo, (i) => quadros[(i * passo).floor()]);
}

bool _ehGif(Uint8List bytes) =>
    bytes.length > 5 &&
    bytes[0] == 0x47 && // G
    bytes[1] == 0x49 && // I
    bytes[2] == 0x46 && // F
    bytes[3] == 0x38; // 8 — GIF87a / GIF89a

String _dataUri(String tipo, List<int> conteudo) =>
    'data:$tipo;base64,${base64Encode(conteudo)}';

/// O peso real do que vai trafegar: o base64 é maior que o arquivo, e é ele que
/// viaja dentro de cada pacote de presença.
int _peso(String tipo, List<int> conteudo) => _dataUri(tipo, conteudo).length;
