import 'package:flutter_test/flutter_test.dart';
import 'package:flohmarkt_mobile/domain/accounting.dart';
import 'package:flohmarkt_mobile/domain/reconciliation.dart';
import 'package:flohmarkt_mobile/domain/models.dart';

ArticleListing item(
  String id,
  int box,
  int price, {
  String code = '092700104200054',
}) => ArticleListing(
  listingId: id,
  articleId: id,
  codeFull: code,
  title: id,
  priceCents: price,
  labelRevision: 1,
  exportGeneration: 1,
  boxNumber: box,
  marketId: 'm',
);
SaleEvent sale(
  String id,
  ArticleListing a, {
  String? cancelOf,
  int register = 1,
}) => SaleEvent(
  id: id,
  receiptId: 'receipt-$register',
  occurredAt: '2026-09-26T12:00:00Z',
  inputMethod: 'manual',
  cancelOf: cancelOf,
  registerNumber: register,
  customerNumber: 1,
  listing: a,
);

void main() {
  test(
    'unknown valid labels remain unexpected without invented catalog entries',
    () {
      final session = ReconciliationSession(listings: [], events: []);
      expect(
        session.scanUnknown('MM1|unknown').status,
        ReconciliationStatus.unexpected,
      );
      expect(
        session.scanUnknown('MM1|unknown').status,
        ReconciliationStatus.duplicate,
      );
      expect(session.report.unknownCodes, {'MM1|unknown': 2});
      expect(session.report.scannedTotal, 2);
      expect(session.report.invalidCodes, isEmpty);
      expect(session.persistedStates, isEmpty);
    },
  );
  test('statistics adds individually rounded seller fees', () {
    final a = item('a', 1, 5), b = item('b', 2, 5, code: '092800104200054');
    final service = AccountingService(
      listings: [a, b],
      events: [sale('a', a), sale('b', b)],
      fees: const FeePolicy(revenueShareBasisPoints: 1000),
    );
    expect(service.statistics().feeCents, 0);
    expect(service.statistics().payoutCents, 10);
  });
  test('returned article drops obsolete unexpected saved state', () {
    final a = item('a', 1, 500);
    final session = ReconciliationSession(
      listings: [a],
      events: [],
      saved: {
        'a': const ReconciliationState(ReconciliationStatus.unexpected, 1),
      },
    );
    expect(session.report.unexpected, isEmpty);
    expect(session.report.missing.single.listingId, 'a');
    expect(session.report.scannedTotal, 0);
    expect(session.persistedStates['a']!.status, ReconciliationStatus.open);
    expect(session.scan(a).status, ReconciliationStatus.matched);
  });
  test('staged reconciliation does not mutate original before persistence', () {
    final a = item('a', 1, 500);
    final original = ReconciliationSession(listings: [a], events: []);
    final staged = original.copy()..scan(a);
    expect(staged.report.matched, hasLength(1));
    expect(original.report.matched, isEmpty);
    expect(original.persistedStates, isEmpty);
  });
  test('desktop three-cent fixture and explicit half-even boundary', () {
    final a = item('a', 5, 3), b = item('b', 6, 3);
    final service = AccountingService(
      listings: [a, b],
      events: [sale('a', a), sale('b', b)],
      fees: const FeePolicy(revenueShareBasisPoints: 1500),
    );
    expect(service.settlements().single.feeCents, 1);
    expect(service.settlements().single.payoutCents, 5);
    expect(roundHalfEven(30 * 1500, 10000), 4);
  });
  test(
    'half-even cents and cumulative box allocations preserve seller total',
    () {
      final a = item('a', 1, 5), b = item('b', 2, 10);
      final service = AccountingService(
        listings: [a, b],
        events: [sale('a', a), sale('b', b)],
        fees: const FeePolicy(
          revenueShareBasisPoints: 1000,
          feePerBoxCents: 200,
        ),
      );
      final settlement = service.settlements().single;
      expect(settlement.feeCents, 2);
      expect(settlement.payoutCents, 13);
      expect(settlement.boxSettlements.map((b) => b.feeCents), [0, 2]);
      expect(service.statistics().processingFeeCents, 400);
      expect(service.statistics().payoutCents, 13);
      expect(roundHalfEven(5, 10), 0);
      expect(roundHalfEven(15, 10), 2);
    },
  );
  test('missing catalog sales retain revenue; reversal removes original', () {
    final a = item('a', 1, 500), missing = item('missing', 1, 700);
    final service = AccountingService(
      listings: [a],
      events: [
        sale('a', a),
        sale('missing', missing),
        sale('reverse', a, cancelOf: 'a'),
      ],
      fees: const FeePolicy(),
    );
    final stats = service.statistics();
    expect(stats.revenueCents, 700);
    expect(stats.soldCount, 1);
    expect(stats.unsoldCount, 1);
    expect(stats.soldPercent, 0);
    expect(stats.missingCatalog.single.id, 'missing');
  });
  test('seller regions and register/customer composite remain distinct', () {
    final a = item('a', 1, 500), b = item('b', 2, 500, code: '092800104200054');
    final service = AccountingService(
      listings: [a, b],
      events: [sale('a', a), sale('b', b, register: 2)],
      fees: const FeePolicy(),
    );
    expect(service.settlements().length, 2);
    expect(service.statistics().customerCount, 2);
  });
  test('sorting restores duplicate state and foreign scans do not persist', () {
    final a = item('a', 1, 500), b = item('b', 2, 500, code: '092800104200054');
    final session = ReconciliationSession(
      listings: [a, b],
      events: [],
      sellerKey: a.sellerKey,
    );
    expect(session.scan(a).status, ReconciliationStatus.matched);
    expect(session.scan(a).status, ReconciliationStatus.duplicate);
    expect(session.scan(b).status, ReconciliationStatus.unexpected);
    expect(session.persistedStates.containsKey('b'), false);
    expect(session.report.isFinalized, true);
    expect(session.report.scannedTotal, 3);
    final restored = ReconciliationSession(
      listings: [a, b],
      events: [],
      sellerKey: a.sellerKey,
      saved: session.persistedStates,
    );
    expect(restored.report.duplicates.single.listingId, 'a');
    expect(restored.report.scannedTotal, 2);
  });
  test(
    'invalid, unknown and sold scans remain exceptions without matching',
    () {
      final a = item('a', 1, 500), unknown = item('unknown', 1, 600);
      final session = ReconciliationSession(
        listings: [a],
        events: [sale('a', a)],
      );
      expect(session.scan(a).status, ReconciliationStatus.unexpected);
      expect(session.scan(unknown).status, ReconciliationStatus.unexpected);
      expect(
        session.scan(null, rawCode: 'bad').status,
        ReconciliationStatus.invalid,
      );
      expect(session.report.scannedTotal, 3);
      expect(session.report.invalidCodes, ['bad']);
    },
  );
}
