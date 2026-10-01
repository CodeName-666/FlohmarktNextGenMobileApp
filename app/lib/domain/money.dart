int parseCents(String input) {
  final match = RegExp(
    r'^([0-9]{1,7})(?:[,.]([0-9]{1,2}))?$',
  ).firstMatch(input.trim());
  if (match == null) {
    throw const FormatException(
      'Betrag mit höchstens zwei Nachkommastellen eingeben.',
    );
  }
  return int.parse(match[1]!) * 100 +
      int.parse((match[2] ?? '').padRight(2, '0'));
}

String formatCents(int cents) =>
    '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100},${(cents.abs() % 100).toString().padLeft(2, '0')} €';
