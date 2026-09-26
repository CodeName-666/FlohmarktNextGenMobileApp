import 'barcode.dart';

class ArticleListing {
  final String listingId, articleId, codeFull, title, marketId;
  final int priceCents, labelRevision, exportGeneration, boxNumber;

  const ArticleListing({
    required this.listingId,
    required this.articleId,
    required this.codeFull,
    required this.title,
    required this.priceCents,
    required this.labelRevision,
    required this.exportGeneration,
    required this.boxNumber,
    required this.marketId,
  });

  int get sellerNumber => int.parse(codeFull.substring(7, 10));
  int get articleNumber => int.parse(codeFull.substring(10, 14));

  void validateLabel(LabelCode label) {
    if (codeFull != label.codeFull || label.revision != labelRevision) {
      throw const FormatException(
        'Etikettenrevision veraltet. Aktuelles Etikett verwenden.',
      );
    }
  }

  Map<String, Object?> toMap() => {
    'listingId': listingId,
    'articleId': articleId,
    'codeFull': codeFull,
    'title': title,
    'priceCents': priceCents,
    'labelRevision': labelRevision,
    'exportGeneration': exportGeneration,
    'boxNumber': boxNumber,
    'marketId': marketId,
  };

  factory ArticleListing.fromMap(Map<String, Object?> row) => ArticleListing(
    listingId: row['listingId'] as String,
    articleId: row['articleId'] as String,
    codeFull: row['codeFull'] as String,
    title: row['title'] as String,
    priceCents: row['priceCents'] as int,
    labelRevision: row['labelRevision'] as int,
    exportGeneration: row['exportGeneration'] as int,
    boxNumber: row['boxNumber'] as int,
    marketId: row['marketId'] as String,
  );
}

class Receipt {
  final String id, occurredAt;
  final int number, totalCents, tenderedCents;
  const Receipt({
    required this.id,
    required this.occurredAt,
    required this.number,
    required this.totalCents,
    required this.tenderedCents,
  });
  int get changeCents => tenderedCents - totalCents;
  factory Receipt.fromMap(Map<String, Object?> row) => Receipt(
    id: row['id'] as String,
    occurredAt: row['occurredAt'] as String,
    number: row['number'] as int,
    totalCents: row['totalCents'] as int,
    tenderedCents: row['tenderedCents'] as int,
  );
}

class SaleEvent {
  final String id, receiptId, occurredAt, inputMethod;
  final String? cancelOf;
  final int registerNumber;
  final ArticleListing listing;
  const SaleEvent({
    required this.id,
    required this.receiptId,
    required this.occurredAt,
    required this.inputMethod,
    required this.cancelOf,
    required this.registerNumber,
    required this.listing,
  });
  factory SaleEvent.fromMap(Map<String, Object?> row) => SaleEvent(
    id: row['id'] as String,
    receiptId: row['receiptId'] as String,
    occurredAt: row['occurredAt'] as String,
    inputMethod: row['inputMethod'] as String,
    cancelOf: row['cancelOf'] as String?,
    registerNumber: row['registerNumber'] as int,
    listing: ArticleListing.fromMap(row),
  );
}
