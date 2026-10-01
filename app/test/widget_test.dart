import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/data/demo_catalog.dart';
import 'package:flohmarkt_mobile/ui/register_page.dart';

Future<void> settleDatabase(WidgetTester tester) async {
  // FFI runs in a real isolate. Yield real time before waiting for animations.
  for (var attempt = 0; attempt < 200; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Database operation did not finish.');
}

void main() {
  testWidgets('rapid HID submissions keep focus and both articles', (
    tester,
  ) async {
    sqfliteFfiInit();
    await tester.runAsync(() async {
      final store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await tester.pumpWidget(MaterialApp(home: RegisterPage(store: store)));
      await settleDatabase(tester);
      final input = find.byKey(const Key('scan-input'));
      await tester.enterText(input, demoPayload);
      // Invoke the same callbacks as a HID Enter, without yielding to SQLite.
      final field = tester.widget<TextField>(input);
      field.onEditingComplete?.call();
      field.onSubmitted!(demoPayload);
      field.onSubmitted!('MM1|092700104200062|1|7DF55D18');
      await settleDatabase(tester);
      expect(await store.cart(), hasLength(2));
      expect(field.focusNode!.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await store.close();
    });
  });

  testWidgets('phone supports scan, duplicate feedback and cash checkout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    await tester.runAsync(() async {
      final store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await tester.pumpWidget(MaterialApp(home: RegisterPage(store: store)));
      await settleDatabase(tester);
      expect(find.text('Demo · Keine echten Verkäufe'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('scan-input')), demoPayload);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleDatabase(tester);
      expect(find.text('Kinderbuch · Waldabenteuer'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('scan-input')), demoPayload);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleDatabase(tester);
      expect(find.text('Artikel liegt bereits im Warenkorb.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('checkout')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tendered')), '10');
      await tester.tap(find.text('Barzahlung bestätigen'));
      await settleDatabase(tester);
      expect(find.text('Beleg 1 gespeichert'), findsOneWidget);
      expect(find.text('7,50 €'), findsOneWidget);
      expect(await store.events(), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await store.close();
    });
  });
}
