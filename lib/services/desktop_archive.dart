import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../data/market_package.dart';
import '../domain/models.dart';

class ArchiveConflict {
  final String kind, identifier, message;
  const ArchiveConflict(this.kind, this.identifier, this.message);
}

class DesktopMergeResult {
  final List<SaleEvent> events;
  final Map<String, Map<String, Object?>> reconciliation;
  final List<ArchiveConflict> conflicts;
  const DesktopMergeResult(this.events, this.reconciliation, this.conflicts);
}

/// Pure codec for desktop schema 4. Import is staged; callers persist atomically
/// only after the operator has inspected every reported merge conflict.
class DesktopArchive {
  final MarketSession session;
  final List<SaleEvent> events;
  final Map<String, Map<String, Object?>> reconciliation;
  final Object registerNumber;
  final Object? draftRaw;
  const DesktopArchive._(
    this.session,
    this.events,
    this.reconciliation,
    this.registerNumber,
    this.draftRaw,
  );

  static DesktopArchive decode(
    String raw, {
    required MarketSession session,
    required List<ArticleListing> catalog,
  }) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['version'] is! int ||
        decoded['version'] != 4 ||
        decoded['verkaeufe'] is! List ||
        decoded['reconciliation'] is! List) {
      throw const FormatException(
        'Kassenarchiv benötigt Schema 4 mit Verkäufen und Rücksortierung.',
      );
    }
    final register = decoded['kasse'];
    if (register != 'gesamt' && (register is! int || register <= 0)) {
      throw const FormatException('Ungültige Kassennummer.');
    }
    if (decoded['marketId'] != null &&
        '${decoded['marketId']}' != session.marketId) {
      throw const FormatException(
        'Kassenarchiv gehört zu einem anderen Markt.',
      );
    }
    if (decoded['exportGeneration'] != null &&
        (decoded['exportGeneration'] is! int ||
            decoded['exportGeneration'] != session.exportGeneration)) {
      throw const FormatException(
        'Kassenarchiv gehört zu einer anderen Exportgeneration.',
      );
    }
    final byId = {for (final item in catalog) item.listingId: item};
    final byNumber = <String, ArticleListing>{};
    for (final item in catalog) {
      if (item.marketId != session.marketId ||
          item.exportGeneration != session.exportGeneration) {
        throw const FormatException('Katalog gehört nicht zur Kassensitzung.');
      }
      final key = '${item.boxNumber}:${item.articleNumber}';
      if (byNumber.containsKey(key)) {
        throw const FormatException(
          'Katalog enthält mehrdeutige Box-/Artikelnummern.',
        );
      }
      byNumber[key] = item;
    }
    final events = <SaleEvent>[];
    for (final row in decoded['verkaeufe'] as List) {
      if (row is! Map) {
        throw const FormatException('Ungültiger Verkauf im Archiv.');
      }
      final id = _text(row['vorgangId'], 'Vorgangs-ID');
      final at = _text(row['occurredAt'], 'Zeitpunkt');
      final timestamp = DateTime.tryParse(at);
      if (timestamp == null || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(at)) {
        throw const FormatException(
          'Verkauf benötigt einen Zeitpunkt mit Zeitzone.',
        );
      }
      final box = _integer(row['stammnr'], 'Boxnummer');
      final number = _integer(row['artikelnr'], 'Artikelnummer');
      if (box < 0 ||
          number < 0 ||
          (row['articleNr'] != null &&
              (row['articleNr'] is! int || row['articleNr'] != number))) {
        throw const FormatException(
          'Ungültige oder widersprüchliche Artikelnummer.',
        );
      }
      final cents = euroToCents(row['preis']);
      final rawListing = row['listingId'];
      if (rawListing != null && rawListing is! String) {
        throw const FormatException('Ungültige Listing-ID.');
      }
      final hasListing = rawListing is String && rawListing.isNotEmpty;
      final known = hasListing ? byId[rawListing] : byNumber['$box:$number'];
      if (hasListing &&
          known == null &&
          (row['articleId'] is! String ||
              (row['articleId'] as String).isEmpty)) {
        throw const FormatException(
          'Historischer Verkauf ohne rekonstruierbare Artikelidentität.',
        );
      }
      if (known != null &&
          (known.boxNumber != box ||
              known.articleNumber != number ||
              (row['articleId'] != null &&
                  row['articleId'] != known.articleId))) {
        throw const FormatException(
          'Artikelidentität im Archiv widerspricht dem aktiven Markt.',
        );
      }
      final generation = row['exportGeneration'];
      final revision = row['labelRevision'];
      if (revision != null && (revision is! int || revision < 0)) {
        throw const FormatException('Ungültige historische Etikettenrevision.');
      }
      if (session.exportGeneration > 0 &&
          hasListing &&
          (generation is! int ||
              generation != session.exportGeneration ||
              revision is! int ||
              revision <= 0 ||
              (known != null &&
                  (revision != known.labelRevision ||
                      cents != known.priceCents)))) {
        throw const FormatException(
          'Verkauf passt nicht zu Exportgeneration, Revision oder eingefrorenem Preis.',
        );
      }
      if (session.exportGeneration == 0 &&
          generation != null &&
          generation != 0) {
        throw const FormatException(
          'V2-Verkauf darf nicht in einen lokalen V1-Markt importiert werden.',
        );
      }
      final article = ArticleListing(
        listingId: hasListing ? rawListing : 'unexpected:$id',
        articleId:
            known?.articleId ??
            (hasListing ? row['articleId'] as String : 'unexpected:$id'),
        codeFull: known?.codeFull ?? '',
        title:
            known?.title ??
            (hasListing
                ? 'Historischer Verkauf – Stammdaten fehlen'
                : 'Unerwarteter Verkauf'),
        priceCents: cents,
        labelRevision: hasListing
            ? (known?.labelRevision ?? (revision as int? ?? 0))
            : 0,
        exportGeneration: session.exportGeneration,
        boxNumber: box,
        marketId: session.marketId,
        legacyArticleNumber: number,
        size: known?.size ?? '',
        fields: known?.fields ?? const {'historicalMissingCatalog': true},
        unexpected: !hasListing,
      );
      final canceled = row['storniert'];
      if (canceled is! bool) {
        throw const FormatException('Storno-Kennzeichen fehlt.');
      }
      final legacyCancellation =
          canceled &&
          (row['stornoVorgangId'] == null || row['stornoVorgangId'] == '');
      final cancelOf = canceled && !legacyCancellation
          ? _text(row['stornoVorgangId'], 'Storno-Verweis')
          : null;
      if (cancelOf == id) {
        throw const FormatException(
          'Storno darf nicht auf sich selbst verweisen.',
        );
      }
      final till = _integer(row['kassennr'] ?? register, 'Kassennummer');
      final customer = _integer(row['kundennr'], 'Kundennummer');
      if (till <= 0 || customer < 0) {
        throw const FormatException('Ungültige Kassen-/Kundennummer.');
      }
      if (register is int && till != register) {
        throw const FormatException('Verkauf gehört nicht zur Archivkasse.');
      }
      events.add(
        SaleEvent(
          id: id,
          receiptId: 'desktop:$till:$customer',
          occurredAt: timestamp.toUtc().toIso8601String(),
          inputMethod: '${row['eingabeWeg'] ?? 'manual'}',
          cancelOf: cancelOf,
          registerNumber: till,
          customerNumber: customer,
          rawCode: row['rohcode']?.toString(),
          listing: article,
        ),
      );
      if (legacyCancellation) {
        final original = events.last;
        events.add(
          SaleEvent(
            id: _legacyCancellationId(original.id),
            receiptId: original.receiptId,
            occurredAt: original.occurredAt,
            inputMethod: original.inputMethod,
            cancelOf: original.id,
            registerNumber: original.registerNumber,
            customerNumber: original.customerNumber,
            rawCode: original.rawCode,
            listing: original.listing,
          ),
        );
      }
    }
    final states = <String, Map<String, Object?>>{};
    for (final row in decoded['reconciliation'] as List) {
      if (row is! Map) {
        throw const FormatException('Ungültige Rücksortierungszeile.');
      }
      final item = byNumber['${row['stammnr']}:${row['artikelnr']}'];
      if (item == null) {
        throw const FormatException(
          'Rücksortierung verweist auf unbekannten Artikel.',
        );
      }
      final state = {
        'status': _text(row['status'], 'Rücksortierungsstatus'),
        'scan_count': _integer(row['scan_count'], 'Scananzahl'),
      };
      if ((state['scan_count'] as int) < 0 ||
          !{
            'offen',
            'gefunden',
            'unerwartet',
            'doppelscan',
          }.contains(state['status']) ||
          states.containsKey(item.listingId)) {
        throw const FormatException('Doppelte oder ungültige Rücksortierung.');
      }
      states[item.listingId] = state;
    }
    return DesktopArchive._(
      session,
      List.unmodifiable(events),
      states,
      register!,
      decoded['warenkorb_entwurf'],
    );
  }

  static String encode({
    required MarketSession session,
    required List<SaleEvent> events,
    Map<String, Map<String, Object?>> reconciliation = const {},
    List<ArticleListing> catalog = const [],
    bool consolidated = false,
    Object? draftRaw,
  }) {
    final byId = {
      for (final item in [...catalog, ...events.map((e) => e.listing)])
        item.listingId: item,
    };
    for (final event in events) {
      if (event.listing.marketId != session.marketId ||
          event.listing.exportGeneration != session.exportGeneration) {
        throw const FormatException(
          'Verkaufsereignis gehört nicht zum aktiven Markt.',
        );
      }
    }
    return _wireJson({
      'version': 4,
      'kasse': consolidated ? 'gesamt' : session.registerNumber,
      'marketId': session.marketId,
      'exportGeneration': session.exportGeneration,
      'warenkorb_entwurf': ?draftRaw,
      'verkaeufe': [
        for (final event in events)
          {
            'stammnr': event.listing.boxNumber,
            'artikelnr': event.listing.articleNumber,
            'preis': _Euro(event.listing.priceCents),
            'kassennr': event.registerNumber,
            'kundennr': event.customerNumber,
            'vorgangId': event.id,
            'occurredAt': event.occurredAt,
            'articleId': event.listing.unexpected
                ? null
                : event.listing.articleId,
            'listingId': event.listing.unexpected
                ? null
                : event.listing.listingId,
            'articleNr': event.listing.articleNumber,
            'labelRevision': event.listing.labelRevision > 0
                ? event.listing.labelRevision
                : null,
            'exportGeneration': session.exportGeneration > 0
                ? session.exportGeneration
                : null,
            'eingabeWeg': event.inputMethod,
            'storniert': event.cancelOf != null,
            'stornoVorgangId': event.cancelOf,
            'rohcode': event.rawCode,
          },
      ],
      'reconciliation': [
        for (final entry in reconciliation.entries)
          {
            'stammnr': _catalogItem(byId, entry.key).boxNumber,
            'artikelnr': _catalogItem(byId, entry.key).articleNumber,
            'status': entry.value['status'],
            'scan_count': entry.value['scan_count'] ?? 0,
          },
      ],
    });
  }

  static DesktopMergeResult merge(List<DesktopArchive> archives) {
    final events = <String, SaleEvent>{},
        states = <String, Map<String, Object?>>{};
    final conflicts = <ArchiveConflict>[];
    for (final archive in archives) {
      if (archives.first.session.marketId != archive.session.marketId ||
          archives.first.session.exportGeneration !=
              archive.session.exportGeneration ||
          archives.first.session.exportChecksum !=
              archive.session.exportChecksum) {
        throw const FormatException(
          'Archive gehören nicht zum selben Marktexport.',
        );
      }
      for (final event in archive.events) {
        final previous = events[event.id];
        if (previous != null &&
            _eventIdentity(previous) != _eventIdentity(event)) {
          conflicts.add(
            ArchiveConflict(
              'event_identity',
              event.id,
              'Dieselbe Vorgangs-ID enthält abweichende Daten.',
            ),
          );
        } else {
          events[event.id] = event;
        }
      }
      for (final entry in archive.reconciliation.entries) {
        final previous = states[entry.key];
        if (previous != null &&
            pythonCanonicalJson(previous) != pythonCanonicalJson(entry.value)) {
          conflicts.add(
            ArchiveConflict(
              'reconciliation',
              entry.key,
              'Abweichende Rücksortierungsstände müssen geprüft werden.',
            ),
          );
        } else {
          states[entry.key] = entry.value;
        }
      }
    }
    final canceled = <String>{};
    for (final event in events.values.where((e) => e.cancelOf != null)) {
      final original = events[event.cancelOf];
      if (original == null) {
        conflicts.add(
          ArchiveConflict(
            'missing_original',
            event.id,
            'Original des Stornos fehlt im Archiv.',
          ),
        );
      } else if (original.cancelOf != null ||
          original.listing.listingId != event.listing.listingId ||
          original.listing.priceCents != event.listing.priceCents) {
        conflicts.add(
          ArchiveConflict(
            'invalid_cancellation',
            event.id,
            'Storno passt nicht zum Originalverkauf.',
          ),
        );
      } else if (!canceled.add(original.id)) {
        conflicts.add(
          ArchiveConflict(
            'duplicate_cancellation',
            event.id,
            'Originalverkauf wurde mehrfach storniert.',
          ),
        );
      }
    }
    final sold = <String, String>{};
    for (final event in events.values.where(
      (e) => e.cancelOf == null && !canceled.contains(e.id),
    )) {
      final key = '${event.listing.boxNumber}:${event.listing.articleNumber}';
      if (sold.containsKey(key)) {
        conflicts.add(
          ArchiveConflict(
            'duplicate_sale',
            key,
            'Artikel mehrfach verkauft (${sold[key]}, ${event.id}).',
          ),
        );
      } else {
        sold[key] = event.id;
      }
    }
    return DesktopMergeResult(
      List.unmodifiable(events.values),
      states,
      List.unmodifiable(conflicts),
    );
  }
}

String _eventIdentity(SaleEvent event) => pythonCanonicalJson({
  'id': event.id,
  'at': DateTime.parse(event.occurredAt).toUtc().toIso8601String(),
  'register': event.registerNumber,
  'customer': event.customerNumber,
  'input': event.inputMethod,
  'cancelOf': event.cancelOf,
  'rawCode': event.rawCode,
  'listing': event.listing.toMap(),
});
ArticleListing _catalogItem(Map<String, ArticleListing> catalog, String key) =>
    catalog[key] ??
    (throw const FormatException('Rücksortierungsartikel fehlt im Katalog.'));
int _integer(Object? value, String field) {
  if (value is! int) throw FormatException('$field muss ganzzahlig sein.');
  return value;
}

String _text(Object? value, String field) {
  if (value is! String || value.isEmpty) throw FormatException('$field fehlt.');
  return value;
}

class _Euro {
  final int cents;
  const _Euro(this.cents);
}

String _legacyCancellationId(String original) {
  final bytes = sha256
      .convert(utf8.encode('marketmate:legacy-storno:$original'))
      .bytes
      .take(16)
      .toList();
  final hex = original.replaceAll('-', '');
  if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex)) {
    for (var i = 0; i < 6; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
  }
  bytes[6] = 0x70 | (bytes[6] & 0x0f);
  bytes[8] = 0x80 | (bytes[8] & 0x3f);
  final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${id.substring(0, 8)}-${id.substring(8, 12)}-${id.substring(12, 16)}-${id.substring(16, 20)}-${id.substring(20)}';
}

String _wireJson(Object? value) {
  if (value is _Euro) {
    return '${value.cents ~/ 100}.${(value.cents.abs() % 100).toString().padLeft(2, '0')}';
  }
  if (value is Map) {
    return '{${value.entries.map((e) => '${jsonEncode(e.key)}:${_wireJson(e.value)}').join(',')}}';
  }
  if (value is List) return '[${value.map(_wireJson).join(',')}]';
  return jsonEncode(value);
}
