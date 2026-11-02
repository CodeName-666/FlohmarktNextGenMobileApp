import '../domain/catalog_search.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'catalog_reports.dart';

/// Longest QR text that standard camera apps still read reliably at error
/// correction level M on a phone screen (KAN-594).
const receiptQrLimit = 1000;
const _titleLength = 24;

/// Plain-text receipt for the offline QR code: the same positions, total and
/// receipt number as the PDF, but no names, e-mail addresses or tokens.
///
/// When the text would exceed [limit], item lines are dropped from the end
/// and replaced by "… und n weitere Artikel"; header and totals always stay.
String receiptQrText(
  MarketSession session,
  Receipt receipt,
  List<SaleEvent> events, {
  int limit = receiptQrLimit,
}) {
  final header = [
    'MarketMate Beleg',
    session.name,
    if (session.isDemo) 'DEMO - Keine echten Verkäufe',
    'Kasse ${receipt.registerNumber} · Beleg ${receipt.number} · Kunde ${receipt.customerNumber}',
    localEventTime(receipt.occurredAt),
    '',
  ];
  final items = [
    for (final event in receiptPositions(receipt, events)) _line(event),
    for (final event in receiptHistory(
      receipt,
      events,
    ).where((e) => e.cancelOf != null && e.receiptId != receipt.id))
      'Später storniert: ${_title(event.listing.title)} '
          '${formatCents(-event.listing.priceCents)}',
  ];
  final footer = [
    '',
    'Summe: ${formatCents(receipt.totalCents)}',
    if (receipt.tenderedKnown) ...[
      'Gegeben: ${formatCents(receipt.tenderedCents)}',
      'Rückgeld: ${formatCents(receipt.changeCents)}',
    ] else
      'Bargeld bestätigt, Gegeben/Rückgeld nicht erfasst',
    'Vorgang: ${receipt.id}',
  ];

  String compose(List<String> lines) =>
      [...header, ...lines, ...footer].join('\n');
  if (compose(items).length <= limit) return compose(items);
  for (var kept = items.length - 1; kept >= 0; kept--) {
    final shortened = [
      ...items.take(kept),
      '… und ${items.length - kept} weitere Artikel',
    ];
    if (compose(shortened).length <= limit) return compose(shortened);
  }
  return compose(['… und ${items.length} weitere Artikel']);
}

String _line(SaleEvent event) {
  final cents = event.cancelOf == null
      ? event.listing.priceCents
      : -event.listing.priceCents;
  return '${event.cancelOf == null ? '' : 'Storno: '}'
      '${sellerIdentity(event.listing)} Nr ${event.listing.articleNumber} '
      '${_title(event.listing.title)} ${formatCents(cents)}';
}

String _title(String title) {
  final text = title.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= _titleLength
      ? text
      : '${text.substring(0, _titleLength - 1)}…';
}
