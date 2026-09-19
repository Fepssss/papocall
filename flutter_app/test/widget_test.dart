import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:papocall/main.dart';
import 'package:papocall/providers/app_state.dart';
import 'app_sandbox.dart';

void main() {
  useAppDataSandbox();

  testWidgets('PapoCall App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
        ],
        child: const PapoCallApp(),
      ),
    );
    expect(find.byType(PapoCallApp), findsOneWidget);
  });
}
