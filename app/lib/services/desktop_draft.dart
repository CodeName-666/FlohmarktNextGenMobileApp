import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../data/market_package.dart';
import '../domain/models.dart';

class DesktopDraftPosition {
  final ArticleListing listing;
  final int signedPriceCents;
  final String? originalEventId, pendingEventId;
  const DesktopDraftPosition(
    this.listing,
    this.signedPriceCents, {
    this.originalEventId,
    this.pendingEventId,
  });
  bool get isReturn => signedPriceCents < 0;
}

/// Validates a desktop basket without adding any committed sale or reservation.
class DesktopDraft {
  final int registerNumber, customerNumber;
  final List<DesktopDraftPosition> positions;
  final Map<String, Object?> raw;
  const DesktopDraft._(
    this.registerNumber,
    this.customerNumber,
    this.positions,
    this.raw,
  );

  static const _fingerprintKey = 'mobileExportSha256';

  static String exportFingerprint(Map<String, Object?> body) =>
      body[_fingerprintKey] as String? ??
      sha256.convert(utf8.encode(_pythonSpacedJson(body))).toString();

  /// Stored sessions keep only the small export header. Article lists live in
  /// `listings` and the original source; a multi-megabyte session row breaks
  /// Android's CursorWindow. The desktop fingerprint is taken beforehand.
  static MarketSession compactSession(MarketSession session) {
    final body = session.metadata;
    if (!body.values.any((v) => v is List)) return session;
    return MarketSession(
      marketId: session.marketId,
      name: session.name,
      registerNumber: session.registerNumber,
      exportGeneration: session.exportGeneration,
      exportChecksum: session.exportChecksum,
      isDemo: session.isDemo,
      metadata: {
        for (final e in body.entries)
          if (e.value is! List) e.key: e.value,
        _fingerprintKey: exportFingerprint(body),
      },
    );
  }

  static Map<String, Object?> encode({
    required MarketSession session,
    required List<CartEntry> positions,
    required int customerNumber,
    required Map<String, Object?> exportBody,
    required String occurredAt,
  }) {
    Object euro(int cents) => jsonDecode(
      '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}',
    );
    return {
      'version': 1,
      'kasse': session.registerNumber,
      'export_sha256': exportFingerprint(exportBody),
      'kunde': {
        'kunden_nummer': customerNumber,
        'artikel_liste': [
          for (final line in positions)
            {
              'stammnummer': line.listing.boxNumber,
              'artikel_nummer': line.listing.articleNumber,
              'preis': euro(line.signedCents),
              'beschreibung': line.listing.title,
              'verkaeufer_nummer': line.listing.sellerNumber,
            },
        ],
      },
      'verkaeufe': [
        for (final line in positions.where((l) => l.cancelOf == null))
          {
            'stammnummer': line.listing.boxNumber,
            'artikel_nummer': line.listing.articleNumber,
            'preis': euro(line.listing.priceCents),
            'kassen_nummer': session.registerNumber,
            'kunden_nummer': customerNumber,
            'vorgangId': line.pendingEventId ?? line.entryId,
            'occurredAt': occurredAt,
            'articleId': line.listing.articleId,
            'listingId': line.listing.listingId,
            'articleNr': line.listing.articleNumber,
            'labelRevision': line.listing.isRevisioned
                ? line.listing.labelRevision
                : null,
            'exportGeneration': line.listing.isRevisioned
                ? line.listing.exportGeneration
                : null,
            'eingabeWeg': line.inputMethod,
            'storniert': false,
            'stornoVorgangId': null,
            'rohcode': null,
          },
      ],
    };
  }

  static DesktopDraft? decode(
    Object? raw, {
    required MarketSession session,
    required List<ArticleListing> catalog,
    required List<SaleEvent> committedEvents,
    required Map<String, Object?> exportBody,
  }) {
    if (raw == null) return null;
    final body = _object(raw, 'Entwurf');
    if (body['version'] is! int ||
        body['version'] != 1 ||
        body['kasse'] is! int ||
        body['kasse'] != session.registerNumber ||
        body['export_sha256'] != exportFingerprint(exportBody)) {
      throw const FormatException(
        'Entwurf passt nicht zu Export, Kasse oder Format.',
      );
    }
    final customer = _object(body['kunde'], 'Kunde');
    final number = _integer(customer['kunden_nummer']);
    if (number <= 0 ||
        committedEvents.any(
          (event) =>
              event.registerNumber == session.registerNumber &&
              event.customerNumber >= number,
        )) {
      throw const FormatException(
        'Kundennummer des Entwurfs ist nicht mehr frei.',
      );
    }
    final byNumber = <String, ArticleListing>{};
    for (final item in catalog) {
      final key = '${item.boxNumber}:${item.articleNumber}';
      if (item.marketId != session.marketId ||
          item.exportGeneration != session.exportGeneration ||
          byNumber.containsKey(key)) {
        throw const FormatException(
          'Mehrdeutiger oder fremder Entwurfskatalog.',
        );
      }
      byNumber[key] = item;
    }
    final canceled = committedEvents
        .where((e) => e.cancelOf != null)
        .map((e) => e.cancelOf)
        .toSet();
    final active = <String, SaleEvent>{};
    for (final event in committedEvents.where(
      (e) => e.cancelOf == null && !canceled.contains(e.id),
    )) {
      final key = '${event.listing.boxNumber}:${event.listing.articleNumber}';
      if (active.containsKey(key)) {
        throw const FormatException(
          'Doppelverkauf vor Entwurfswiederaufnahme klären.',
        );
      }
      active[key] = event;
    }
    final pending = <String, Map<String, Object?>>{};
    final ids = committedEvents.map((e) => e.id).toSet();
    const fields = {
      'stammnummer',
      'artikel_nummer',
      'preis',
      'kassen_nummer',
      'kunden_nummer',
      'vorgangId',
      'occurredAt',
      'articleId',
      'listingId',
      'articleNr',
      'labelRevision',
      'exportGeneration',
      'eingabeWeg',
      'storniert',
      'stornoVorgangId',
      'rohcode',
    };
    for (final value in _list(body['verkaeufe'])) {
      final sale = _object(value, 'Entwurfsverkauf');
      if (sale.keys.toSet().difference(fields).isNotEmpty ||
          fields.difference(sale.keys.toSet()).isNotEmpty) {
        throw const FormatException('Unvollständiger Entwurfsverkauf.');
      }
      final key =
          '${_integer(sale['stammnummer'])}:${_integer(sale['artikel_nummer'])}';
      final item = byNumber[key];
      final id = sale['vorgangId'];
      final at = sale['occurredAt'];
      if (item == null ||
          id is! String ||
          id.isEmpty ||
          !ids.add(id) ||
          pending.containsKey(key) ||
          at is! String ||
          DateTime.tryParse(at) == null ||
          !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(at) ||
          sale['kassen_nummer'] is! int ||
          sale['kassen_nummer'] != session.registerNumber ||
          sale['kunden_nummer'] is! int ||
          sale['kunden_nummer'] != number ||
          sale['storniert'] != false ||
          sale['stornoVorgangId'] != null ||
          euroToCents(sale['preis']) != item.priceCents ||
          active.containsKey(key)) {
        throw const FormatException('Ungültiger Verkauf im Entwurf.');
      }
      if (session.exportGeneration > 0 &&
          (sale['listingId'] != item.listingId ||
              sale['articleId'] != item.articleId ||
              sale['articleNr'] is! int ||
              sale['articleNr'] != item.articleNumber ||
              sale['labelRevision'] is! int ||
              sale['labelRevision'] != item.labelRevision ||
              sale['exportGeneration'] is! int ||
              sale['exportGeneration'] != session.exportGeneration)) {
        throw const FormatException(
          'Entwurf besitzt keinen gültigen Listing-/Revisionssnapshot.',
        );
      }
      pending[key] = sale;
    }
    final positions = <DesktopDraftPosition>[];
    final seen = <String>{}, consumed = <String>{};
    for (final value in _list(customer['artikel_liste'])) {
      final position = _object(value, 'Position');
      final key =
          '${_integer(position['stammnummer'])}:${_integer(position['artikel_nummer'])}';
      final item = byNumber[key];
      final priceText = '${position['preis']}'.trim();
      final returning = priceText.startsWith('-');
      final cents = euroToCents(
        returning ? priceText.substring(1) : position['preis'],
      );
      if (item == null ||
          !seen.add('$key:$returning') ||
          (returning && cents == 0)) {
        throw const FormatException(
          'Ungültige oder doppelte Entwurfsposition.',
        );
      }
      final original = active[key];
      final sale = pending[key];
      if (returning) {
        if ((original == null && sale == null) ||
            cents !=
                (original?.listing.priceCents ?? euroToCents(sale!['preis']))) {
          throw const FormatException(
            'Rückgabe passt zu keinem Originalverkauf.',
          );
        }
        positions.add(
          DesktopDraftPosition(
            original?.listing ?? item,
            -cents,
            originalEventId: original?.id,
            pendingEventId: original == null
                ? sale!['vorgangId'] as String
                : null,
          ),
        );
      } else {
        if (original != null ||
            sale == null ||
            cents != euroToCents(sale['preis'])) {
          throw const FormatException(
            'Position und Entwurfsverkauf widersprechen sich.',
          );
        }
        consumed.add(key);
        positions.add(
          DesktopDraftPosition(
            item,
            cents,
            pendingEventId: sale['vorgangId'] as String,
          ),
        );
      }
    }
    if (positions.isEmpty || consumed.length != pending.length) {
      throw const FormatException('Leerer Entwurf oder Verkauf ohne Position.');
    }
    return DesktopDraft._(
      session.registerNumber,
      number,
      List.unmodifiable(positions),
      Map.unmodifiable(body),
    );
  }
}

String _pythonSpacedJson(Object? value) {
  if (value is Map) {
    // Reuse canonical Unicode-codepoint ordering and scalar number spelling.
    final ordered = jsonDecode(pythonCanonicalJson(value)) as Map;
    return '{${ordered.entries.map((e) => '${jsonEncode(e.key)}: ${_pythonSpacedJson(e.value)}').join(', ')}}';
  }
  if (value is List) return '[${value.map(_pythonSpacedJson).join(', ')}]';
  return pythonCanonicalJson(value);
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map) throw FormatException('$name ist kein Objekt.');
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('Entwurfsliste fehlt.');
  return value;
}

int _integer(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('Ungültige Entwurfsnummer.');
  }
  return value;
}
