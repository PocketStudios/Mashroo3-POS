import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mashroo3/main.dart';

void main() {
  testWidgets('api key screen shows account flow', (WidgetTester tester) async {
    await EasyLocalization.ensureInitialized();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: MaterialApp(
          home: ApiKeyScreen(
            onSubmit: (String apiKey, PosAppMode mode) async {},
            initialMode: PosAppMode.pos,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mashroo3'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
    expect(find.text("I don't have an account"), findsOneWidget);

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
