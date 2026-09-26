import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../domain/barcode.dart';
import '../domain/models.dart';

/// Python json.dumps(sort_keys=True, separators=(',', ':'), ensure_ascii=False).
/// Monetary calculations never use these floating point metadata numbers.
String pythonCanonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()
      ..sort((a, b) {
        final aa = a.runes.toList(), bb = b.runes.toList();
        for (var i = 0; i < aa.length && i < bb.length; i++) {
          if (aa[i] != bb[i]) return aa[i].compareTo(bb[i]);
        }
        return aa.length.compareTo(bb.length);
      });
    return '{${keys.map((key) => '${jsonEncode(key)}:${pythonCanonicalJson(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(pythonCanonicalJson).join(',')}]';
  if (value is double) {
    if (!value.isFinite) {
      throw const FormatException('Nicht-endliche JSON-Zahl.');
    }
    if (value == 0) return value.isNegative ? '-0.0' : '0.0';
    final scientific = value.toStringAsExponential();
    final parts = scientific.split('e');
    final exponent = int.parse(parts[1]);
    if (exponent < -4 || exponent >= 16) {
      return '${parts[0]}e${exponent < 0 ? "-" : "+"}${exponent.abs().toString().padLeft(2, '0')}';
    }
    return value.toString();
  }
  return jsonEncode(value);
}

/// Exact decimal input at the external Euro boundary, without float arithmetic.
int euroToCents(Object? value) {
  final text = value.toString().trim().replaceAll(',', '.');
  final match = RegExp(r'^([0-9]+)(?:\.([0-9]*))?$').firstMatch(text);
  if (match == null) throw const FormatException('Ungültiger Preis.');
  var decimals = match[2] ?? '';
  while (decimals.length > 2 && decimals.endsWith('0')) {
    decimals = decimals.substring(0, decimals.length - 1);
  }
  if (decimals.length > 2) {
    throw const FormatException('Preis hat mehr als zwei Nachkommastellen.');
  }
  return int.parse(match[1]!) * 100 + int.parse(decimals.padRight(2, '0'));
}

class MarketPackage {
  final MarketSession session;
  final List<ArticleListing> listings;
  final Map<String, Object?> body;
  final String rawJson, sourceSha256;
  bool get isLegacy => session.exportGeneration == 0;
  MarketPackage._(
    this.session,
    this.listings,
    this.body,
    this.rawJson,
    this.sourceSha256,
  );

  factory MarketPackage.parse(
    String raw, {
    bool verifyChecksum = true,
    int registerNumber = 1,
  }) {
    if (registerNumber <= 0) {
      throw const FormatException('Kassennummer muss positiv sein.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Marktpaket muss ein JSON-Objekt sein.');
    }
    final body = Map<String, Object?>.from(decoded);
    final version = body['version'];
    if (version != '2.0' && version != '1.2') {
      throw const FormatException('Nicht unterstützte Exportversion.');
    }
    if (version == '2.0' && verifyChecksum) {
      final expected = body['checksum'];
      final unsigned = Map<String, Object?>.from(body)..remove('checksum');
      final actual = sha256
          .convert(utf8.encode(pythonCanonicalJson(unsigned)))
          .toString();
      if (expected is! String ||
          expected.replaceFirst(RegExp(r'^sha256:'), '').toLowerCase() !=
              actual) {
        throw const FormatException('Prüfsumme des Marktpakets stimmt nicht.');
      }
    }
    final market = _map(body['market'], 'market');
    final marketId = _positiveInt(market['id'], 'Markt-ID');
    final generation = version == '2.0'
        ? _positiveInt(market['exportGeneration'], 'Exportgeneration')
        : 0;
    final articles = <String, Map<String, Object?>>{};
    for (final item in _list(body['articles'], 'articles')) {
      final article = _map(item, 'Artikel');
      final id = _text(article['articleId'], 'Artikel-ID');
      if (articles.containsKey(id)) {
        throw const FormatException('Doppelte Artikel-ID.');
      }
      articles[id] = article;
    }
    final boxes = <String, int>{};
    for (final item in _list(
      body['stammnummernMapping'],
      'stammnummernMapping',
    )) {
      final mapping = _map(item, 'Box-Zuordnung');
      final box = _integer(mapping['stammnummer'], 'Boxnummer');
      if (box < 0) throw const FormatException('Ungültige Boxnummer.');
      for (final id in _list(mapping['articleIds'], 'articleIds')) {
        if (id is! String ||
            !articles.containsKey(id) ||
            boxes.containsKey(id)) {
          throw const FormatException(
            'Fehlende oder mehrdeutige Artikel-/Box-Zuordnung.',
          );
        }
        boxes[id] = box;
      }
    }
    final listings = <ArticleListing>[];
    final seenCodes = <String>{},
        seenIds = <String>{},
        seenArticles = <String>{};
    for (final item in _list(body['listings'], 'listings')) {
      final listing = _map(item, 'Listing');
      if (listing['marketId'] != marketId) {
        throw const FormatException('Listing gehört zu einem anderen Markt.');
      }
      final id = _text(listing['listingId'], 'Listing-ID');
      final articleId = _text(listing['articleId'], 'Artikel-ID');
      final article = articles[articleId];
      final box = boxes[articleId];
      if (article == null || box == null) {
        throw const FormatException('Listing ohne Artikel oder Box-Zuordnung.');
      }
      final fields = _map(article['fields'], 'Artikelfelder');
      final code = _text(article['codeFull'], 'Artikelcode');
      if (code.length != 15 || LabelCode.manual(code, 1).codeFull != code) {
        throw const FormatException('Ungültiger Artikelcode.');
      }
      final articleNumber = _integer(article['articleNr'], 'Artikelnummer');
      if (articleNumber != LabelCode.manual(code, 1).articleNumber) {
        throw const FormatException(
          'Artikelnummer widerspricht dem Artikelcode.',
        );
      }
      if (!seenCodes.add(code) ||
          !seenIds.add(id) ||
          !seenArticles.add(articleId)) {
        throw const FormatException('Doppelte Artikel-/Listing-Identität.');
      }
      final cents = generation > 0
          ? _integer(listing['priceSnapshotCents'], 'Preis in Cent')
          : euroToCents(listing['priceSnapshot'] ?? fields['price']);
      if (cents < 0) {
        throw const FormatException('Preis darf nicht negativ sein.');
      }
      listings.add(
        ArticleListing(
          listingId: id,
          articleId: articleId,
          codeFull: code,
          title: '${fields['description'] ?? fields['title'] ?? ''}',
          priceCents: cents,
          labelRevision: generation > 0
              ? _positiveInt(
                  listing['acceptedLabelRevision'],
                  'Etikettenrevision',
                )
              : 0,
          exportGeneration: generation,
          boxNumber: box,
          marketId: '$marketId',
          legacyArticleNumber: articleNumber,
          size: '${fields['size'] ?? ''}',
          fields: fields,
        ),
      );
    }
    if (listings.isEmpty ||
        seenArticles.length != boxes.length ||
        seenArticles.length != articles.length) {
      throw const FormatException(
        'Marktpaket enthält keine vollständigen Artikel-/Listing-Zuordnungen.',
      );
    }
    final digest = sha256.convert(utf8.encode(raw)).toString();
    return MarketPackage._(
      MarketSession(
        marketId: '$marketId',
        name: '${market['name'] ?? 'Markt $marketId'}',
        registerNumber: registerNumber,
        exportGeneration: generation,
        exportChecksum: digest,
        metadata: body,
      ),
      List.unmodifiable(listings),
      Map.unmodifiable(body),
      raw,
      digest,
    );
  }

  factory MarketPackage.fromLegacy(
    String raw, {
    required String name,
    int registerNumber = 1,
  }) {
    if (name.trim().isEmpty) throw const FormatException('Marktname fehlt.');
    final tables = jsonDecode(raw);
    if (tables is! List) {
      throw const FormatException('V1-Export benötigt eine JSON-Liste.');
    }
    final digest = sha256.convert(utf8.encode(raw)).toString();
    final marketId = int.parse(digest.substring(0, 12), radix: 16) + 1;
    final articles = <Map<String, Object?>>[],
        listings = <Map<String, Object?>>[],
        mapping = <Map<String, Object?>>[];
    var maxBox = 0;
    int? assigned;
    for (final table in tables) {
      if (table is! Map || table['type'] != 'table') continue;
      final tableName = '${table['name'] ?? ''}';
      if (tableName == 'verkaeufer' &&
          table['data'] is List &&
          (table['data'] as List).isNotEmpty) {
        assigned = (table['data'] as List).length;
      }
      if (!tableName.startsWith('stnr')) continue;
      final box = int.tryParse(tableName.substring(4));
      if (box == null || box < 0 || box > 999 || table['data'] is! List) {
        throw const FormatException('Ungültige V1-Artikeltabelle.');
      }
      if (box > maxBox) maxBox = box;
      final ids = <String>[];
      for (final row in table['data'] as List) {
        if (row is! Map) {
          throw const FormatException('Ungültige V1-Artikelzeile.');
        }
        final title = '${row['beschreibung'] ?? ''}'.trim();
        final size = '${row['groesse'] ?? ''}'.trim();
        final price = '${row['preis'] ?? ''}'.trim();
        if (title.isEmpty && size.isEmpty && price.isEmpty) continue;
        final number = int.tryParse('${row['artikelnummer']}'.trim());
        if (title.isEmpty || number == null || number < 0 || number > 9999) {
          throw const FormatException(
            'V1-Artikel benötigt Beschreibung und gültige Artikelnummer.',
          );
        }
        final cents = euroToCents(price);
        final articleId = 'v1-$box-$number';
        final code = LabelCode.manual(
          '0927001${box.toString().padLeft(3, '0')}${number.toString().padLeft(4, '0')}',
          1,
        ).codeFull;
        // Decimal strings retain exact cents at this legacy boundary.
        final euro =
            '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
        articles.add({
          'articleId': articleId,
          'articleNr': number,
          'codeFull': code,
          'fields': {'description': title, 'size': size, 'price': euro},
        });
        listings.add({
          'listingId': 'listing-$articleId',
          'articleId': articleId,
          'marketId': marketId,
          'status': 'For Sale',
          'priceSnapshot': euro,
        });
        ids.add(articleId);
      }
      if (ids.isNotEmpty) {
        mapping.add({
          'stammnummer': box,
          'userId': 'user-$box',
          'articleIds': ids,
        });
      }
    }
    final result = MarketPackage.parse(
      jsonEncode({
        'version': '1.2',
        'market': {'id': marketId, 'name': name.trim()},
        'provenance': {'origin': 'v1', 'sourceSha256': digest},
        'marketParameters': {
          'maxStammnummern': null,
          'assignedStammnummern': assigned ?? (maxBox == 0 ? null : maxBox),
        },
        'fees': {
          'sellerFeeFlat': 0,
          'sellerFeePerStammnummer': 5,
          'revenueSharePercent': 15,
        },
        'articles': articles,
        'listings': listings,
        'stammnummernMapping': mapping,
      }),
      registerNumber: registerNumber,
    );
    return MarketPackage._(
      result.session,
      result.listings,
      result.body,
      result.rawJson,
      digest,
    );
  }
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map) throw FormatException('$field muss ein Objekt sein.');
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value, String field) {
  if (value is! List) throw FormatException('$field muss eine Liste sein.');
  return value;
}

String _text(Object? value, String field) {
  if (value is! String || value.isEmpty) throw FormatException('$field fehlt.');
  return value;
}

int _integer(Object? value, String field) {
  if (value is! int) throw FormatException('$field muss ganzzahlig sein.');
  return value;
}

int _positiveInt(Object? value, String field) {
  final result = _integer(value, field);
  if (result <= 0) throw FormatException('$field muss positiv sein.');
  return result;
}
