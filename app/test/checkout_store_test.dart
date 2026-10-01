import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/data/demo_catalog.dart';

void main() {
  late Directory directory;
  late CheckoutStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mobile_checkout_');
    store = await CheckoutStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/checkout.db',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'scan reserves once and rejects wrong revision and unknown item',
    () async {
      await store.addScan(demoPayload);
      await expectLater(store.addScan(demoPayload), throwsStateError);
      await expectLater(
        store.addManual('092700104200054', 2),
        throwsFormatException,
      );
      await expectLater(store.addManual('09270010429999', 1), throwsStateError);
      expect((await store.cart()).single.priceCents, 250);
      expect(await store.events(), isEmpty);
    },
  );

  test('underpayment and empty checkout never create a receipt', () async {
    await expectLater(store.checkout(500), throwsStateError);
    await store.addScan(demoPayload);
    await expectLater(store.checkout(249), throwsStateError);
    expect(await store.receipts(), isEmpty);
    expect(await store.cart(), hasLength(1));
  });

  test('checkout writes exact snapshots, then cancel and resell', () async {
    await store.addScan(demoPayload);
    final receipt = await store.checkout(1000);
    expect(receipt.totalCents, 250);
    expect(receipt.changeCents, 750);
    expect(await store.cart(), isEmpty);
    final sale = (await store.events()).single;
    expect(sale.id[14], '7');
    expect(sale.listing.labelRevision, 1);
    expect(sale.listing.exportGeneration, 1);
    expect(sale.listing.boxNumber, 7); // Seller is 42, not this box.
    await expectLater(store.addScan(demoPayload), throwsStateError);
    await store.cancel(sale.id);
    await expectLater(store.cancel(sale.id), throwsStateError);
    final history = await store.events();
    expect(history.where((e) => e.id == sale.id).single.cancelOf, isNull);
    expect(history.where((e) => e.cancelOf == sale.id), hasLength(1));
    await store.addScan(demoPayload);
    await store.checkout(250);
    expect(await store.events(), hasLength(3));
  });

  test('pending cart and committed sales survive database reopen', () async {
    await store.addScan(demoPayload);
    await store.close();
    store = await CheckoutStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/checkout.db',
    );
    expect(await store.cart(), hasLength(1));
    await store.checkout(250);
    await store.close();
    store = await CheckoutStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/checkout.db',
    );
    expect(await store.cart(), isEmpty);
    expect(await store.events(), hasLength(1));
    expect(await store.receipts(), hasLength(1));
  });

  test('write failure rolls back receipt, sales and cart deletion', () async {
    await store.addScan(demoPayload);
    // Same database connection: inject a real SQLite write failure.
    final db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/checkout.db',
    );
    await db.execute(
      "CREATE TRIGGER fail_sale BEFORE INSERT ON events "
      "BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END",
    );
    await expectLater(store.checkout(500), throwsA(isA<DatabaseException>()));
    expect(await store.cart(), hasLength(1));
    expect(await store.receipts(), isEmpty);
    expect(await store.events(), isEmpty);
    await db.execute('DROP TRIGGER fail_sale');
    expect((await store.checkout(500)).number, 1);
  });

  test('concurrent checkout cannot sell a cart twice', () async {
    await store.addScan(demoPayload);
    final results = await Future.wait([
      store.checkout(500).then<Object>((r) => r).catchError((Object e) => e),
      store.checkout(500).then<Object>((r) => r).catchError((Object e) => e),
    ]);
    expect(results.whereType<StateError>(), hasLength(1));
    expect(await store.events(), hasLength(1));
  });
}
