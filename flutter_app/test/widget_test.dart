import 'package:flutter_test/flutter_test.dart';
import 'package:papocall/main.dart';

void main() {
  testWidgets('PapoCall App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PapoCallApp());
    expect(find.byType(PapoCallApp), findsOneWidget);
  });
}
