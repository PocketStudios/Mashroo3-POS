import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mashroo3/main.dart';

void main() {
  testWidgets('opens Mashroo3 Remote Control dialog from API key screen', (
    WidgetTester tester,
  ) async {
    await EasyLocalization.ensureInitialized();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: MaterialApp(
          home: ApiKeyScreen(
            onSubmit: (String apiKey) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder openRemoteControl = find.widgetWithIcon(
      OutlinedButton,
      Icons.support_agent_outlined,
    );
    expect(openRemoteControl, findsOneWidget);
    await tester.tap(openRemoteControl);
    await tester.pumpAndSettle();

    final Finder dialogFinder = find.byType(AlertDialog);
    expect(dialogFinder, findsOneWidget);
    expect(
      find.descendant(
        of: dialogFinder,
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is Text &&
              ((widget.data?.contains('Windows desktop only') ?? false) ||
                  (widget.data?.contains(
                        'remote_control.unsupported_platform',
                      ) ??
                      false)),
        ),
      ),
      findsOneWidget,
    );

    final Finder startButton = find.descendant(
      of: dialogFinder,
      matching: find.byType(FilledButton),
    );
    expect(startButton, findsOneWidget);
    final FilledButton button = tester.widget<FilledButton>(startButton);
    expect(button.onPressed, isNull);
  });

  testWidgets('opens Mashroo3 Remote Control dialog from app bar', (
    WidgetTester tester,
  ) async {
    await EasyLocalization.ensureInitialized();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: MaterialApp(
          home: PosScreen(
            apiKey: 'abcd1234',
            openingCash: 100,
            products: const <Product>[],
            orders: const <PosOrder>[],
            customers: const <Customer>[Customer.walkIn()],
            selectedCustomer: const Customer.walkIn(),
            cartItems: const <CartItem>[],
            cartTotal: 0,
            todaySales: 0,
            displayCurrency: PosDisplayCurrency.usd,
            dailyExchangeRate: 89500,
            onLogout: () async {},
            onRefreshData: () async =>
                PosActionResult(success: true, message: 'ok'),
            onAddProduct: (Product product) =>
                PosActionResult(success: true, message: 'ok'),
            onBarcodeSubmit: (String barcode) =>
                PosActionResult(success: true, message: 'ok'),
            onChangeQuantity: (Product product, double delta) {},
            onCustomerSelected: (Customer customer) {},
            onCreateCustomer: (String name, String? phone) async =>
                PosActionResult(success: true, message: 'ok'),
            onCreateOrder: (String? orderDescription, double paidAmount) async =>
                PosActionResult(success: true, message: 'ok'),
            onUpdateCurrencySettings: (
              PosDisplayCurrency displayCurrency,
              double dailyExchangeRate,
            ) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.support_agent_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.support_agent_outlined));
    await tester.pumpAndSettle();

    final Finder dialogFinder = find.byType(AlertDialog);
    expect(dialogFinder, findsOneWidget);
    expect(
      find.descendant(
        of: dialogFinder,
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is Text &&
              ((widget.data?.contains('Windows desktop only') ?? false) ||
                  (widget.data?.contains(
                        'remote_control.unsupported_platform',
                      ) ??
                      false)),
        ),
      ),
      findsOneWidget,
    );

    final Finder startButton = find.descendant(
      of: dialogFinder,
      matching: find.byType(FilledButton),
    );
    expect(startButton, findsOneWidget);
    final FilledButton button = tester.widget<FilledButton>(startButton);
    expect(button.onPressed, isNull);
  });
}
