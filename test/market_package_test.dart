import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flohmarkt_mobile/data/market_package.dart';

void main() {
  test('legacy preserves box, exact cents and source identity', () {
    final raw = jsonEncode([
      {
        'type': 'table',
        'name': 'stnr17',
        'data': [
          {
            'artikelnummer': '3',
            'beschreibung': 'Jacke',
            'groesse': 'M',
            'preis': '12,35',
          },
        ],
      },
    ]);
    final package = MarketPackage.fromLegacy(raw, name: 'Testmarkt');
    expect(package.listings.single.priceCents, 1235);
    expect(package.listings.single.boxNumber, 17);
    expect(package.session.exportGeneration, 0);
    expect(package.isLegacy, isTrue);
    expect(
      MarketPackage.fromLegacy(raw, name: 'Anderer Name').session.marketId,
      package.session.marketId,
    );
  });
  test('populated invalid legacy rows reject entire import', () {
    expect(
      () => MarketPackage.fromLegacy(
        jsonEncode([
          {
            'type': 'table',
            'name': 'stnr17',
            'data': [
              {'artikelnummer': '3', 'beschreibung': 'Jacke', 'preis': 'NaN'},
            ],
          },
        ]),
        name: 'Test',
      ),
      throwsFormatException,
    );
  });
  test('checksum uses Python canonical numbers and recursive key order', () {
    expect(
      pythonCanonicalJson({
        'z': 1e-7,
        'a': {'ü': 1.0, 'a': 1e20},
      }),
      '{"a":{"a":1e+20,"ü":1.0},"z":1e-07}',
    );
  });
  test('bad checksum cannot load market', () {
    expect(
      () => MarketPackage.parse('{"version":"2.0","checksum":"bad"}'),
      throwsFormatException,
    );
  });
  test(
    'V2 binds mapped box and accepted revision to integer price snapshot',
    () {
      final body = <String, Object?>{
        'version': '2.0',
        'market': {'id': 9, 'name': 'Testmarkt', 'exportGeneration': 7},
        'articles': [
          {
            'articleId': 'a1',
            'articleNr': 3,
            'codeFull': '092700101700035',
            'fields': {'description': 'Jacke', 'price': 999},
          },
        ],
        'stammnummernMapping': [
          {
            'stammnummer': 42,
            'articleIds': ['a1'],
          },
        ],
        'listings': [
          {
            'listingId': 'L1',
            'articleId': 'a1',
            'marketId': 9,
            'priceSnapshotCents': 1235,
            'acceptedLabelRevision': 4,
          },
        ],
      };
      // Use legacy generation to obtain a known valid Luhn code independently
      // of the V2 mapping, whose market box deliberately differs from seller 17.
      final legacy = MarketPackage.fromLegacy(
        jsonEncode([
          {
            'type': 'table',
            'name': 'stnr17',
            'data': [
              {'artikelnummer': '3', 'beschreibung': 'Jacke', 'preis': '12.35'},
            ],
          },
        ]),
        name: 'Legacy',
      );
      ((body['articles'] as List).single as Map)['codeFull'] =
          legacy.listings.single.codeFull;
      body['checksum'] =
          'sha256:${sha256.convert(utf8.encode(pythonCanonicalJson(body)))}';
      final package = MarketPackage.parse(jsonEncode(body));
      expect(package.listings.single.boxNumber, 42);
      expect(package.listings.single.sellerNumber, 17);
      expect(package.listings.single.priceCents, 1235);
      expect(package.listings.single.labelRevision, 4);
      ((body['articles'] as List).single as Map)['articleNr'] = 99;
      expect(
        () => MarketPackage.parse(jsonEncode(body), verifyChecksum: false),
        throwsFormatException,
      );
      ((body['articles'] as List).single as Map)['articleNr'] = 3;
      (body['articles'] as List).add({
        'articleId': 'unmapped',
        'articleNr': 4,
        'codeFull': legacy.listings.single.codeFull,
        'fields': {},
      });
      expect(
        () => MarketPackage.parse(jsonEncode(body), verifyChecksum: false),
        throwsFormatException,
      );
      (body['articles'] as List).removeLast();
      ((body['listings'] as List).single as Map).remove('priceSnapshotCents');
      expect(
        () => MarketPackage.parse(jsonEncode(body), verifyChecksum: false),
        throwsFormatException,
      );
    },
  );
}
