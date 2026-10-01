import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/ui/operations_pages.dart';

Future<void> settleDatabase(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Database did not settle');
}

void main() {
  sqfliteFfiInit();
  testWidgets('accounting exposes seller details and report actions', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await tester.pumpWidget(MaterialApp(home: AccountingPage(store: store)));
      await settleDatabase(tester);
      expect(find.text('Alle Abrechnungen als PDF'), findsOneWidget);
      expect(find.textContaining('Auszahlung'), findsWidgets);
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
      expect(find.text('Einzelabrechnung als PDF'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await store.close();
    });
  });
  testWidgets('reconciliation scan persists and restores across page reopen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await tester.pumpWidget(
        MaterialApp(home: ReconciliationPage(store: store)),
      );
      await settleDatabase(tester);
      await tester.enterText(
        find.byKey(const Key('reconciliation-code')),
        'MM1|092700104200054|1|6BCD8E44',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleDatabase(tester);
      expect(
        (await store.reconciliationStates()).values.single['status'],
        'gefunden',
      );
      expect(find.textContaining('Gefunden: 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(home: ReconciliationPage(store: store)),
      );
      await settleDatabase(tester);
      expect(find.textContaining('Gefunden: 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await store.close();
    });
  });
}
