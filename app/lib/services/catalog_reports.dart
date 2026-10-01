import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/catalog_search.dart';
import '../domain/models.dart';
import '../domain/money.dart';

String localEventTime(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return 'Zeitpunkt unbekannt';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}';
}

Map<String, String> marketDetailValues(MarketSession session) {
  final values = <String, String>{
    'Markt-ID': session.marketId,
    'Kasse': '${session.registerNumber}',
    'Herkunft': session.isDemo
        ? 'Demo'
        : session.exportGeneration == 0
        ? 'V1 · revisionslos'
        : 'V2',
    'Exportgeneration': '${session.exportGeneration}',
    if (session.exportChecksum.isNotEmpty)
      'Export-Prüfsumme': session.exportChecksum,
  };
  const labels = {
    'date': 'Datum',
    'startDate': 'Beginn',
    'endDate': 'Ende',
    'location': 'Ort',
    'exportedAt': 'Exportiert am',
    'freezeStatus': 'Freeze-Status',
    'status': 'Status',
    'sellerFeeFlat': 'Verkäuferpauschale (EUR)',
    'sellerFeePerStammnummer': 'Gebühr je Box (EUR)',
    'revenueSharePercent': 'Umsatzanteil (%)',
    'maxStammnummern': 'Maximale Boxen',
    'assignedStammnummern': 'Vergebene Boxen',
  };
  void add(Object? raw, String prefix) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      if (entry.value is Map ||
          entry.value is List ||
          entry.value == null ||
          ['id', 'name', 'exportGeneration'].contains(entry.key)) {
        continue;
      }
      values['$prefix${labels[entry.key] ?? entry.key}'] = '${entry.value}';
    }
  }

  add(session.metadata['market'], '');
  add(session.metadata['marketParameters'], '');
  add(session.metadata['fees'], 'Exportgebühren · ');
  for (final key in ['version', 'exportedAt', 'generatedAt', 'exportDate']) {
    if (session.metadata[key] != null) {
      values[labels[key] ?? key] = '${session.metadata[key]}';
    }
  }
  return values;
}

Future<Uint8List> buildReceiptPdf(
  MarketSession session,
  Receipt receipt,
  List<SaleEvent> events,
) async {
  final own = events.where((e) => e.receiptId == receipt.id).toList();
  // A later cancellation attached to the original receipt is history, not a
  // mutation of the originally printed purchase. Separate refund receipts do
  // contain their cancellation position and negative total.
  final ownIds = own.map((e) => e.id).toSet();
  final signedTotal = own.fold<int>(
    0,
    (sum, e) =>
        sum +
        (e.cancelOf == null ? e.listing.priceCents : -e.listing.priceCents),
  );
  final original = signedTotal == receipt.totalCents
      ? own
      : own.where((e) => !ownIds.contains(e.cancelOf)).toList();
  final history = receiptHistory(receipt, events);
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final document = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Header(level: 0, text: session.name),
        if (session.isDemo) pw.Text('DEMO - Keine echten Verkäufe'),
        pw.Text(
          'Kunde ${receipt.customerNumber} / Beleg ${receipt.number} / Kasse ${receipt.registerNumber}',
        ),
        pw.Text(localEventTime(receipt.occurredAt)),
        pw.Text('Vorgang: ${receipt.id}'),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Artikel', 'Verkäufer / Box', 'Betrag'],
          data: [
            for (final event in original)
              [
                event.listing.title,
                '${sellerIdentity(event.listing)} / ${event.listing.boxNumber}',
                formatCents(
                  event.cancelOf == null
                      ? event.listing.priceCents
                      : -event.listing.priceCents,
                ),
              ],
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text('Belegsumme: ${formatCents(receipt.totalCents)}'),
        if (receipt.tenderedKnown) ...[
          pw.Text('Gegeben: ${formatCents(receipt.tenderedCents)}'),
          pw.Text('Rückgeld / Auszahlung: ${formatCents(receipt.changeCents)}'),
        ] else
          pw.Text('Bargeld bestätigt · Gegeben und Rückgeld nicht erfasst'),
        if (history.any((e) => e.cancelOf != null)) ...[
          pw.Header(level: 1, text: 'Stornohistorie'),
          for (final event in history.where((e) => e.cancelOf != null))
            pw.Paragraph(
              text:
                  '${localEventTime(event.occurredAt)}: ${event.listing.title}, '
                  '${formatCents(-event.listing.priceCents)}\nOriginal: ${event.cancelOf}\nStorno: ${event.id}',
            ),
        ],
      ],
    ),
  );
  return document.save();
}

Future<Uint8List> buildMarketDetailsPdf(
  MarketSession session,
  List<ArticleListing> listings,
  List<SaleEvent> activeSales,
) async {
  final sold = activeSales.map((e) => e.listing.listingId).toSet();
  final values = marketDetailValues(session);
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final document = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Header(level: 0, text: session.name),
        if (session.isDemo) pw.Text('DEMO - Keine echten Verkäufe'),
        pw.Text(
          'Stand: ${localEventTime(DateTime.now().toUtc().toIso8601String())}',
        ),
        pw.Text(
          '${listings.length} Artikel, ${listings.where((a) => sold.contains(a.listingId)).length} verkauft',
        ),
        pw.Text(
          '${listings.map((a) => a.sellerKey).toSet().length} Verkäufer, ${listings.map((a) => a.boxNumber).toSet().length} Boxen',
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Angabe', 'Wert'],
          data: values.entries.map((e) => [e.key, e.value]).toList(),
        ),
      ],
    ),
  );
  return document.save();
}
