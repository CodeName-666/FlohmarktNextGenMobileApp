import 'package:flutter_test/flutter_test.dart';
import 'package:flohmarkt_mobile/domain/models.dart';
import 'package:flohmarkt_mobile/services/desktop_archive.dart';

const session = MarketSession(
  marketId: '9',
  name: 'Test',
  registerNumber: 1,
  exportGeneration: 7,
);
const listing = ArticleListing(
  listingId: 'L1',
  articleId: 'A1',
  codeFull: '',
  title: 'Jacke',
  priceCents: 1235,
  labelRevision: 4,
  exportGeneration: 7,
  boxNumber: 42,
  marketId: '9',
  legacyArticleNumber: 3,
);
SaleEvent event(
  String id, {
  int register = 1,
  int price = 1235,
  String? cancelOf,
}) => SaleEvent(
  id: id,
  receiptId: 'r1',
  occurredAt: '2026-09-26T10:00:00Z',
  inputMethod: 'scan',
  cancelOf: cancelOf,
  registerNumber: register,
  customerNumber: 1,
  listing: ArticleListing(
    listingId: 'L1',
    articleId: 'A1',
    codeFull: '',
    title: 'Jacke',
    priceCents: price,
    labelRevision: 4,
    exportGeneration: 7,
    boxNumber: 42,
    marketId: '9',
    legacyArticleNumber: 3,
  ),
);
DesktopArchive roundtrip(List<SaleEvent> events) => DesktopArchive.decode(
  DesktopArchive.encode(session: session, events: events, consolidated: true),
  session: session,
  catalog: [listing],
);
void main() {
  test(
    'historical absent catalog retains immutable listing snapshot and flags missing master data',
    () {
      final raw = DesktopArchive.encode(
        session: session,
        events: [event('historical')],
      );
      final archive = DesktopArchive.decode(raw, session: session, catalog: []);
      final snapshot = archive.events.single.listing;
      expect(snapshot.listingId, 'L1');
      expect(snapshot.articleId, 'A1');
      expect(snapshot.priceCents, 1235);
      expect(snapshot.labelRevision, 4);
      expect(snapshot.fields['historicalMissingCatalog'], true);
      expect(
        () => DesktopArchive.decode(
          raw.replaceFirst('"labelRevision":4', '"labelRevision":null'),
          session: session,
          catalog: [],
        ),
        throwsFormatException,
      );
    },
  );
  test('embedded draft is preserved separately from committed sales', () {
    final raw = DesktopArchive.encode(
      session: session,
      events: [],
      draftRaw: {'version': 1},
    );
    final archive = DesktopArchive.decode(
      raw,
      session: session,
      catalog: [listing],
    );
    expect(archive.events, isEmpty);
    expect(archive.draftRaw, {'version': 1});
  });
  test('rejects inconsistent archive till and numeric schema coercion', () {
    final raw = DesktopArchive.encode(
      session: session,
      events: [event('a', register: 2)],
    );
    expect(
      () => DesktopArchive.decode(raw, session: session, catalog: [listing]),
      throwsFormatException,
    );
    final valid = DesktopArchive.encode(session: session, events: [event('a')]);
    expect(
      () => DesktopArchive.decode(
        valid.replaceFirst('"version":4', '"version":4.0'),
        session: session,
        catalog: [listing],
      ),
      throwsFormatException,
    );
    expect(
      () => DesktopArchive.decode(
        valid.replaceFirst('"articleNr":3', '"articleNr":4'),
        session: session,
        catalog: [listing],
      ),
      throwsFormatException,
    );
  });
  test('old in-place cancellation becomes two stable immutable events', () {
    final raw = DesktopArchive.encode(
      session: session,
      events: [event('a')],
    ).replaceFirst('"storniert":false', '"storniert":true');
    final first = DesktopArchive.decode(
      raw,
      session: session,
      catalog: [listing],
    );
    final second = DesktopArchive.decode(
      raw,
      session: session,
      catalog: [listing],
    );
    expect(first.events.length, 2);
    expect(first.events.last.cancelOf, 'a');
    expect(first.events.last.id, second.events.last.id);
    expect(DesktopArchive.merge([first]).conflicts, isEmpty);
  });
  test(
    'desktop JSON roundtrip retains cents revision and immutable cancellation',
    () {
      final raw = DesktopArchive.encode(
        session: session,
        events: [
          event('a'),
          event('b', cancelOf: 'a'),
        ],
      );
      expect(raw, contains('"preis":12.35'));
      final archive = DesktopArchive.decode(
        raw,
        session: session,
        catalog: [listing],
      );
      expect(archive.events.length, 2);
      expect(archive.events.first.listing.priceCents, 1235);
      expect(archive.events.last.cancelOf, 'a');
    },
  );
  test('merge deduplicates identical UUID and reports divergent UUID', () {
    final merged = DesktopArchive.merge([
      roundtrip([event('a')]),
      roundtrip([event('a')]),
    ]);
    expect(merged.events.length, 1);
    expect(merged.conflicts, isEmpty);
    final divergent = DesktopArchive.merge([
      roundtrip([event('a')]),
      roundtrip([event('a', register: 2)]),
    ]);
    expect(divergent.conflicts.single.kind, 'event_identity');
  });
  test(
    'merge reports duplicate effective sales but cancellation resolves them',
    () {
      expect(
        DesktopArchive.merge([
          roundtrip([event('a'), event('b', register: 2)]),
        ]).conflicts.single.kind,
        'duplicate_sale',
      );
      expect(
        DesktopArchive.merge([
          roundtrip([
            event('a'),
            event('b', register: 2),
            event('c', cancelOf: 'a'),
          ]),
        ]).conflicts,
        isEmpty,
      );
    },
  );
  test('different market or generation is rejected before import', () {
    final raw = DesktopArchive.encode(session: session, events: [event('a')]);
    expect(
      () => DesktopArchive.decode(
        raw.replaceFirst('"exportGeneration":7', '"exportGeneration":8'),
        session: session,
        catalog: [listing],
      ),
      throwsFormatException,
    );
  });
}
