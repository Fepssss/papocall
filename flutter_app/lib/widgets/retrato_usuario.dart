import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../theme/hud_theme.dart';

/// O retrato de uma pessoa: a foto que ela escolheu, ou as iniciais do nome.
///
/// Recebe os dois campos crus porque a mesma foto precisa aparecer tanto a
/// partir de um [UserModel] da lista de membros quanto a partir de uma
/// mensagem recebida, que carrega o retrato de quem falou no momento em que
/// falou — e não uma consulta ao cadastro de hoje.
///
/// O endereço da foto viaja dentro de cada pacote de presença, então ele guarda
/// ou um link http(s) ou um `data:image/...;base64,` pequeno. Os dois passam
/// por aqui, e o que falhar vira iniciais em vez de um quadrado vermelho no
/// meio da lista.
class RetratoUsuario extends StatelessWidget {
  const RetratoUsuario({
    super.key,
    required this.avatar,
    required this.iniciais,
    this.raio = 16,
    this.corQuandoSemFoto = HudTheme.bgHover,
    this.corDasIniciais = Colors.white,
  });

  final String avatar;
  final String iniciais;
  final double raio;
  final Color corQuandoSemFoto;
  final Color corDasIniciais;

  @override
  Widget build(BuildContext context) {
    final origem = avatar.trim();
    final Widget semFoto = CircleAvatar(
      radius: raio,
      backgroundColor: corQuandoSemFoto,
      child: Text(
        iniciais.isEmpty ? '?' : iniciais,
        style: TextStyle(
          color: corDasIniciais,
          fontSize: raio * 0.8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    if (origem.isEmpty) return semFoto;

    return ClipOval(
      child: SizedBox(
        width: raio * 2,
        height: raio * 2,
        child: FittedBox(
          fit: BoxFit.cover,
          child: _imagemDe(origem, semFoto),
        ),
      ),
    );
  }

  Widget _imagemDe(String origem, Widget reserva) {
    if (origem.startsWith('data:')) {
      final virgula = origem.indexOf(',');
      if (virgula <= 0) return reserva;
      final Uint8List bytes;
      try {
        bytes = base64Decode(origem.substring(virgula + 1));
      } on FormatException {
        return reserva;
      }
      return Image.memory(
        bytes,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => reserva,
      );
    }

    final uri = Uri.tryParse(origem);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return reserva;
    }
    return Image.network(
      origem,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => reserva,
    );
  }
}
