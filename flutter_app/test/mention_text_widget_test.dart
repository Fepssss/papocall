import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/theme/hud_theme.dart';
import 'package:papocall/widgets/mention_text.dart';

/// Confere que a pintura das marcações sai como o esperado na tela, e não
/// apenas que a função de divisão dos trechos devolve a lista certa.
void main() {
  const estiloBase = TextStyle(color: HudTheme.textNormal, fontSize: 14);

  Future<void> montar(WidgetTester tester, String texto) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MentionText(
            text: texto,
            knownHandles: const {'ana', 'bruno'},
            selfHandle: 'bruno',
            baseStyle: estiloBase,
          ),
        ),
      ),
    );
  }

  testWidgets('texto sem marcação sai como Text simples', (tester) async {
    await montar(tester, 'mensagem comum');

    final texto = tester.widget<Text>(find.byType(Text));
    expect(texto.data, 'mensagem comum');
    // Sem spans: montar RichText à toa numa lista de centenas de mensagens
    // custaria caro sem nenhum ganho.
    expect(texto.textSpan, isNull);
  });

  testWidgets('marcação conhecida vira destaque e preserva o texto', (tester) async {
    await montar(tester, 'oi @ana, tudo certo?');

    // A marcação é um widget próprio (o destaque); o resto continua como
    // trechos do mesmo parágrafo, então é procurado pelo conteúdo.
    expect(find.text('@ana'), findsOneWidget);
    expect(find.textContaining('oi '), findsWidgets);
    expect(find.textContaining(', tudo certo?'), findsWidgets);
  });

  testWidgets('marcação de quem lê usa a cor de destaque próprio', (tester) async {
    await montar(tester, 'atenção @bruno');

    final chip = tester.widget<Text>(find.text('@bruno'));
    expect(chip.style?.color, HudTheme.green);
  });

  testWidgets('marcação de terceiro usa a cor secundária', (tester) async {
    await montar(tester, 'chama a @ana');

    final chip = tester.widget<Text>(find.text('@ana'));
    expect(chip.style?.color, HudTheme.accent);
  });

  testWidgets('@ de quem não existe continua texto comum', (tester) async {
    await montar(tester, 'oi @fantasma');

    // Nenhum destaque: dar aparência de marcação a um @ inexistente faria
    // parecer que alguém foi avisado quando não foi.
    final texto = tester.widget<Text>(find.byType(Text));
    expect(texto.data, 'oi @fantasma');
    expect(texto.textSpan, isNull);
  });

  testWidgets('várias marcações na mesma mensagem', (tester) async {
    await montar(tester, '@ana e @bruno, vamos?');

    expect(find.text('@ana'), findsOneWidget);
    expect(find.text('@bruno'), findsOneWidget);
    expect(find.textContaining(', vamos?'), findsWidgets);

    // As duas marcações saem coloridas de forma diferente: '@bruno' é quem lê.
    expect(tester.widget<Text>(find.text('@ana')).style?.color, HudTheme.accent);
    expect(tester.widget<Text>(find.text('@bruno')).style?.color, HudTheme.green);
  });
}
