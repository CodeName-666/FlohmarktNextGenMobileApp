import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/data/demo_catalog.dart';
import 'package:flohmarkt_mobile/ui/register_page.dart';
import 'package:flohmarkt_mobile/ui/payment_dialog.dart';
import 'package:flohmarkt_mobile/ui/receipt_page.dart';

Future<void> settleDatabase(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
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
  setUpAll(sqfliteFfiInit);
  testWidgets('failed payment persists dialog and amount then retries once', (
    tester,
  ) async {
    var attempts = 0;
    PaymentInput? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<PaymentInput>(
              context: context,
              builder: (_) => PaymentDialog(
                totalCents: 250,
                onConfirm: (input) async {
                  attempts++;
                  if (attempts == 1) throw StateError('Speicher voll');
                  saved = input;
                },
              ),
            ),
            child: const Text('Zahlen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Zahlen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tendered')), '10');
    await tester.tap(find.text('Barzahlung bestätigen'));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentDialog), findsOneWidget);
    expect(find.textContaining('Speicher voll'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('tendered')))
          .controller!
          .text,
      '10',
    );
    await tester.tap(find.text('Barzahlung bestätigen'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(saved!.cents, 1000);
    expect(saved!.known, isTrue);
    expect(find.byType(PaymentDialog), findsNothing);
  });

  testWidgets('payment serializes confirmation and blank cash stays unknown', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    PaymentInput? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentDialog(
          totalCents: 250,
          onConfirm: (input) async {
            calls++;
            saved = input;
            await pending.future;
          },
        ),
      ),
    );
    final callback = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Barzahlung bestätigen'),
        )
        .onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(calls, 1);
    expect(saved!.known, isFalse);
    expect(saved!.cents, 250);
    expect(
      tester.widget<TextField>(find.byKey(const Key('tendered'))).enabled,
      isFalse,
    );
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'recovery gates manual camera search demo remove and pay for both baskets',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final store = await CheckoutStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        await store.addScan(demoPayload);
        await store.swapCustomer();
        await store.addScan('MM1|092700104200062|1|7DF55D18');
        await tester.pumpWidget(MaterialApp(home: RegisterPage(store: store)));
        await settleDatabase(tester);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Manuell'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Kamera'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Artikel suchen'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('checkout')))
              .onPressed,
          isNull,
        );
        final scan = tester.widget<TextField>(
          find.byKey(const Key('scan-input')),
        );
        scan.onSubmitted!(demoPayload);
        await tester.pumpAndSettle();
        expect(await store.cart(), hasLength(1));
        expect(await store.events(), isEmpty);
        final switchButton = find.widgetWithText(
          OutlinedButton,
          'Kundenkorb parken / wechseln · 1 wartend (2,50 €)',
        );
        await tester.tap(switchButton);
        await settleDatabase(tester);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Manuell'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Manuell'),
              )
              .onPressed,
          isNotNull,
        );
        expect(await store.events(), isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await store.close();
      });
    },
  );

  testWidgets(
    'receipt history includes return receipt and original reference',
    (tester) async {
      await tester.runAsync(() async {
        final store = await CheckoutStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        await store.addScan(demoPayload);
        await store.checkout(250);
        final sale = (await store.events()).single;
        await store.addReturn(sale.listing.listingId);
        await store.checkout(0);
        await tester.pumpWidget(MaterialApp(home: ReceiptPage(store: store)));
        await settleDatabase(tester);
        expect(find.textContaining('Storno / Rückgabe'), findsWidgets);
        expect(find.textContaining('Original: ${sale.id}'), findsWidgets);
        expect(find.text('Bon erneut drucken / teilen'), findsWidgets);
        expect(await store.events(), hasLength(2));
        await tester.pumpWidget(const SizedBox.shrink());
        await store.close();
      });
    },
  );
}
