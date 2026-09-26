import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/domain/models.dart';

const realSession = MarketSession(
  marketId: '42',
  name: 'Herbstmarkt',
  registerNumber: 3,
  exportGeneration: 7,
  exportChecksum: 'fixture',
);
const realListing = ArticleListing(
  listingId: 'listing-a',
  articleId: 'article-a',
  codeFull: '092700104200054',
  title: 'Buch',
  priceCents: 250,
  labelRevision: 1,
  exportGeneration: 7,
  boxNumber: 7,
  marketId: '42',
);

void main() {
  late CheckoutStore store;
  late Directory dir;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('full_port_');
    store = await CheckoutStore.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/cash.db',
      session: realSession,
      listings: [realListing],
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test(
    'held drafts block restore and imports without being discarded',
    () async {
      final empty = await store.backup();
      await store.addManual(realListing.codeFull, 1);
      await store.swapCustomer();
      await expectLater(store.restoreBackup(empty), throwsStateError);
      await expectLater(store.importEvents([]), throwsStateError);
      expect(await store.heldCart(), hasLength(1));
    },
  );
  test('held return cannot be invalidated by immediate cancellation', () async {
    await store.addManual(realListing.codeFull, 1);
    await store.checkout(250);
    final sale = (await store.events()).single;
    await store.addReturn(realListing.listingId);
    await store.swapCustomer();
    await expectLater(store.cancel(sale.id), throwsStateError);
    expect(await store.activeSales(), hasLength(1));
    expect(await store.heldCart(), hasLength(1));
  });
  test('customer sequence is per cash desk after import', () async {
    final external = SaleEvent(
      id: 'external',
      receiptId: 'desktop:9:99',
      occurredAt: '2026-09-26T12:00:00Z',
      inputMethod: 'manual',
      cancelOf: null,
      registerNumber: 9,
      customerNumber: 99,
      listing: realListing,
    );
    await store.importEvents([external]);
    await store.cancel(external.id);
    final refund = (await store.receipts()).first;
    expect(refund.registerNumber, 3);
    expect(refund.customerNumber, 1);
    expect(refund.totalCents, -250);
    await store.addManual(realListing.codeFull, 1);
    final receipt = await store.checkout(250);
    expect(receipt.number, 3);
    expect(receipt.customerNumber, 2);
    expect((await store.events()).last.customerNumber, 2);
    await store.close();
    store = await CheckoutStore.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/cash.db',
      session: realSession,
      requireExisting: true,
    );
    expect((await store.receipts()).first.customerNumber, 2);
  });
  test(
    'duplicate event checks full snapshot but accepts desktop receipt alias',
    () async {
      await store.addManual(realListing.codeFull, 1);
      await store.checkout(250);
      final sale = (await store.events()).single;
      final alias = SaleEvent.fromMap({
        ...sale.toMap(),
        'receiptId': 'desktop:3:1',
        'legacyArticleNumber': 5,
      });
      await store.importEvents([alias]);
      expect(await store.events(), hasLength(1));
      for (final changed in [
        {'title': 'Changed'},
        {'labelRevision': 2},
        {'inputMethod': 'other'},
        {'boxNumber': 99},
      ]) {
        await expectLater(
          store.importEvents([
            SaleEvent.fromMap({...sale.toMap(), ...changed}),
          ]),
          throwsStateError,
        );
      }
    },
  );
  test(
    'existing receipt rejects extra sale and preserves original totals',
    () async {
      await store.addManual(realListing.codeFull, 1);
      await store.checkout(250);
      final sale = (await store.events()).single;
      await expectLater(
        store.importEvents([
          SaleEvent.fromMap({...sale.toMap(), 'id': 'new-event'}),
        ]),
        throwsStateError,
      );
      expect(await store.events(), hasLength(1));
      expect((await store.receipts()).single.totalCents, 250);
    },
  );
  test('backup rejects inconsistent receipt total transactionally', () async {
    await store.addManual(realListing.codeFull, 1);
    await store.checkout(500);
    final backup = await store.backup();
    backup['receipts'] = [
      Map<String, Object?>.from((backup['receipts'] as List).single as Map)
        ..['totalCents'] = 100,
    ];
    final target = await CheckoutStore.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/bad-total.db',
      session: realSession,
    );
    await expectLater(target.restoreBackup(backup), throwsFormatException);
    expect(await target.receipts(), isEmpty);
    expect(await target.events(), isEmpty);
    await target.close();
  });

  test(
    'real market identity and cash desk persist on receipt and outbox',
    () async {
      await store.addManual(realListing.codeFull, 1);
      final receipt = await store.checkout(500);
      expect(receipt.registerNumber, 3);
      final event = (await store.events()).single;
      expect(event.customerNumber, 1);
      expect(event.registerNumber, 3);
      expect(event.listing.exportGeneration, 7);
      expect(await store.pendingEvents(), hasLength(1));
      await store.acknowledgeEvents([event.id]);
      expect(await store.pendingEvents(), isEmpty);
    },
  );
  test(
    'return is a draft until checkout; removing it leaves original sale',
    () async {
      await store.addManual(realListing.codeFull, 1);
      await store.checkout(250);
      await store.addReturn(realListing.listingId);
      expect((await store.cartLines()).single.signedCents, -250);
      expect(await store.events(), hasLength(1));
      await store.remove(realListing.listingId);
      expect(await store.activeSales(), hasLength(1));
      await store.addReturn(realListing.listingId);
      final refund = await store.checkout(0);
      expect(refund.changeCents, 250);
      expect(await store.activeSales(), isEmpty);
      expect(await store.events(), hasLength(2));
    },
  );
  test(
    'parallel customers preserve drafts and reserve their articles',
    () async {
      await store.addManual(realListing.codeFull, 1);
      await store.swapCustomer();
      expect(await store.cartLines(), isEmpty);
      expect(await store.heldCart(), hasLength(1));
      await expectLater(
        store.addManual(realListing.codeFull, 1),
        throwsStateError,
      );
      await store.swapCustomer();
      expect(await store.heldCart(), isEmpty);
      await store.checkout(250);
      expect(await store.events(), hasLength(1));
    },
  );
  test('import deduplicates and rolls back conflicting identities', () async {
    await store.addManual(realListing.codeFull, 1);
    await store.checkout(250);
    final original = (await store.events()).single;
    await store.importEvents([original]);
    expect(await store.events(), hasLength(1));
    final invalid = SaleEvent(
      id: original.id,
      receiptId: original.receiptId,
      occurredAt: original.occurredAt,
      inputMethod: 'manual',
      cancelOf: null,
      registerNumber: 9,
      listing: realListing,
    );
    await expectLater(store.importEvents([invalid]), throwsStateError);
    expect((await store.events()).single.registerNumber, 3);
  });
  test(
    'optional tender is recorded as unknown, logs redact and filter',
    () async {
      await store.addManual(realListing.codeFull, 1);
      final receipt = await store.checkout(250, tenderedKnown: false);
      expect(receipt.tenderedKnown, false);
      expect((await store.receipts()).single.tenderedKnown, false);
      await store.setSetting('uiSettings', {
        'logLevel': 'WARNING',
        'logCategories': ['sync'],
      });
      await store.log('sync', 'routine');
      await store.log('scanner', 'wrong category', level: 'ERROR');
      await store.log(
        'sync',
        'token=secret Bearer sensitive',
        level: 'WARNING',
      );
      final logs = await store.logs();
      expect(logs, hasLength(1));
      expect(logs.single['message'], isNot(contains('secret')));
      expect(logs.single['message'], isNot(contains('sensitive')));
      expect(store.loggingFailure, isNull);
    },
  );
  test('corrupt backup draft cannot replace catalog or settings', () async {
    await store.addManual(realListing.codeFull, 1);
    final backup = await store.backup();
    final rows = backup['cart'] as List;
    final broken = Map<String, Object?>.from(rows.single as Map)
      ..['listingId'] = 'different';
    backup['cart'] = [broken];
    final target = await CheckoutStore.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/invalid.db',
      session: realSession,
      listings: [realListing],
    );
    await expectLater(target.restoreBackup(backup), throwsFormatException);
    expect(await target.cartLines(), isEmpty);
    expect(
      (await target.allListings()).single.listingId,
      realListing.listingId,
    );
    await target.close();
  });
  test(
    'wrong generation/session cannot reopen an existing cash desk',
    () async {
      await store.close();
      await expectLater(
        CheckoutStore.open(
          factory: databaseFactoryFfi,
          path: '${dir.path}/cash.db',
          session: const MarketSession(
            marketId: 'other',
            name: 'Other',
            registerNumber: 3,
            exportGeneration: 7,
          ),
          listings: [realListing],
        ),
        throwsStateError,
      );
      store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/cash.db',
        session: realSession,
      );
    },
  );
  test(
    'backup roundtrip preserves receipts, draft, event IDs and outbox',
    () async {
      await store.addManual(realListing.codeFull, 1);
      await store.checkout(250);
      await store.addReturn(realListing.listingId);
      final backup = await store.backup();
      final target = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/restore.db',
        session: realSession,
      );
      await target.restoreBackup(backup);
      expect(
        (await target.events()).single.id,
        (await store.events()).single.id,
      );
      expect(
        (await target.cartLines()).single.cancelOf,
        (await store.events()).single.id,
      );
      expect(await target.pendingEvents(), hasLength(1));
      await target.close();
    },
  );
}
