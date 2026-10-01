import 'package:flutter_test/flutter_test.dart';
import 'package:flohmarkt_mobile/domain/barcode.dart';
import 'package:flohmarkt_mobile/domain/money.dart';

void main() {
  const code = '092700104200054';
  // Independent fixture generated with desktop Python zlib.crc32.
  const payload = 'MM1|092700104200054|1|6BCD8E44';

  test('MM1 matches desktop CRC32 and preserves seller/article identity', () {
    final label = LabelCode.parse(payload);
    expect(label.codeFull, code);
    expect(label.revision, 1);
    expect(label.sellerNumber, 42);
    expect(label.articleNumber, 5);
  });

  test('rejects corrupted CRC, revisionless and malformed labels', () {
    for (final value in [
      code,
      '42-5',
      '$payload\nX',
      'MM1|092700104200054|2|6BCD8E44',
      'MM1|092700104200054|0|00000000',
    ]) {
      expect(() => LabelCode.parse(value), throwsFormatException);
    }
  });

  test('manual full code normalizes printed groups and validates Luhn', () {
    expect(LabelCode.manual('09-27-001-042-0005', 1).codeFull, code);
    expect(() => LabelCode.manual('092700104200055', 1), throwsFormatException);
    expect(() => LabelCode.manual(code, 0), throwsFormatException);
  });

  test('money is exact cents with German and decimal point input', () {
    expect(parseCents('12,50'), 1250);
    expect(parseCents('0.10'), 10);
    expect(parseCents('20'), 2000);
    expect(formatCents(1250), '12,50 €');
    for (final value in ['-1', '1,001', 'NaN', '1e3', '', '1.000,00']) {
      expect(() => parseCents(value), throwsFormatException);
    }
  });
}
