import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flohmarkt_mobile/data/legacy_inspection.dart';

Map<String, Object?> article(Object number, String title, String price) => {
  'artikelnummer': number,
  'beschreibung': title,
  'preis': price,
};
Map<String, Object?> table(String name, Object data) => {
  'type': 'table',
  'name': name,
  'data': data,
};

void main() {
  test('valid preview binds source, counts empty rows and box assignments', () {
    final raw = jsonEncode([
      table('verkaeufer', [
        {'id': 1},
        {'id': 2},
      ]),
      table('stnr17', [
        article(3, 'Jacke', '12,35'),
        {'artikelnummer': 8},
      ]),
      table('stnr42', [article(4, 'Buch', '2.00')]),
    ]);
    final result = LegacyInspection.inspect(raw, name: 'Testmarkt');
    expect(result.issues, isEmpty);
    expect(result.package!.listings, hasLength(2));
    expect(result.validRows, 2);
    expect(result.ignoredRows, 1);
    expect(result.boxCount, 2);
    expect(result.sellerCount, 2);
    expect(result.report['articleAssignmentsByBox'], {'17': 1, '42': 1});
    expect(result.sourceSha256, sha256.convert(utf8.encode(raw)).toString());
    expect(result.package!.sourceSha256, result.sourceSha256);
    expect(jsonDecode(jsonEncode(result.report))['importable'], isTrue);
  });
  test(
    'all populated row failures and cross-table duplicates are reported',
    () {
      final raw = jsonEncode([
        table('stnr17', [
          article(3, 'Gut', '1'),
          article(4, '', '-2'),
          article('falsch', 'Fehler', 'NaN'),
          4,
        ]),
        table('stnr017', [article(3, 'Doppelt', '2')]),
        table('stnr1000', []),
      ]);
      final result = LegacyInspection.inspect(raw, name: 'Test');
      expect(result.package, isNull);
      expect(result.validRows, 1);
      expect(result.issues, hasLength(7));
      expect(result.issues.join('\n'), contains('Zeile 2'));
      expect(result.issues.join('\n'), contains('doppelte Artikelnummer'));
      expect(result.report['importable'], false);
      expect(() => jsonEncode(result.report), returnsNormally);
    },
  );
  test(
    'malformed, wrong-shaped and empty sources produce exportable reports',
    () {
      for (final raw in ['{', '{}', '[]', 'null']) {
        final result = LegacyInspection.inspect(raw, name: 'Test');
        expect(result.package, isNull);
        expect(result.issues, isNotEmpty);
        expect(result.report['importable'], false);
        expect(() => jsonEncode(result.report), returnsNormally);
      }
    },
  );
  test('empty name and invalid register prevent otherwise valid import', () {
    final raw = jsonEncode([
      table('stnr1', [article(1, 'Test', '1.00')]),
    ]);
    final result = LegacyInspection.inspect(raw, name: ' ', registerNumber: 0);
    expect(result.package, isNull);
    expect(result.validRows, 1);
    expect(result.issues, hasLength(2));
  });
}
