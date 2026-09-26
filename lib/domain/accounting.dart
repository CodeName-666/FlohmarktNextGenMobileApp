import 'models.dart';

/// Rational round-to-nearest, ties-to-even. Monetary input/output is cents.
int roundHalfEven(int numerator, int denominator) {
  if (denominator <= 0) throw ArgumentError.value(denominator);
  final magnitude = numerator.abs();
  var quotient = magnitude ~/ denominator;
  final remainder = magnitude % denominator;
  if (remainder * 2 > denominator ||
      (remainder * 2 == denominator && quotient.isOdd)) {
    quotient++;
  }
  return numerator < 0 ? -quotient : quotient;
}

class FeePolicy {
  final int revenueShareBasisPoints, feePerBoxCents;
  const FeePolicy({this.revenueShareBasisPoints = 0, this.feePerBoxCents = 0})
    : assert(revenueShareBasisPoints >= 0 && revenueShareBasisPoints <= 10000),
      assert(feePerBoxCents >= 0);
  int share(int revenueCents) =>
      roundHalfEven(revenueCents * revenueShareBasisPoints, 10000);
}

/// Cancellations apply across registers. Stable desktop precedence resolves
/// duplicate sale rows for reporting; import must separately expose conflicts.
List<SaleEvent> effectiveSaleEvents(Iterable<SaleEvent> events) {
  final all = events.toList();
  final cancelled = all.map((e) => e.cancelOf).whereType<String>().toSet();
  final sorted =
      all.where((e) => e.cancelOf == null && !cancelled.contains(e.id)).toList()
        ..sort((a, b) {
          var result = a.registerNumber.compareTo(b.registerNumber);
          if (result == 0) {
            result = a.customerNumber.compareTo(b.customerNumber);
          }
          if (result == 0) {
            result = a.listing.boxNumber.compareTo(b.listing.boxNumber);
          }
          if (result == 0) {
            result = a.listing.articleNumber.compareTo(b.listing.articleNumber);
          }
          if (result == 0) result = a.id.compareTo(b.id);
          return result;
        });
  final byListing = <String, SaleEvent>{};
  for (final event in sorted) {
    byListing.putIfAbsent(event.listing.listingId, () => event);
  }
  return List.unmodifiable(byListing.values);
}

class BoxSettlement {
  final int boxNumber, offeredCount, offeredCents, soldCount, revenueCents;
  final int unsoldCount, unsoldCents, openCount, feeCents, payoutCents;
  const BoxSettlement({
    required this.boxNumber,
    required this.offeredCount,
    required this.offeredCents,
    required this.soldCount,
    required this.revenueCents,
    required this.unsoldCount,
    required this.unsoldCents,
    required this.openCount,
    required this.feeCents,
    required this.payoutCents,
  });
}

class SellerSettlement {
  final String sellerKey;
  final List<int> boxNumbers;
  final List<ArticleListing> offered, sold, unsold;
  final List<SaleEvent> missingCatalog;
  final List<BoxSettlement> boxSettlements;
  final int revenueCents, feeCents, payoutCents;
  const SellerSettlement({
    required this.sellerKey,
    required this.boxNumbers,
    required this.offered,
    required this.sold,
    required this.unsold,
    required this.missingCatalog,
    required this.boxSettlements,
    required this.revenueCents,
    required this.feeCents,
    required this.payoutCents,
  });
  int get offeredCents => offered.fold(0, (total, a) => total + a.priceCents);
}

class MarketStatistics {
  final int offeredCount, soldCount, unsoldCount, customerCount, sellerCount;
  final int offeredCents,
      revenueCents,
      processingFeeCents,
      feeCents,
      payoutCents;
  final int knownSoldCount, knownSoldOfferedCents;
  final List<SaleEvent> missingCatalog;
  const MarketStatistics({
    required this.offeredCount,
    required this.soldCount,
    required this.unsoldCount,
    required this.customerCount,
    required this.sellerCount,
    required this.offeredCents,
    required this.revenueCents,
    required this.processingFeeCents,
    required this.feeCents,
    required this.payoutCents,
    required this.knownSoldCount,
    required this.knownSoldOfferedCents,
    required this.missingCatalog,
  });
  int get organizerProceedsCents => processingFeeCents + feeCents;
  double get soldPercent =>
      offeredCount == 0 ? 0 : knownSoldCount * 100 / offeredCount;
  double get soldValuePercent =>
      offeredCents == 0 ? 0 : knownSoldOfferedCents * 100 / offeredCents;
  double get averageItemsPerCustomer =>
      customerCount == 0 ? 0 : soldCount / customerCount;
  int get averageRevenueCents =>
      customerCount == 0 ? 0 : roundHalfEven(revenueCents, customerCount);
  int get averageOfferedPriceCents =>
      offeredCount == 0 ? 0 : roundHalfEven(offeredCents, offeredCount);
  int get averageSoldPriceCents =>
      soldCount == 0 ? 0 : roundHalfEven(revenueCents, soldCount);
}

class AccountingService {
  final List<ArticleListing> listings;
  final List<SaleEvent> events;
  final FeePolicy fees;

  /// Listing ids that have been found (including duplicate scans).
  final Set<String> reconciledListingIds;
  AccountingService({
    required Iterable<ArticleListing> listings,
    required Iterable<SaleEvent> events,
    required this.fees,
    this.reconciledListingIds = const {},
  }) : listings = List.unmodifiable(listings),
       events = List.unmodifiable(events);
  List<SaleEvent> get effectiveSales => effectiveSaleEvents(events);

  List<SellerSettlement> settlements({int? registerNumber}) {
    final sales = effectiveSales
        .where(
          (e) => registerNumber == null || e.registerNumber == registerNumber,
        )
        .toList();
    final keys = {
      ...listings.map((a) => a.sellerKey),
      ...sales.map((e) => e.listing.sellerKey),
    }.toList()..sort();
    final catalogIds = listings.map((a) => a.listingId).toSet();
    return keys.map((key) {
      final offered = listings.where((a) => a.sellerKey == key).toList();
      final sellerSales = sales
          .where((e) => e.listing.sellerKey == key)
          .toList();
      final sold = sellerSales.map((e) => e.listing).toList();
      final soldIds = sold.map((a) => a.listingId).toSet();
      final unsold = offered
          .where((a) => !soldIds.contains(a.listingId))
          .toList();
      final boxes = {
        ...offered.map((a) => a.boxNumber),
        ...sold.map((a) => a.boxNumber),
      }.toList()..sort();
      var cumulative = 0, allocated = 0;
      final breakdown = <BoxSettlement>[];
      for (final box in boxes) {
        final boxOffered = offered.where((a) => a.boxNumber == box).toList();
        final boxSold = sold.where((a) => a.boxNumber == box).toList();
        final boxUnsold = unsold.where((a) => a.boxNumber == box).toList();
        final revenue = _sum(boxSold);
        cumulative += revenue;
        final rounded = fees.share(cumulative), fee = rounded - allocated;
        allocated = rounded;
        breakdown.add(
          BoxSettlement(
            boxNumber: box,
            offeredCount: boxOffered.length,
            offeredCents: _sum(boxOffered),
            soldCount: boxSold.length,
            revenueCents: revenue,
            unsoldCount: boxUnsold.length,
            unsoldCents: _sum(boxUnsold),
            openCount: boxUnsold
                .where((a) => !reconciledListingIds.contains(a.listingId))
                .length,
            feeCents: fee,
            payoutCents: revenue - fee,
          ),
        );
      }
      return SellerSettlement(
        sellerKey: key,
        boxNumbers: List.unmodifiable(boxes),
        offered: List.unmodifiable(offered),
        sold: List.unmodifiable(sold),
        unsold: List.unmodifiable(unsold),
        missingCatalog: List.unmodifiable(
          sellerSales.where((e) => !catalogIds.contains(e.listing.listingId)),
        ),
        boxSettlements: List.unmodifiable(breakdown),
        revenueCents: cumulative,
        feeCents: allocated,
        payoutCents: cumulative - allocated,
      );
    }).toList();
  }

  MarketStatistics statistics({int? registerNumber}) {
    final sales = effectiveSales
        .where(
          (e) => registerNumber == null || e.registerNumber == registerNumber,
        )
        .toList();
    final byId = {for (final a in listings) a.listingId: a};
    final known = sales
        .where((e) => byId.containsKey(e.listing.listingId))
        .toList();
    final revenue = sales.fold(0, (sum, e) => sum + e.listing.priceCents);
    final fee = settlements(
      registerNumber: registerNumber,
    ).fold(0, (sum, s) => sum + s.feeCents);
    return MarketStatistics(
      offeredCount: listings.length,
      soldCount: sales.length,
      unsoldCount: listings.length - known.length,
      customerCount: sales
          .where((e) => e.customerNumber > 0)
          .map((e) => (e.registerNumber, e.customerNumber))
          .toSet()
          .length,
      sellerCount: listings.map((a) => a.sellerKey).toSet().length,
      offeredCents: _sum(listings),
      revenueCents: revenue,
      processingFeeCents:
          listings.map((a) => a.boxNumber).toSet().length * fees.feePerBoxCents,
      feeCents: fee,
      payoutCents: revenue - fee,
      knownSoldCount: known.length,
      knownSoldOfferedCents: known.fold(
        0,
        (sum, e) => sum + byId[e.listing.listingId]!.priceCents,
      ),
      missingCatalog: List.unmodifiable(
        sales.where((e) => !byId.containsKey(e.listing.listingId)),
      ),
    );
  }

  static int _sum(Iterable<ArticleListing> articles) =>
      articles.fold(0, (sum, a) => sum + a.priceCents);
}
