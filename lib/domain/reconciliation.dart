import 'accounting.dart';
import 'models.dart';

enum ReconciliationStatus { open, matched, unexpected, duplicate, invalid }

class ReconciliationState {
  final ReconciliationStatus status;
  final int scanCount;
  const ReconciliationState(this.status, this.scanCount);
  String get persistedStatus => switch (status) {
    ReconciliationStatus.matched => 'gefunden',
    ReconciliationStatus.unexpected => 'unerwartet',
    ReconciliationStatus.duplicate => 'doppelscan',
    _ => 'offen',
  };
  factory ReconciliationState.fromMap(Map<String, Object?> map) =>
      ReconciliationState(switch (map['status']) {
        'gefunden' => ReconciliationStatus.matched,
        'unerwartet' => ReconciliationStatus.unexpected,
        'doppelscan' => ReconciliationStatus.duplicate,
        _ => ReconciliationStatus.open,
      }, (map['scan_count'] as num?)?.toInt() ?? 0);
  Map<String, Object?> toMap() => {
    'status': persistedStatus,
    'scan_count': scanCount,
  };
}

class ReconciliationScanResult {
  final ReconciliationStatus status;
  final ArticleListing? listing;
  final int scanCount;
  final String rawCode;
  const ReconciliationScanResult(
    this.status,
    this.listing,
    this.scanCount,
    this.rawCode,
  );
}

class ReconciliationReport {
  final List<ArticleListing> expected, matched, missing, unexpected, duplicates;
  final List<String> invalidCodes;
  final Map<String, int> unknownCodes;
  final int scannedTotal, totalCount, soldCount;
  const ReconciliationReport({
    required this.expected,
    required this.matched,
    required this.missing,
    required this.unexpected,
    required this.duplicates,
    required this.invalidCodes,
    required this.scannedTotal,
    required this.totalCount,
    required this.soldCount,
    this.unknownCodes = const {},
  });
  bool get isFinalized =>
      totalCount > 0 && matched.length + soldCount == totalCount;
}

/// Mutable working session. Persist [persistedStates] atomically before showing
/// durable success. Unknown/foreign/invalid scans are session-local, as desktop.
class ReconciliationSession {
  final String? sellerKey;
  final Map<String, ArticleListing> _catalog, _expected = {};
  final Map<String, int> _counts = {};
  final Set<String> _matched = {};
  final Map<String, ArticleListing> _unexpected = {}, _duplicates = {};
  final List<String> _invalid = [];
  final Map<String, int> _unknown = {};
  final Map<String, ReconciliationState> _states;
  ReconciliationSession._copy(ReconciliationSession source)
    : sellerKey = source.sellerKey,
      _catalog = Map.of(source._catalog),
      _states = Map.of(source._states) {
    _expected.addAll(source._expected);
    _counts.addAll(source._counts);
    _matched.addAll(source._matched);
    _unexpected.addAll(source._unexpected);
    _duplicates.addAll(source._duplicates);
    _invalid.addAll(source._invalid);
    _unknown.addAll(source._unknown);
  }

  /// Stage a scan on a copy and publish it only after persistence succeeds.
  ReconciliationSession copy() => ReconciliationSession._copy(this);
  ReconciliationSession({
    required Iterable<ArticleListing> listings,
    required Iterable<SaleEvent> events,
    this.sellerKey,
    Map<String, ReconciliationState> saved = const {},
  }) : _catalog = {for (final a in listings) a.listingId: a},
       _states = Map.of(saved) {
    final sold = effectiveSaleEvents(
      events,
    ).map((e) => e.listing.listingId).toSet();
    for (final a in _catalog.values) {
      if (!_inScope(a)) continue;
      final key = a.listingId;
      if (!sold.contains(key)) _expected[key] = a;
      final state = saved[key];
      if (state == null || state.status == ReconciliationStatus.open) continue;
      final count = state.scanCount < 1 ? 1 : state.scanCount;
      switch (state.status) {
        case ReconciliationStatus.matched:
          if (_expected.containsKey(key)) {
            _matched.add(key);
            _counts[key] = count;
          } else {
            _states[key] = const ReconciliationState(
              ReconciliationStatus.open,
              0,
            );
          }
        case ReconciliationStatus.duplicate:
          _duplicates[key] = a;
          _counts[key] = count < 2 ? 2 : count;
          if (_expected.containsKey(key)) {
            _matched.add(key);
          } else {
            _unexpected[key] = a;
          }
        case ReconciliationStatus.unexpected:
          if (!_expected.containsKey(key)) {
            _unexpected[key] = a;
            _counts[key] = count;
          } else {
            // A returned article is expected again; an old sold-item scan
            // cannot satisfy or taint its new reconciliation session.
            _states[key] = const ReconciliationState(
              ReconciliationStatus.open,
              0,
            );
          }
        case ReconciliationStatus.open:
        case ReconciliationStatus.invalid:
          break;
      }
    }
  }
  bool _inScope(ArticleListing a) =>
      sellerKey == null || a.sellerKey == sellerKey;
  Map<String, ReconciliationState> get persistedStates =>
      Map.unmodifiable(_states);
  ReconciliationScanResult scanUnknown(String rawCode) {
    final raw = rawCode.trim();
    final count = (_unknown[raw] ?? 0) + 1;
    _unknown[raw] = count;
    return ReconciliationScanResult(
      count > 1
          ? ReconciliationStatus.duplicate
          : ReconciliationStatus.unexpected,
      null,
      count,
      raw,
    );
  }

  ReconciliationScanResult scan(
    ArticleListing? listing, {
    String rawCode = '',
  }) {
    if (listing == null) {
      _invalid.add(rawCode.trim());
      return ReconciliationScanResult(
        ReconciliationStatus.invalid,
        null,
        _invalid.length,
        rawCode.trim(),
      );
    }
    final key = listing.listingId;
    final article = _catalog[key] ?? listing;
    final count = (_counts[key] ?? 0) + 1;
    _counts[key] = count;
    late ReconciliationStatus status;
    if (_expected.containsKey(key)) {
      final duplicate = _matched.contains(key) || _duplicates.containsKey(key);
      _matched.add(key);
      _unexpected.remove(key);
      status = duplicate
          ? ReconciliationStatus.duplicate
          : ReconciliationStatus.matched;
    } else {
      status = count > 1 || _unexpected.containsKey(key)
          ? ReconciliationStatus.duplicate
          : ReconciliationStatus.unexpected;
      _unexpected[key] = article;
    }
    if (status == ReconciliationStatus.duplicate) _duplicates[key] = article;
    if (_catalog.containsKey(key) && _inScope(article)) {
      _states[key] = ReconciliationState(status, count);
    }
    return ReconciliationScanResult(status, article, count, rawCode);
  }

  ReconciliationReport get report {
    final scoped = _catalog.values.where(_inScope).length;
    return ReconciliationReport(
      expected: _sort(_expected.values),
      matched: _sort(_matched.map((key) => _expected[key]!)),
      missing: _sort(
        _expected.values.where((a) => !_matched.contains(a.listingId)),
      ),
      unexpected: _sort(_unexpected.values),
      duplicates: _sort(_duplicates.values),
      invalidCodes: List.unmodifiable(_invalid),
      unknownCodes: Map.unmodifiable(_unknown),
      scannedTotal:
          _counts.values.fold(0, (sum, n) => sum + n) +
          _invalid.length +
          _unknown.values.fold(0, (sum, n) => sum + n),
      totalCount: scoped,
      soldCount: scoped - _expected.length,
    );
  }

  static List<ArticleListing> _sort(Iterable<ArticleListing> values) {
    final result = values.toList()
      ..sort((a, b) {
        final box = a.boxNumber.compareTo(b.boxNumber);
        return box != 0 ? box : a.articleNumber.compareTo(b.articleNumber);
      });
    return List.unmodifiable(result);
  }
}
