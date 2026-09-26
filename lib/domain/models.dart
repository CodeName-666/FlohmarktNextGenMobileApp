import 'dart:convert';
import 'barcode.dart';

class ArticleListing {
  final String listingId, articleId, codeFull, title, marketId;
  final int priceCents, labelRevision, exportGeneration, boxNumber;
  final int legacyArticleNumber;
  final String size;
  final Map<String, Object?> fields;
  final bool unexpected;

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
    this.legacyArticleNumber = 0,
    this.size = '',
    this.fields = const {},
    this.unexpected = false,
  });

  int get sellerNumber =>
      codeFull.length == 15 ? int.parse(codeFull.substring(7, 10)) : boxNumber;
  int get articleNumber => codeFull.length == 15
      ? int.parse(codeFull.substring(10, 14))
      : legacyArticleNumber;
  String get sellerKey =>
      codeFull.length == 15 ? codeFull.substring(0, 10) : 'legacy:$boxNumber';
  bool get isRevisioned => exportGeneration > 0;

  void validateLabel(LabelCode label) {
    if (codeFull != label.codeFull ||
        (isRevisioned && label.revision != labelRevision)) {
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
    'legacyArticleNumber': legacyArticleNumber,
    'size': size,
    'fieldsJson': jsonEncode(fields),
    'unexpected': unexpected ? 1 : 0,
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
    legacyArticleNumber: (row['legacyArticleNumber'] as num?)?.toInt() ?? 0,
    size: row['size'] as String? ?? '',
    fields: row['fieldsJson'] is String
        ? Map<String, Object?>.from(
            jsonDecode(row['fieldsJson'] as String) as Map,
          )
        : const {},
    unexpected: row['unexpected'] == 1 || row['unexpected'] == true,
  );
}

class Receipt {
  final String id, occurredAt;
  final int number, totalCents, tenderedCents;
  final bool tenderedKnown;
  final int registerNumber;
  final int customerNumber;
  const Receipt({
    required this.id,
    required this.occurredAt,
    required this.number,
    required this.totalCents,
    required this.tenderedCents,
    this.tenderedKnown = true,
    this.registerNumber = 1,
    int? customerNumber,
  }) : customerNumber = customerNumber ?? number;
  int get changeCents => tenderedCents - totalCents;
  factory Receipt.fromMap(Map<String, Object?> row) => Receipt(
    id: row['id'] as String,
    occurredAt: row['occurredAt'] as String,
    number: row['number'] as int,
    totalCents: row['totalCents'] as int,
    tenderedCents: row['tenderedCents'] as int,
    tenderedKnown: row['tenderedKnown'] != 0,
    registerNumber: row['registerNumber'] as int? ?? 1,
    customerNumber: row['customerNumber'] as int?,
  );
}

class SaleEvent {
  final String id, receiptId, occurredAt, inputMethod;
  final String? cancelOf;
  final int registerNumber;
  final int customerNumber;
  final String? rawCode;
  final ArticleListing listing;
  const SaleEvent({
    required this.id,
    required this.receiptId,
    required this.occurredAt,
    required this.inputMethod,
    required this.cancelOf,
    required this.registerNumber,
    required this.listing,
    this.customerNumber = 0,
    this.rawCode,
  });
  factory SaleEvent.fromMap(Map<String, Object?> row) => SaleEvent(
    id: row['id'] as String,
    receiptId: row['receiptId'] as String,
    occurredAt: row['occurredAt'] as String,
    inputMethod: row['inputMethod'] as String,
    cancelOf: row['cancelOf'] as String?,
    registerNumber: row['registerNumber'] as int,
    listing: ArticleListing.fromMap(row),
    customerNumber: row['customerNumber'] as int? ?? 0,
    rawCode: row['rawCode'] as String?,
  );

  Map<String, Object?> toMap() => {
    ...listing.toMap(),
    'id': id,
    'receiptId': receiptId,
    'occurredAt': occurredAt,
    'inputMethod': inputMethod,
    'cancelOf': cancelOf,
    'registerNumber': registerNumber,
    'customerNumber': customerNumber,
    'rawCode': rawCode,
  };
}

class MarketSession {
  final String marketId, name, exportChecksum;
  final int registerNumber, exportGeneration;
  final bool isDemo;
  final Map<String, Object?> metadata;
  const MarketSession({
    required this.marketId,
    required this.name,
    required this.registerNumber,
    required this.exportGeneration,
    this.exportChecksum = '',
    this.isDemo = false,
    this.metadata = const {},
  });
  Map<String, Object?> toMap() => {
    'marketId': marketId,
    'name': name,
    'registerNumber': registerNumber,
    'exportGeneration': exportGeneration,
    'exportChecksum': exportChecksum,
    'isDemo': isDemo,
    'metadata': metadata,
  };
  factory MarketSession.fromMap(Map<String, Object?> map) => MarketSession(
    marketId: map['marketId'] as String,
    name: map['name'] as String,
    registerNumber: map['registerNumber'] as int,
    exportGeneration: map['exportGeneration'] as int,
    exportChecksum: map['exportChecksum'] as String? ?? '',
    isDemo: map['isDemo'] == true,
    metadata: Map<String, Object?>.from(map['metadata'] as Map? ?? {}),
  );
}

class CartEntry {
  final String entryId;
  final String? pendingEventId;
  final ArticleListing listing;
  final String inputMethod;
  final String? cancelOf;
  CartEntry({
    required this.listing,
    required this.inputMethod,
    this.cancelOf,
    String? entryId,
    this.pendingEventId,
  }) : entryId = entryId ?? listing.listingId;
  int get signedCents =>
      cancelOf == null ? listing.priceCents : -listing.priceCents;
}
