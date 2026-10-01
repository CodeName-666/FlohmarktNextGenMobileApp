import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flohmarkt_mobile/domain/models.dart';
import 'package:flohmarkt_mobile/services/desktop_draft.dart';

const session = MarketSession(
  marketId: '9',
  name: 'Test',
  registerNumber: 2,
  exportGeneration: 7,
);
const item = ArticleListing(
  listingId: 'L1',
  articleId: 'A1',
  codeFull: '',
  title: 'Buch',
  priceCents: 250,
  labelRevision: 4,
  exportGeneration: 7,
  boxNumber: 42,
  marketId: '9',
  legacyArticleNumber: 3,
);
const exportBody = <String, Object?>{
  'market': {'id': 9},
  'title': 'Märkte',
};
Map<String, Object?> fixture() => {
  'version': 1,
  'kasse': 2,
  'export_sha256': DesktopDraft.exportFingerprint(exportBody),
  'kunde': {
    'kunden_nummer': 3,
    'artikel_liste': <Map<String, Object?>>[
      {
        'stammnummer': 42,
        'artikel_nummer': 3,
        'preis': 2.5,
        'beschreibung': 'Buch',
        'verkaeufer_nummer': 7,
      },
    ],
  },
  'verkaeufe': [
    {
      'stammnummer': 42,
      'artikel_nummer': 3,
      'preis': 2.5,
      'kassen_nummer': 2,
      'kunden_nummer': 3,
      'vorgangId': 'pending',
      'occurredAt': '2026-09-26T10:00:00Z',
      'articleId': 'A1',
      'listingId': 'L1',
      'articleNr': 3,
      'labelRevision': 4,
      'exportGeneration': 7,
      'eingabeWeg': 'vollcode',
      'storniert': false,
      'stornoVorgangId': null,
      'rohcode': null,
    },
  ],
};
DesktopDraft? decode(Object? raw, {List<SaleEvent> events = const []}) =>
    DesktopDraft.decode(
      raw,
      session: session,
      catalog: [item],
      committedEvents: events,
      exportBody: exportBody,
    );
void main() {
  test(
    'fingerprint matches Python default separators Unicode and number spelling',
    () {
      expect(
        DesktopDraft.exportFingerprint({
          'z': 1e-7,
          'a': {'ü': 1.0, 'a': 1e20},
        }),
        'ca66feabca202ef84360f9af58a5c3fc9b185dcf0c01d0ca56a5da60d22e5fed',
      );
    },
  );
  test(
    'valid draft preserves customer till revision and pending identity without sale',
    () {
      final result = decode(fixture())!;
      expect(result.customerNumber, 3);
      expect(result.registerNumber, 2);
      expect(result.positions.single.listing.labelRevision, 4);
      expect(result.positions.single.pendingEventId, 'pending');
      expect(result.positions.single.signedPriceCents, 250);
      expect(decode(null), isNull);
    },
  );
  for (final damage in [
    'hash',
    'till',
    'customer',
    'revision',
    'missing_field',
    'duplicate',
    'price',
    'orphan',
    'unknown',
    'return',
  ]) {
    test('rejects corrupt draft $damage before mutation', () {
      final raw = fixture();
      final customer = raw['kunde'] as Map;
      final positions = customer['artikel_liste'] as List;
      final sales = raw['verkaeufe'] as List;
      switch (damage) {
        case 'hash':
          raw['export_sha256'] = 'bad';
        case 'till':
          raw['kasse'] = 1;
        case 'customer':
          customer['kunden_nummer'] = true;
        case 'revision':
          sales[0]['labelRevision'] = 3;
        case 'missing_field':
          (sales[0] as Map).remove('occurredAt');
        case 'duplicate':
          positions.add(Map<String, Object?>.from(positions[0] as Map));
        case 'price':
          positions[0]['preis'] = 2.51;
        case 'orphan':
          positions.clear();
        case 'unknown':
          positions[0]['artikel_nummer'] = 99;
        case 'return':
          positions[0]['preis'] = -2.5;
          sales.clear();
      }
      expect(() => decode(raw), throwsFormatException);
    });
  }
  test(
    'return references exact active original; in-draft return references pending sale',
    () {
      final raw = fixture();
      final positions = (raw['kunde'] as Map)['artikel_liste'] as List;
      positions.add(<String, Object?>{
        ...Map<String, Object?>.from(positions.first as Map),
        'preis': -2.5,
      });
      final result = decode(raw)!;
      expect(result.positions.last.pendingEventId, 'pending');
      expect(result.positions.last.originalEventId, isNull);
      positions.removeAt(0);
      (raw['verkaeufe'] as List).clear();
      final original = SaleEvent(
        id: 'original',
        receiptId: 'r',
        occurredAt: '2026-09-25T10:00:00Z',
        inputMethod: 'scan',
        cancelOf: null,
        registerNumber: 2,
        customerNumber: 1,
        listing: item,
      );
      expect(
        decode(raw, events: [original])!.positions.single.originalEventId,
        'original',
      );
    },
  );
  test('raw draft survives JSON roundtrip', () {
    expect(decode(jsonDecode(jsonEncode(fixture())))!.raw, fixture());
  });
}
