import 'package:flutter/widgets.dart';

/// Proporções da HUD em função do tamanho da janela.
///
/// A interface foi desenhada para 1280x800 e tem quase trezentos tamanhos de
/// letra escritos um por um no código. Reescrevê-los seria trocar um desenho
/// inteiro; o que se faz aqui é escalar o que já existe — o texto pela cópia do
/// [MediaQuery] no `MaterialApp.builder`, e as colunas de largura fixa pelos
/// getters abaixo — para que a janela se aproveite sozinha em vez de sobrar
/// num monitor grande ou cortar linha por linha num menor.
class HudLayout {
  const HudLayout._(this.escala, this.larguraJanela);

  /// Largura de projeto: abaixo dela encolhe, acima dela cresce.
  static const double _base = 1280;

  static const double _escalaMinima = 0.85;
  static const double _escalaMaxima = 1.3;

  /// Fator aplicado ao texto de toda a árvore.
  final double escala;

  /// Largura lógica da janela, em pixels de lógica.
  final double larguraJanela;

  factory HudLayout.of(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final escala = (largura / _base).clamp(_escalaMinima, _escalaMaxima).toDouble();
    return HudLayout._(escala, largura);
  }

  /// Rail de servidores + lista de canais + perfil do usuário.
  double get painelEsquerdo => (312 * escala).clamp(264.0, 380.0).toDouble();

  /// Coluna vertical de ícones dos servidores, dentro do painel esquerdo.
  double get railServidores => (72 * escala).clamp(64.0, 90.0).toDouble();

  /// Lista de membros ao lado do chat.
  double get barraMembros => (240 * escala).clamp(200.0, 300.0).toDouble();

  /// A lista de membros é a primeira coisa a ceder espaço: sem ela o chat
  /// continua completo, e espremê-la é que fazia o texto dos balões virar
  /// reticências em uma janela estreita.
  bool get mostraBarraMembros => larguraJanela >= 1180;
}
