import 'barcode.dart';
import 'models.dart';

enum ArticleSearchMode { description, seller, article }

enum ArticleStatusFilter { all, available, sold }

String sellerIdentity(ArticleListing article) {
  final key = article.sellerKey;
  if (key.length != 10 || !RegExp(r'^\d{10}$').hasMatch(key)) {
    return 'V1 · Box ${article.boxNumber}';
  }
  return '${key.substring(0, 2)}-${key.substring(2, 4)}-${key.substring(4, 7)}-${key.substring(7)}';
}

class CatalogField {
  final String id, label;
  final bool numeric;
  const CatalogField(this.id, this.label, {this.numeric = false});
  String value(ArticleListing article) {
    final raw =
        article.fields[id] ??
        switch (id) {
          'description' => article.title,
          'size' => article.size,
          _ => '',
        };
    if (numeric) {
      // Presentation of non-monetary profile numbers only.
      final number = num.tryParse('$raw');
      if (number != null && number.isFinite) {
        if (number == number.truncateToDouble()) return '${number.toInt()}';
        final parts = number.toStringAsFixed(2).split('.');
        final whole = parts.first.replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'),
          (m) => '${m[1]}.',
        );
        return '$whole,${parts.last}';
      }
    }
    return '$raw';
  }
}

List<CatalogField> catalogFields(MarketSession session) {
  final profile = session.metadata['fieldProfile'];
  final raw = profile is Map ? profile['articleFields'] : null;
  final fields = <CatalogField>[];
  final seen = <String>{};
  if (raw is List) {
    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String || id.isEmpty || id == 'price' || !seen.add(id)) {
        continue;
      }
      final label = entry['label'];
      fields.add(
        CatalogField(
          id,
          label is String && label.isNotEmpty ? label : id,
          numeric: entry['type'] == 'number',
        ),
      );
    }
  }
  return fields.isEmpty
      ? const [
          CatalogField('description', 'Beschreibung'),
          CatalogField('size', 'Größe'),
        ]
      : fields;
}

List<ArticleListing> filterCatalog({
  required List<ArticleListing> listings,
  required Set<String> soldListingIds,
  required List<CatalogField> fields,
  required String query,
  required ArticleSearchMode mode,
  ArticleStatusFilter status = ArticleStatusFilter.all,
}) {
  final text = query.trim().toLowerCase();
  if (text.length < (mode == ArticleSearchMode.description ? 2 : 1)) return [];
  bool matches(ArticleListing article) {
    if (mode == ArticleSearchMode.description) {
      final haystack = fields
          .map((f) => f.value(article))
          .join(' ')
          .toLowerCase();
      return text.split(RegExp(r'\s+')).every(haystack.contains);
    }
    if (mode == ArticleSearchMode.article) {
      return RegExp(r'^\d+$').hasMatch(text) &&
          int.tryParse(text) == article.articleNumber;
    }
    if (text == article.sellerKey.toLowerCase()) return true;
    if (RegExp(r'^\d+$').hasMatch(text) && text.length < 14) {
      final number = int.tryParse(text);
      return number == article.boxNumber || number == article.sellerNumber;
    }
    if (text == sellerIdentity(article).toLowerCase()) return true;
    final short = RegExp(r'^(\d+)-(\d+)$').firstMatch(text);
    if (short != null) {
      final seller = int.tryParse(short[1]!);
      return (seller == article.boxNumber || seller == article.sellerNumber) &&
          int.tryParse(short[2]!) == article.articleNumber;
    }
    try {
      final code = text.toUpperCase().startsWith('MM1|')
          ? LabelCode.parse(text.toUpperCase()).codeFull
          : LabelCode.manual(text, 1).codeFull;
      return article.codeFull == code;
    } on FormatException {
      return false;
    }
  }

  final result = listings
      .where(
        (a) =>
            matches(a) &&
            switch (status) {
              ArticleStatusFilter.all => true,
              ArticleStatusFilter.available => !soldListingIds.contains(
                a.listingId,
              ),
              ArticleStatusFilter.sold => soldListingIds.contains(a.listingId),
            },
      )
      .toList();
  result.sort((a, b) {
    var order = (soldListingIds.contains(a.listingId) ? 1 : 0).compareTo(
      soldListingIds.contains(b.listingId) ? 1 : 0,
    );
    if (order == 0) order = a.sellerKey.compareTo(b.sellerKey);
    if (order == 0) order = a.articleNumber.compareTo(b.articleNumber);
    if (order == 0) order = a.listingId.compareTo(b.listingId);
    return order;
  });
  return result;
}

List<SaleEvent> receiptHistory(Receipt receipt, List<SaleEvent> events) {
  final own = events
      .where((e) => e.receiptId == receipt.id)
      .map((e) => e.id)
      .toSet();
  return events
      .where((e) => own.contains(e.id) || own.contains(e.cancelOf))
      .toList()
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
}

List<Receipt> findReceipts(
  String query,
  List<Receipt> receipts,
  List<SaleEvent> events,
) {
  final text = query.trim();
  if (text.isEmpty) return [];
  final number = RegExp(r'^\d+$').hasMatch(text) ? int.tryParse(text) : null;
  return receipts
      .where(
        (r) => number != null
            ? r.number == number ||
                  events.any(
                    (e) => e.receiptId == r.id && e.customerNumber == number,
                  )
            : r.id == text ||
                  events.any((e) => e.receiptId == r.id && e.id == text),
      )
      .toList();
}
