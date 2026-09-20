import 'package:flutter/widgets.dart';

/// Proporções da HUD em função do tamanho da janela.
///
/// A interface foi desenhada para 1280x800 e tem quase trezentos tamanhos de
/// letra escritos um por um no código. Reescrevê-los seria trocar um desenho
/// inteiro; o que se faz aqui é ceder terreno quando a janela aperta — o texto
/// pela cópia do [MediaQuery] no `MaterialApp.builder`, e as colunas de largura
/// fixa pelos getters abaixo — para que nada corte linha por linha numa janela
/// menor. Para cima a escala não passa de 1: o tamanho desenhado é o tamanho
/// que se vê, e a janela grande serve para mostrar mais conteúdo, não letras
/// maiores.
class HudLayout {
  const HudLayout._(this.escala, this.larguraJanela);

  /// Largura de projeto: abaixo dela a interface encolhe, acima dela fica no
  /// tamanho desenhado.
  static const double _base = 1280;

  static const double _escalaMinima = 0.85;

  /// A escala para em 1 de propósito. A HUD foi desenhada no tamanho que se vê
  /// numa janela cheia, e inflar tudo em 30% num monitor grande não ganhou
  /// espaço nenhum — só estourou a barra de cima e fez o painel parecer maior
  /// do que a pessoa escolheu. Acima da largura de projeto a interface fica
  /// exatamente como é hoje; abaixo dela é que ela cede.
  static const double _escalaMaxima = 1.0;

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
  double get painelEsquerdo => 312 * escala;

  /// Coluna vertical de ícones dos servidores, dentro do painel esquerdo.
  double get railServidores => 72 * escala;

  /// Lista de membros ao lado do chat.
  double get barraMembros => 240 * escala;

  /// A lista de membros é a primeira coisa a ceder espaço: sem ela o chat
  /// continua completo, e espremê-la é que fazia o texto dos balões virar
  /// reticências em uma janela estreita.
  bool get mostraBarraMembros => larguraJanela >= 1180;
}
