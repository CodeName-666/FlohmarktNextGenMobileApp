import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/data/demo_catalog.dart';
import 'package:flohmarkt_mobile/domain/catalog_search.dart';
import 'package:flohmarkt_mobile/domain/models.dart';
import 'package:flohmarkt_mobile/domain/money.dart';
import 'package:flohmarkt_mobile/services/receipt_qr.dart';
import 'package:flohmarkt_mobile/ui/receipt_qr_dialog.dart';
import 'package:flohmarkt_mobile/ui/register_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'register_safety_test.dart' show settleDatabase;

/// KAN-594: offline QR receipt text and the on-request button.
void main() {
  setUpAll(sqfliteFfiInit);

  const session = MarketSession(
    marketId: '9',
    name: 'Herbstmarkt',
    registerNumber: 2,
    exportGeneration: 3,
    metadata: {'organizerEmail': 'veranstalter@example.test'},
  );

  ArticleListing listing(int index, {String? title}) => ArticleListing(
    listingId: 'L$index',
    articleId: 'A$index',
    codeFull: '092700104200054',
    title: title ?? 'Artikel $index',
    priceCents: 150 + index,
    labelRevision: 1,
    exportGeneration: 3,
    boxNumber: 17,
    marketId: '9',
    fields: const {'sellerName': 'Erika Muster', 'email': 'erika@example.test'},
  );

  SaleEvent sale(int index, {String receiptId = 'R1', String? cancelOf}) =>
      SaleEvent(
        id: 'E$index',
        receiptId: receiptId,
        occurredAt: '2026-11-02T10:00:00Z',
        inputMethod: 'scan',
        cancelOf: cancelOf,
        registerNumber: 2,
        listing: listing(index),
      );

  test(
    'text carries receipt number, positions and totals, no personal data',
    () {
      final events = [sale(1), sale(2)];
      final receipt = Receipt(
        id: 'R1',
        occurredAt: '2026-11-02T10:00:00Z',
        number: 7,
        totalCents: 151 + 152,
        tenderedCents: 500,
        registerNumber: 2,
      );
      final text = receiptQrText(session, receipt, events);
      expect(text, contains('Kasse 2 · Beleg 7'));
      expect(text, contains('Summe: ${formatCents(receipt.totalCents)}'));
      expect(text, contains('Rückgeld: ${formatCents(receipt.changeCents)}'));
      expect(receiptPositions(receipt, events).map((e) => e.listing.title), [
        'Artikel 1',
        'Artikel 2',
      ]);
      for (final title in ['Artikel 1', 'Artikel 2']) {
        expect(text, contains(title));
      }
      for (final secret in [
        'Erika',
        'Muster',
        '@',
        'veranstalter',
        'Bearer',
        'token',
      ]) {
        expect(text, isNot(contains(secret)));
      }
    },
  );

  test(
    'a later cancellation is history; a refund receipt shows its position',
    () {
      final events = [sale(1), sale(9, receiptId: 'R2', cancelOf: 'E1')];
      final original = Receipt(
        id: 'R1',
        occurredAt: '2026-11-02T10:00:00Z',
        number: 1,
        totalCents: 151,
        tenderedCents: 151,
      );
      expect(
        receiptQrText(session, original, events),
        contains('Später storniert'),
      );
      final refund = Receipt(
        id: 'R2',
        occurredAt: '2026-11-02T10:05:00Z',
        number: 2,
        totalCents: -159,
        tenderedCents: -159,
      );
      final text = receiptQrText(session, refund, events);
      expect(text, contains('Storno: '));
      expect(text, contains('Summe: ${formatCents(-159)}'));
    },
  );

  test('long receipts stay below the limit and keep the full total', () {
    final events = [for (var i = 0; i < 60; i++) sale(i)];
    final total = events.fold<int>(0, (sum, e) => sum + e.listing.priceCents);
    final receipt = Receipt(
      id: 'R1',
      occurredAt: '2026-11-02T10:00:00Z',
      number: 12,
      totalCents: total,
      tenderedCents: total,
    );
    final text = receiptQrText(session, receipt, events);
    expect(text.length, lessThanOrEqualTo(receiptQrLimit));
    expect(text, matches(RegExp(r'… und \d+ weitere Artikel')));
    expect(text, contains('Summe: ${formatCents(total)}'));
    expect(text, contains('Beleg 12'));
    final encoded = QrValidator.validate(
      data: text,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
    expect(encoded.status, QrValidationStatus.valid);
  });

  Future<void> sell(WidgetTester tester) async {
    final scan = tester.widget<TextField>(find.byKey(const Key('scan-input')));
    scan.onSubmitted!(demoPayload);
    await settleDatabase(tester);
    await tester.tap(find.byKey(const Key('checkout')));
    await settleDatabase(tester);
    await tester.enterText(find.byKey(const Key('tendered')), '10');
    await tester.tap(find.text('Barzahlung bestätigen'));
    await settleDatabase(tester);
  }

  testWidgets('QR only on request; the next scan hides the button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterPage(store: store, wakelock: (_) async {}),
        ),
      );
      await settleDatabase(tester);
      await sell(tester);
      expect(find.text('QR-Quittung'), findsOneWidget); // on the saved screen
      expect(find.byType(ReceiptQrDialog), findsNothing);
      await tester.tap(find.text('Nächster Vorgang'));
      await settleDatabase(tester);

      final button = find.byKey(const Key('receipt-qr'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      // The dialog opens after the receipt positions are read from the database.
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(ReceiptQrDialog).evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt-qr-code')), findsOneWidget);
      await tester.tap(find.text('Schließen'));
      await settleDatabase(tester);

      final scan = tester.widget<TextField>(
        find.byKey(const Key('scan-input')),
      );
      scan.onSubmitted!('MM1|092700104200062|1|7DF55D18');
      await settleDatabase(tester);
      expect(button, findsNothing);
      expect(await store.cartLines(), hasLength(1));
      await store.close();
    });
  });

  testWidgets('switched off, no QR button appears', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await store.setSetting('uiSettings', {'receiptQr': false});
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterPage(store: store, wakelock: (_) async {}),
        ),
      );
      await settleDatabase(tester);
      await sell(tester);
      expect(find.text('QR-Quittung'), findsNothing);
      await tester.tap(find.text('Nächster Vorgang'));
      await settleDatabase(tester);
      expect(find.byKey(const Key('receipt-qr')), findsNothing);
      await store.close();
    });
  });
}
