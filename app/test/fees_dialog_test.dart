import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/ui/operations_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// KAN-603: the fee dialog lays its fields out without overlap.
void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('fee fields are stacked with space between them', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await tester.pumpWidget(MaterialApp(home: StatisticsPage(store: store)));
      final fees = find.byTooltip('Gebühren');
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 20));
        final button = tester.widget<IconButton>(
          find.ancestor(of: fees, matching: find.byType(IconButton)),
        );
        if (button.onPressed != null) break;
      }
      await tester.tap(fees);
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      final fields = find.descendant(
        of: dialog,
        matching: find.byType(TextField),
      );
      expect(fields, findsNWidgets(2));
      final share = tester.getRect(fields.at(0));
      final box = tester.getRect(fields.at(1));
      expect(box.top - share.bottom, greaterThanOrEqualTo(8));
      // Both fields use the full dialog width.
      expect(share.width, box.width);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Abbrechen'));
      // Closing reloads the page; let the database work finish.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(dialog, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await store.close();
    });
  });
}
