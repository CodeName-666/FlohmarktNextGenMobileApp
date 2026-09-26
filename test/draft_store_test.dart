import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/services/desktop_draft.dart';
import 'full_checkout_test.dart' show realSession, realListing;

Map<String, Object?> draftFixture() => {
  'version': 1,
  'kasse': 3,
  'export_sha256': DesktopDraft.exportFingerprint({}),
  'kunde': {
    'kunden_nummer': 7,
    'artikel_liste': [
      {
        'stammnummer': 7,
        'artikel_nummer': 5,
        'preis': '2.50',
        'beschreibung': 'Buch',
      },
      {
        'stammnummer': 7,
        'artikel_nummer': 5,
        'preis': '-2.50',
        'beschreibung': 'Buch',
      },
    ],
  },
  'verkaeufe': [
    {
      'stammnummer': 7,
      'artikel_nummer': 5,
      'preis': '2.50',
      'kassen_nummer': 3,
      'kunden_nummer': 7,
      'vorgangId': '00000000-0000-7000-8000-000000000001',
      'occurredAt': '2026-09-26T10:00:00Z',
      'articleId': realListing.articleId,
      'listingId': realListing.listingId,
      'articleNr': 5,
      'labelRevision': 1,
      'exportGeneration': 7,
      'eingabeWeg': 'manual',
      'storniert': false,
      'stornoVorgangId': null,
      'rohcode': null,
    },
  ],
};
void main() {
  setUpAll(sqfliteFfiInit);
  test(
    'pending return and parked payment stay separate and clear on commit',
    () async {
      final store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
        session: realSession,
        listings: [realListing],
      );
      await store.addResolved(realListing);
      await store.addReturn(realListing.listingId);
      expect(await store.events(), isEmpty);
      expect((await store.cartLines()).map((e) => e.signedCents), [250, -250]);
      await store.setSetting('draftPaymentInput', '10,00');
      await store.swapCustomer();
      expect(await store.setting('draftPaymentInput'), isNull);
      expect(await store.setting('heldPaymentInput'), '10,00');
      await store.swapCustomer();
      expect(await store.setting('draftPaymentInput'), '10,00');
      await store.checkout(0);
      expect(await store.setting('draftPaymentInput'), isNull);
      expect(await store.activeSales(), isEmpty);
      await store.close();
    },
  );
  test(
    'desktop sale-return pair survives reopen, remains draft, commits atomically',
    () async {
      final dir = await Directory.systemTemp.createTemp('draft_pair_');
      final path = '${dir.path}/cash.db';
      var store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: path,
        session: realSession,
        listings: [realListing],
      );
      final draft = DesktopDraft.decode(
        draftFixture(),
        session: realSession,
        catalog: [realListing],
        committedEvents: [],
        exportBody: {},
      )!;
      await store.importEventsAndDraft([], draft);
      expect(await store.events(), isEmpty);
      expect(await store.cartLines(), hasLength(2));
      final exported = await store.exportDesktopDraft();
      final roundTrip = DesktopDraft.decode(
        exported,
        session: realSession,
        catalog: [realListing],
        committedEvents: [],
        exportBody: {},
      );
      expect(roundTrip!.positions.map((p) => p.signedPriceCents), [250, -250]);
      expect(roundTrip.customerNumber, 7);
      await store.swapCustomer();
      expect(await store.exportDesktopDraft(), isNull);
      final parked = DesktopDraft.decode(
        await store.exportDesktopDraft(held: true),
        session: realSession,
        catalog: [realListing],
        committedEvents: [],
        exportBody: {},
      );
      expect(
        parked!.positions.first.pendingEventId,
        roundTrip.positions.first.pendingEventId,
      );
      await store.swapCustomer();
      final id = (await store.cartLines()).first.entryId;
      await expectLater(store.removeEntry(id), throwsStateError);
      await store.close();
      store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: path,
        requireExisting: true,
      );
      expect((await store.cartLines()).map((e) => e.signedCents).toList(), [
        250,
        -250,
      ]);
      final receipt = await store.checkout(0);
      expect(receipt.customerNumber, 7);
      expect(receipt.totalCents, 0);
      final events = await store.events();
      expect(events, hasLength(2));
      expect(events.last.cancelOf, events.first.id);
      expect(events.first.id, '00000000-0000-7000-8000-000000000001');
      expect(await store.activeSales(), isEmpty);
      await store.close();
      store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: path,
        requireExisting: true,
      );
      expect((await store.receipts()).single.totalCents, 0);
      await store.close();
      await dir.delete(recursive: true);
    },
  );
}
