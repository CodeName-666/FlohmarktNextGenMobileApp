import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/accounting.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/reconciliation.dart';

class OperationsReports {
  static Future<pw.Document> _document() async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    return pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
        italic: font,
        boldItalic: font,
      ),
    );
  }

  static String _amount(int cents) =>
      formatCents(cents).replaceAll(' €', ' EUR');
  static pw.Widget _header(MarketSession session, String title) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      pw.Text('${session.name}${session.isDemo ? ' - DEMO' : ''}'),
      pw.Text(
        'Markt ${session.marketId} | ${DateTime.now().toUtc().toIso8601String()} UTC',
        style: const pw.TextStyle(fontSize: 9),
      ),
      pw.Divider(),
      pw.SizedBox(height: 8),
    ],
  );
  static pw.Widget _table(List<String> headers, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellPadding: const pw.EdgeInsets.all(4),
      );
  static void _page(
    pw.Document doc,
    MarketSession session,
    String title,
    List<pw.Widget> content,
  ) => doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(42),
      header: (_) => _header(session, title),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Seite ${context.pageNumber}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (_) => content,
    ),
  );
  static String missingWarning(List<SaleEvent> events) => events.isEmpty
      ? ''
      : 'Stammdaten fehlen: ${events.length} verkaufte Artikel, Umsatz ${_amount(events.fold(0, (sum, e) => sum + e.listing.priceCents))}. Verkäufe sind in Umsatz und Auszahlung enthalten. Angebotswerte und Quoten beziehen sich auf bekannte Artikel.';
  static List<List<String>> _auditRows(List<SaleEvent> events) => events
      .map(
        (e) => [
          '${e.listing.boxNumber}',
          '${e.listing.articleNumber}',
          '${e.registerNumber}',
          '${e.customerNumber}',
          _amount(e.listing.priceCents),
          e.id,
          e.occurredAt,
          'Stammdaten fehlen',
        ],
      )
      .toList();
  static const _auditHeaders = [
    'Box',
    'Artikel',
    'Kasse',
    'Kunde',
    'Umsatz',
    'Ereignis-ID',
    'UTC',
    'Hinweis',
  ];
  static Future<Uint8List> settlementPdf(
    MarketSession session,
    List<SellerSettlement> settlements,
  ) async {
    if (settlements.isEmpty) {
      throw StateError('Keine Abrechnungsdaten vorhanden.');
    }
    final doc = await _document();
    for (final seller in settlements) {
      _page(doc, session, 'Abrechnung ${seller.sellerKey}', [
        pw.Text('Stamm-/Boxnummern: ${seller.boxNumbers.join(', ')}'),
        pw.SizedBox(height: 8),
        _table(
          [
            'Box',
            'Angeboten',
            'Verkauft',
            'Rest',
            'Offen',
            'Umsatz',
            'Gebühr',
            'Auszahlung',
          ],
          seller.boxSettlements
              .map(
                (b) => [
                  '${b.boxNumber}',
                  '${b.offeredCount}',
                  '${b.soldCount}',
                  '${b.unsoldCount}',
                  '${b.openCount}',
                  _amount(b.revenueCents),
                  _amount(b.feeCents),
                  _amount(b.payoutCents),
                ],
              )
              .toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Text('Angebotswert: ${_amount(seller.offeredCents)}'),
        pw.Text(
          'Umsatz: ${_amount(seller.revenueCents)} | Umsatzanteil: ${_amount(seller.feeCents)}',
        ),
        pw.Text(
          'Auszahlungsbetrag: ${_amount(seller.payoutCents)}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        _table(
          ['Box/Artikel', 'Beschreibung', 'Status', 'Preis'],
          [
            for (final a in seller.sold)
              [
                '${a.boxNumber}/${a.articleNumber}',
                a.title,
                'Verkauft',
                _amount(a.priceCents),
              ],
            for (final a in seller.unsold)
              [
                '${a.boxNumber}/${a.articleNumber}',
                a.title,
                'Nicht verkauft',
                _amount(a.priceCents),
              ],
          ],
        ),
        if (seller.missingCatalog.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(missingWarning(seller.missingCatalog)),
          _table(_auditHeaders, _auditRows(seller.missingCatalog)),
        ],
      ]);
    }
    return doc.save();
  }

  static List<List<String>> statisticsRows(MarketStatistics s) => [
    ['Artikel angeboten', '${s.offeredCount}'],
    ['Verkauft', '${s.soldCount}'],
    ['Nicht verkauft', '${s.unsoldCount}'],
    ['Verkaufsquote', '${s.soldPercent.toStringAsFixed(2)} %'],
    ['Angebotswert', _amount(s.offeredCents)],
    ['Umsatz', _amount(s.revenueCents)],
    ['Wert-Verkaufsquote', '${s.soldValuePercent.toStringAsFixed(2)} %'],
    ['Kunden', '${s.customerCount}'],
    ['Verkäufer', '${s.sellerCount}'],
    ['Umsatz je Kunde', _amount(s.averageRevenueCents)],
    ['Artikel je Kunde', s.averageItemsPerCustomer.toStringAsFixed(2)],
    ['Durchschnitt Angebot', _amount(s.averageOfferedPriceCents)],
    ['Durchschnitt Verkauf', _amount(s.averageSoldPriceCents)],
    ['Bearbeitungsgebühr', _amount(s.processingFeeCents)],
    ['Umsatzanteil', _amount(s.feeCents)],
    ['Gesamterlös', _amount(s.organizerProceedsCents)],
    ['Auszahlung', _amount(s.payoutCents)],
  ];
  static Future<Uint8List> statisticsPdf(
    MarketSession session,
    MarketStatistics stats, {
    int? registerNumber,
  }) async {
    final doc = await _document();
    _page(doc, session, 'Verkaufsstatistik', [
      pw.Text(statisticsScope(registerNumber)),
      _table(['Kennzahl', 'Wert'], statisticsRows(stats)),
      if (stats.missingCatalog.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Text(missingWarning(stats.missingCatalog)),
        _table(_auditHeaders, _auditRows(stats.missingCatalog)),
      ],
    ]);
    return doc.save();
  }

  static String statisticsScope(int? registerNumber) =>
      '${registerNumber == null ? 'Gesamter geladener Markt' : 'Kasse $registerNumber'} · Nur lokal erfasste oder importierte Verkäufe. Angebotswerte: gesamter Katalog.';
  static String statisticsText(
    MarketSession session,
    MarketStatistics stats, {
    int? registerNumber,
  }) =>
      '${session.name}\nVerkaufsstatistik\n${statisticsScope(registerNumber)}\n${statisticsRows(stats).map((r) => r.join(': ')).join('\n')}\n${missingWarning(stats.missingCatalog)}';
  static String settlementsText(
    MarketSession session,
    List<SellerSettlement> sellers,
  ) =>
      '${session.name}\nAbrechnungen\n${sellers.map((s) => '${s.sellerKey} | Boxen ${s.boxNumbers.join(', ')} | Umsatz ${_amount(s.revenueCents)} | Gebühren ${_amount(s.feeCents)} | Auszahlung ${_amount(s.payoutCents)}\n${missingWarning(s.missingCatalog)}').join('\n')}';
  static String unsoldText(MarketSession session, AccountingService service) =>
      '${session.name}\nNicht verkaufte Artikel\n${service.settlements().map((s) => 'Verkäufer ${s.sellerKey}\n${s.unsold.map((a) => '${a.boxNumber}/${a.articleNumber} ${a.title} ${a.size} ${_amount(a.priceCents)}').join('\n')}').join('\n')}';
  static String unsoldJson(MarketSession session, AccountingService service) =>
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'markt': session.name,
        'marketId': session.marketId,
        'erzeugt_am': DateTime.now().toUtc().toIso8601String(),
        'anzahl_nicht_verkauft': service.settlements().fold(
          0,
          (sum, s) => sum + s.unsold.length,
        ),
        'verkaeufer': [
          for (final s in service.settlements())
            {
              'verkaeuferkennung': s.sellerKey,
              'verkaeufer_nummer': s.offered.isNotEmpty
                  ? s.offered.first.sellerNumber
                  : s.sold.first.sellerNumber,
              'artikel': [
                for (final a in s.unsold)
                  {
                    'artikel_nummer': a.articleNumber,
                    'stammnummer': a.boxNumber,
                    'beschreibung': a.title,
                    'groesse': a.size,
                    'preisCents': a.priceCents,
                  },
              ],
            },
        ],
      });
  static Future<Uint8List> unsoldPdf(
    MarketSession session,
    AccountingService service, {
    int numberSlots = 25,
  }) async {
    if (numberSlots < 1 || numberSlots > 28) {
      throw ArgumentError('Nummern pro Seite: 1–28.');
    }
    final sellers = service
        .settlements()
        .where((s) => s.offered.isNotEmpty)
        .toList();
    if (sellers.isEmpty) throw StateError('Keine angebotenen Artikel geladen.');
    final blocks = <String, List<SellerSettlement>>{};
    for (final seller in sellers) {
      final article = seller.offered.first;
      final region = article.codeFull.length == 15
          ? article.codeFull.substring(0, 7)
          : 'legacy';
      final block = (article.sellerNumber - 1) ~/ numberSlots;
      blocks
          .putIfAbsent('$region:${block.toString().padLeft(5, '0')}', () => [])
          .add(seller);
    }
    final doc = await _document();
    final blockKeys = blocks.keys.toList()..sort();
    for (final key in blockKeys) {
      final columns = <({String title, List<String> articles})>[];
      for (final seller in blocks[key]!) {
        final articles = seller.unsold.toList()
          ..sort((a, b) => a.articleNumber.compareTo(b.articleNumber));
        if (articles.isEmpty) {
          columns.add((title: seller.sellerKey, articles: []));
        }
        for (var offset = 0; offset < articles.length; offset += 24) {
          final chunk = articles.skip(offset).take(24);
          columns.add((
            title: seller.sellerKey,
            articles: chunk
                .map((a) => '${a.boxNumber}/${a.articleNumber}')
                .toList(),
          ));
        }
      }
      for (var offset = 0; offset < columns.length; offset += 28) {
        final pageColumns = columns.skip(offset).take(28).toList();
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(32),
            build: (_) => pw.Column(
              children: [
                _header(
                  session,
                  'Rücksortierung - Nummern ${(int.parse(key.split(':').last) * numberSlots) + 1}–${(int.parse(key.split(':').last) + 1) * numberSlots}',
                ),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (final col in pageColumns)
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(left: pw.BorderSide(width: 0.3)),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                col.title,
                                style: const pw.TextStyle(fontSize: 7),
                              ),
                              pw.Divider(),
                              for (final a in col.articles)
                                pw.Padding(
                                  padding: const pw.EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: pw.Text(
                                    a,
                                    style: const pw.TextStyle(fontSize: 8),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    }
    return doc.save();
  }

  static String _csv(List<List<Object?>> rows) =>
      '\ufeff${rows.map((row) => row.map((value) {
        var text = value?.toString() ?? '';
        // Spreadsheet formula injection protection for externally supplied text.
        if (RegExp(r'^[=+@-]').hasMatch(text)) text = "'$text";
        return text.contains(RegExp('[;"\r\n]')) ? '"${text.replaceAll('"', '""')}"' : text;
      }).join(';')).join('\r\n')}\r\n';
  static String auditCsv(List<SaleEvent> events) =>
      _csv([_auditHeaders, ..._auditRows(events)]);
  static String reconciliationCsv(
    MarketSession session,
    ReconciliationReport report,
  ) {
    final rows = <List<Object?>>[
      [session.name, 'Rücksortierung'],
      [],
      ['Zusammenfassung'],
      ['Erwartet', report.expected.length],
      ['Gefunden', report.matched.length],
      ['Fehlend', report.missing.length],
      ['Unerwartet', report.unexpected.length + report.unknownCodes.length],
      [
        'Doppelscans',
        report.duplicates.length +
            report.unknownCodes.values.where((n) => n > 1).length,
      ],
      ['Ungültige Codes', report.invalidCodes.length],
      ['Scans gesamt', report.scannedTotal],
    ];
    for (final group in [
      ('Fehlende Artikel', report.missing),
      ('Unerwartete Artikel', report.unexpected),
      ('Doppelte Artikel', report.duplicates),
    ]) {
      if (group.$2.isEmpty) continue;
      rows.addAll([
        [],
        [group.$1],
        [
          'Verkäuferkennung',
          'Box',
          'Artikel',
          'Beschreibung',
          'Größe',
          'Preis',
        ],
      ]);
      rows.addAll(
        group.$2.map(
          (a) => [
            a.sellerKey,
            a.boxNumber,
            a.articleNumber,
            a.title,
            a.size,
            _amount(a.priceCents),
          ],
        ),
      );
    }
    if (report.unknownCodes.isNotEmpty) {
      rows.addAll([
        [],
        ['Unbekannte gültige Etiketten'],
        ['Etikett', 'Scans'],
        ...report.unknownCodes.entries.map((e) => [e.key, e.value]),
      ]);
    }
    if (report.invalidCodes.isNotEmpty) {
      rows.addAll([
        [],
        ['Ungültige Barcodes'],
        ...report.invalidCodes.map((s) => [s]),
      ]);
    }
    return _csv(rows);
  }
}
