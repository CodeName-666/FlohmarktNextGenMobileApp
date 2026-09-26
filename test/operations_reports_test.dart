import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flohmarkt_mobile/services/operations_reports.dart';
import 'package:flohmarkt_mobile/domain/accounting.dart';
import 'package:flohmarkt_mobile/domain/models.dart';
import 'package:flohmarkt_mobile/domain/reconciliation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const session = MarketSession(
    marketId: 'm',
    name: 'Demomarkt',
    registerNumber: 1,
    exportGeneration: 1,
  );
  const article = ArticleListing(
    listingId: 'a',
    articleId: 'a',
    codeFull: '092700104200054',
    title: 'Text; mit "Zitat"',
    priceCents: 100,
    labelRevision: 1,
    exportGeneration: 1,
    boxNumber: 5,
    marketId: 'm',
  );
  test('statistics exports retain register scope of their figures', () async {
    final service = AccountingService(
      listings: [article],
      events: [],
      fees: const FeePolicy(),
    );
    final stats = service.statistics(registerNumber: 7);
    expect(
      OperationsReports.statisticsText(session, stats, registerNumber: 7),
      contains('Kasse 7'),
    );
    expect(
      OperationsReports.statisticsScope(null),
      contains('Gesamter geladener Markt'),
    );
    final bytes = await OperationsReports.statisticsPdf(
      session,
      stats,
      registerNumber: 7,
    );
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
  });
  test('sorting PDF handles overflow lists offline', () async {
    final listings = [
      for (var i = 0; i < 80; i++)
        ArticleListing(
          listingId: 'a$i',
          articleId: 'a$i',
          codeFull: article.codeFull,
          title: 'Artikel $i',
          priceCents: 100,
          labelRevision: 1,
          exportGeneration: 1,
          boxNumber: 5,
          marketId: 'm',
        ),
    ];
    final service = AccountingService(
      listings: listings,
      events: [],
      fees: const FeePolicy(),
    );
    final bytes = await OperationsReports.unsoldPdf(
      session,
      service,
      numberSlots: 1,
    );
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
  });
  test('reconciliation CSV quotes cells and preserves Unicode BOM', () {
    final report = ReconciliationSession(
      listings: [article],
      events: [],
    ).report;
    final csv = OperationsReports.reconciliationCsv(session, report);
    expect(csv.startsWith('\ufeff'), true);
    expect(csv, contains('"Text; mit ""Zitat"""'));
    expect(csv, contains('Fehlend;1'));
  });
  test('unsold JSON retains sold-out sellers and regional identity', () {
    final event = SaleEvent(
      id: 'v',
      receiptId: 'r',
      occurredAt: '2026-09-26T12:00:00Z',
      inputMethod: 'manual',
      cancelOf: null,
      registerNumber: 1,
      listing: article,
    );
    final service = AccountingService(
      listings: [article],
      events: [event],
      fees: const FeePolicy(),
    );
    final data =
        jsonDecode(OperationsReports.unsoldJson(session, service)) as Map;
    expect(data['anzahl_nicht_verkauft'], 0);
    expect((data['verkaeufer'] as List).single['artikel'], isEmpty);
    expect(
      (data['verkaeufer'] as List).single['verkaeuferkennung'],
      article.sellerKey,
    );
  });
  test('seller PDF is generated and contains PDF bytes', () async {
    final service = AccountingService(
      listings: [article],
      events: [],
      fees: const FeePolicy(),
    );
    final bytes = await OperationsReports.settlementPdf(
      session,
      service.settlements(),
    );
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
  });
}
