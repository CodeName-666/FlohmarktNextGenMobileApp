class LabelCode {
  final String codeFull;
  final int revision;
  const LabelCode._(this.codeFull, this.revision);
  static LabelCode parse(String raw) {
    final match = RegExp(
      r'^MM1\|([0-9]{15})\|([1-9][0-9]*)\|([0-9A-F]{8})$',
    ).firstMatch(raw.trim());
    if (match == null) {
      throw const FormatException(
        'Etikett mit Revision scannen oder manuell erfassen.',
      );
    }
    final body = '${match[1]}|${match[2]}';
    if (_crc32(body) != match[3]) {
      throw const FormatException(
        'Prüfsumme stimmt nicht. Bitte erneut scannen.',
      );
    }
    final revision = int.tryParse(match[2]!);
    if (revision == null) {
      throw const FormatException('Ungültige Etikettenrevision.');
    }
    return manual(match[1]!, revision);
  }

  static LabelCode manual(String raw, int revision) {
    var code = raw.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^[0-9]{14,15}$').hasMatch(code) || revision < 1) {
      throw const FormatException(
        'Vollcode (14/15 Ziffern) und positive Revision eingeben.',
      );
    }
    var sum = 0;
    final digits = code.substring(0, 14).split('').reversed.toList();
    for (var i = 0; i < digits.length; i++) {
      var value = int.parse(digits[i]);
      if (i.isEven) {
        value *= 2;
        if (value > 9) value -= 9;
      }
      sum += value;
    }
    final check = (10 - sum % 10) % 10;
    if (code.length == 14) code += '$check';
    if (int.parse(code[14]) != check) {
      throw const FormatException('Artikel-Prüfziffer stimmt nicht.');
    }
    return LabelCode._(code, revision);
  }

  int get sellerNumber => int.parse(codeFull.substring(7, 10));
  int get articleNumber => int.parse(codeFull.substring(10, 14));

  static String _crc32(String value) {
    var crc = 0xffffffff;
    for (final byte in value.codeUnits) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    return ((crc ^ 0xffffffff) & 0xffffffff)
        .toRadixString(16)
        .padLeft(8, '0')
        .toUpperCase();
  }
}
