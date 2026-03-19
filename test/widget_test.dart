import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ai/src/app.dart';

void main() {
  testWidgets('ForgeAI app bootstraps', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ForgeAiApp()));
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
