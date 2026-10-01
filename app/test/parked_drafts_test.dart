import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/domain/models.dart';
import 'package:flohmarkt_mobile/services/desktop_draft.dart';
import 'full_checkout_test.dart' show realSession, realListing;

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory dir;
  late CheckoutStore store;
  late List<ArticleListing> listings;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('parked_drafts_');
    listings = List.generate(
      5,
      (i) => ArticleListing.fromMap({
        ...realListing.toMap(),
        'listingId': 'listing-$i',
        'articleId': 'article-$i',
        'boxNumber': i + 7,
      }),
    );
    store = await CheckoutStore.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/cash.db',
      session: realSession,
      listings: listings,
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test(
    'corrupt next number rolls back restoration into an empty register',
    () async {
      final backup = Map<String, Object?>.from(
        jsonDecode(jsonEncode(await store.backup())) as Map,
      );
      (backup['settings'] as List).add({
        'key': 'nextDraftNumber',
        'value': '-1',
      });
      await expectLater(store.restoreBackup(backup), throwsFormatException);
      expect(await store.activeDraftNumber(), 1);
      await store.addResolved(listings[0]);
      expect((await store.checkout(250)).customerNumber, 1);
    },
  );

  test(
    'previously exported event keeps its number after newer checkouts',
    () async {
      await store.addResolved(listings[0]);
      final first = await store.exportDesktopDraft();
      final originalId = (await store.cartLines()).single.pendingEventId;
      expect((first!['kunde'] as Map)['kunden_nummer'], 1);
      await store.parkCart();
      await store.addResolved(listings[1]);
      await store.checkout(250);
      final parked = (await store.parkedDrafts()).single;
      await expectLater(
        store.desktopDraftExportNumber(draftId: parked.id),
        throwsStateError,
      );
      await expectLater(
        store.exportDesktopDraft(draftId: parked.id),
        throwsStateError,
      );
      expect((await store.parkedDrafts()).single.number, 1);
      await store.resumeDraft(parked.id);
      expect((await store.checkout(250)).customerNumber, 1);
      expect((await store.events()).last.id, originalId);
    },
  );

  test(
    'imported desktop draft also preserves its external event number',
    () async {
      await store.addResolved(listings[0]);
      final raw = await store.exportDesktopDraft();
      final draft = DesktopDraft.decode(
        raw,
        session: realSession,
        catalog: listings,
        committedEvents: [],
        exportBody: {},
      )!;
      final target = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/imported.db',
        session: realSession,
        listings: listings,
      );
      addTearDown(target.close);
      await target.importEventsAndDraft([], draft);
      await target.parkCart();
      await target.addResolved(listings[1]);
      await target.checkout(250);
      final parked = (await target.parkedDrafts()).single;
      await expectLater(
        target.exportDesktopDraft(draftId: parked.id),
        throwsStateError,
      );
      expect((await target.parkedDrafts()).single.number, 1);
    },
  );

  test(
    'three parked drafts retain reservations, payments and event identities after recovery',
    () async {
      final eventIds = <String?>[];
      for (var i = 0; i < 3; i++) {
        await store.addResolved(listings[i]);
        eventIds.add((await store.cartLines()).single.pendingEventId);
        await store.setSetting('draftPaymentInput', '${i + 5},00');
        await (store as dynamic).parkCart();
      }
      await store.close();
      store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/cash.db',
        requireExisting: true,
      );
      final drafts = await (store as dynamic).parkedDrafts() as List;
      expect(drafts.map((d) => d.number), [1, 2, 3]);
      expect(await store.events(), isEmpty);
      for (var i = 0; i < 3; i++) {
        await expectLater(store.addResolved(listings[i]), throwsStateError);
      }
      await store.addResolved(listings[3]);
      expect((await store.checkout(250)).customerNumber, 4);
      await (store as dynamic).resumeDraft(drafts[1].id);
      expect(await store.setting('draftPaymentInput'), '6,00');
      expect((await store.cartLines()).single.pendingEventId, eventIds[1]);
      expect((await store.checkout(250)).customerNumber, 2);
      expect((await (store as dynamic).parkedDrafts() as List).length, 2);
      await store.addResolved(listings[4]);
      expect((await store.checkout(250)).customerNumber, 5);
    },
  );

  test(
    'legacy held draft migrates on restore with its payment and reserved number',
    () async {
      await store.addResolved(listings[0]);
      final backup = Map<String, Object?>.from(
        jsonDecode(jsonEncode(await store.backup())) as Map,
      );
      final rows = backup['cart'] as List;
      backup['cart'] = <Object?>[];
      final settings = (backup['settings'] as List)
          .cast<Map>()
          .where(
            (r) => ![
              'parkedDrafts',
              'draftCustomerNumber',
              'nextDraftNumber',
            ].contains(r['key']),
          )
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      settings.addAll([
        {'key': 'heldCart', 'value': jsonEncode(rows)},
        {'key': 'heldDraftCustomerNumber', 'value': '7'},
        {'key': 'heldPaymentInput', 'value': jsonEncode('10,00')},
      ]);
      backup['settings'] = settings;
      await store.discardCart();
      await store.restoreBackup(backup);
      final drafts = await (store as dynamic).parkedDrafts() as List;
      expect(drafts.single.number, 7);
      await (store as dynamic).resumeDraft(drafts.single.id);
      expect(await store.setting('draftPaymentInput'), '10,00');
      expect((await store.checkout(250)).customerNumber, 7);
      await store.addResolved(listings[1]);
      expect((await store.checkout(250)).customerNumber, 8);
    },
  );

  test(
    'backup preserves every parked sale-return pair and invalid duplicate rolls back restore',
    () async {
      for (var i = 0; i < 3; i++) {
        await store.addResolved(listings[i]);
        await store.addReturn(listings[i].listingId);
        await (store as dynamic).parkCart();
      }
      final backup = Map<String, Object?>.from(
        jsonDecode(jsonEncode(await store.backup())) as Map,
      );
      final restored = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/restored.db',
        session: realSession,
        listings: listings,
      );
      addTearDown(restored.close);
      await restored.restoreBackup(backup);
      final drafts = await (restored as dynamic).parkedDrafts() as List;
      expect(drafts.length, 3);
      await (restored as dynamic).resumeDraft(drafts.last.id);
      final pair = await restored.cartLines();
      await expectLater(restored.checkout(-1), throwsStateError);
      expect(await restored.events(), isEmpty);
      expect(
        (await restored.cartLines()).first.pendingEventId,
        pair.first.pendingEventId,
      );
      await restored.checkout(0);
      final events = await restored.events();
      expect(events.last.cancelOf, events.first.id);
      expect(events.first.id, pair.first.pendingEventId);

      final settings = (backup['settings'] as List).cast<Map>();
      final parked = settings.singleWhere((r) => r['key'] == 'parkedDrafts');
      final corrupt = jsonDecode(parked['value'] as String) as List;
      corrupt[2]['rows'] = corrupt[0]['rows'];
      parked['value'] = jsonEncode(corrupt);
      final empty = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/invalid.db',
        session: realSession,
        listings: listings,
      );
      addTearDown(empty.close);
      await expectLater(empty.restoreBackup(backup), throwsFormatException);
      expect(await (empty as dynamic).parkedDrafts(), isEmpty);
    },
  );

  test(
    'older parked desktop export renumbers atomically and subsequent checkout keeps its identity',
    () async {
      for (var i = 0; i < 3; i++) {
        await store.addResolved(listings[i]);
        await (store as dynamic).parkCart();
      }
      final drafts = await (store as dynamic).parkedDrafts() as List;
      await store.addResolved(listings[3]);
      await store.checkout(250);
      expect(await store.desktopDraftExportNumber(draftId: drafts[2].id), 5);
      expect((await store.parkedDrafts()).last.number, 3);
      final originalId =
          (drafts[2] as ParkedDraft).entries.single.pendingEventId;
      final database = await databaseFactoryFfi.openDatabase(
        '${dir.path}/cash.db',
      );
      await database.execute(
        "CREATE TRIGGER reject_export BEFORE INSERT ON settings WHEN NEW.key = 'parkedDrafts' BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
      );
      await expectLater(
        store.exportDesktopDraft(draftId: drafts[2].id as String),
        throwsA(isA<DatabaseException>()),
      );
      expect((await store.parkedDrafts()).map((d) => d.number), [1, 2, 3]);
      expect(
        await store.desktopDraftExportNumber(draftId: drafts[2].id as String),
        5,
      );
      await database.execute('DROP TRIGGER reject_export');
      final raw = await (store as dynamic).exportDesktopDraft(
        draftId: drafts[2].id,
      );
      final draft = DesktopDraft.decode(
        raw,
        session: realSession,
        catalog: listings,
        committedEvents: await store.events(),
        exportBody: {},
      );
      expect(draft!.customerNumber, 5);
      expect((await store.parkedDrafts()).map((d) => d.number), [1, 2, 5]);
      expect(draft.positions.single.pendingEventId, originalId);
      expect(draft.positions.single.listing.listingId, 'listing-2');
      expect(await store.heldCart(), hasLength(3));
      expect(await store.cartLines(), isEmpty);
      await store.resumeDraft(drafts[2].id as String);
      expect((await store.checkout(250)).customerNumber, 5);
      expect((await store.events()).last.id, originalId);
    },
  );

  test(
    'existing version-five database migrates its held cart on open',
    () async {
      await store.addResolved(listings[0]);
      await store.setSetting('draftPaymentInput', '12,00');
      final raw = await databaseFactoryFfi.openDatabase('${dir.path}/cash.db');
      await raw.transaction((tx) async {
        final cart = await tx.query('cart');
        await tx.insert('settings', {
          'key': 'heldCart',
          'value': jsonEncode(cart),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await tx.insert('settings', {
          'key': 'heldPaymentInput',
          'value': jsonEncode('12,00'),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await tx.insert('settings', {
          'key': 'heldDraftCustomerNumber',
          'value': '9',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await tx.delete('cart');
        await tx.delete(
          'settings',
          where: 'key IN (?, ?, ?)',
          whereArgs: [
            'draftCustomerNumber',
            'draftPaymentInput',
            'nextDraftNumber',
          ],
        );
      });
      await store.close();
      store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/cash.db',
        requireExisting: true,
      );
      final drafts = await (store as dynamic).parkedDrafts() as List;
      expect(drafts.single.number, 9);
      expect(drafts.single.paymentInput, '12,00');
      await expectLater(store.addResolved(listings[0]), throwsStateError);
      await (store as dynamic).resumeDraft(drafts.single.id);
      expect((await store.checkout(250)).customerNumber, 9);
    },
  );

  test(
    'database failure rolls back receipt and events without losing any parked draft',
    () async {
      for (var i = 0; i < 3; i++) {
        await store.addResolved(listings[i]);
        await (store as dynamic).parkCart();
      }
      await store.addResolved(listings[3]);
      await store.addResolved(listings[4]);
      await store.setSetting('draftPaymentInput', '5,00');
      final original = await store.cartLines();
      final raw = await databaseFactoryFfi.openDatabase('${dir.path}/cash.db');
      await raw.execute(
        "CREATE TRIGGER simulate_disk_failure BEFORE INSERT ON events WHEN NEW.listingId = 'listing-4' BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
      );
      await expectLater(store.checkout(500), throwsA(isA<DatabaseException>()));
      expect(await store.receipts(), isEmpty);
      expect(await store.events(), isEmpty);
      expect(
        (await store.cartLines()).map((e) => e.pendingEventId),
        original.map((e) => e.pendingEventId),
      );
      expect(await store.setting('draftPaymentInput'), '5,00');
      expect(await (store as dynamic).parkedDrafts(), hasLength(3));
      await raw.execute('DROP TRIGGER simulate_disk_failure');
      expect((await store.checkout(500)).customerNumber, 4);
    },
  );

  test(
    'return in third parked draft blocks direct cancellation of its original',
    () async {
      await store.addResolved(listings[0]);
      await store.checkout(250);
      final sale = (await store.events()).single;
      for (var i = 1; i < 3; i++) {
        await store.addResolved(listings[i]);
        await store.parkCart();
      }
      await store.addReturn(listings[0].listingId);
      await store.parkCart();
      await expectLater(store.cancel(sale.id), throwsStateError);
      expect(await store.events(), hasLength(1));
      final refund = (await store.parkedDrafts()).last;
      await store.resumeDraft(refund.id);
      await store.checkout(0);
      expect((await store.events()).last.cancelOf, sale.id);
    },
  );

  test(
    'direct cancellation allocates beyond both active and parked numbers',
    () async {
      await store.addResolved(listings[0]);
      await store.checkout(250);
      final sale = (await store.events()).single;
      await store.addResolved(listings[1]);
      await store.parkCart();
      await store.addResolved(listings[2]);
      await store.cancel(sale.id);
      expect((await store.receipts()).first.customerNumber, 4);
      expect((await store.checkout(250)).customerNumber, 3);
      expect((await store.parkedDrafts()).single.number, 2);
      expect(await store.activeDraftNumber(), 5);
    },
  );
}
