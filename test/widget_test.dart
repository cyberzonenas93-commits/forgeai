import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ai/src/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('CodeCatalystAI app bootstraps', (tester) async {
    SharedPreferences.setMockInitialValues({
      'forge_onboarding_completed': true,
    });
    await tester.pumpWidget(const ProviderScope(child: ForgeAiApp()));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Sign in').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('Sign in'), findsWidgets);
    expect(
      find.text('Stay close to your code, even when you are away from the desk.'),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });
}
