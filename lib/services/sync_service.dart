import 'dart:convert';
import '../data/checkout_store.dart';
import '../data/market_package.dart';
import '../domain/models.dart';
import 'api_client.dart';

class SyncResult {
  final String stage;
  final int sent, acknowledged;
  final List<Map<String, Object?>> results;
  const SyncResult(this.stage, this.sent, this.acknowledged, this.results);
}

/// Local durable protocols are written before any acknowledgement is persisted.
/// Missing/unknown results always leave events in the durable outbox.
class SyncService {
  final CheckoutStore? _store;
  CheckoutStore get store =>
      _store ??
      (throw StateError('Zuerst eine Kasse in der Bibliothek öffnen.'));
  final ApiClient api;
  SyncService(this._store, this.api);
  static const _archiveKey = 'syncProtocols';
  Future<List<Map<String, Object?>>> protocols() async =>
      ((await store.setting(_archiveKey)) as List? ?? [])
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
  Future<List<Map<String, Object?>>> referrals() async =>
      ((await store.setting('syncReferrals')) as List? ?? [])
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
  Future<void> _save(Map<String, Object?> protocol) async {
    final archive = await protocols();
    archive.add(protocol);
    await store.setSetting(_archiveKey, archive);
    await store.log(
      'sync',
      '${protocol['stage']}: ${protocol['error'] ?? protocol['status']}',
    );
  }

  void _validateUpload() {
    if (store.session.isDemo ||
        store.session.exportGeneration <= 0 ||
        int.tryParse(store.session.marketId) == null ||
        int.parse(store.session.marketId) <= 0) {
      throw StateError(
        'Demo- und lokale V1-Märkte dürfen nicht hochgeladen werden.',
      );
    }
    if (!api.hasToken) throw const AuthenticationRequiredException();
  }

  Future<List<Map<String, Object?>>> markets(String organizationId) async {
    if (organizationId.trim().isEmpty) {
      throw const FormatException('Organisations-ID fehlt.');
    }
    final response = await api.request(
      'GET',
      '/markets',
      params: {'organizationId': organizationId.trim(), 'pageSize': 100},
    );
    final body = jsonDecode(response.body);
    if (body is! Map || body['items'] is! List) {
      throw const FormatException('Ungültige Marktliste.');
    }
    return (body['items'] as List).map((e) {
      if (e is! Map || e['id'] is! int || (e['id'] as int) <= 0) {
        throw const FormatException('Ungültiger Markt in der Liste.');
      }
      return Map<String, Object?>.from(e);
    }).toList();
  }

  Future<MarketPackage> download(int marketId, {int? registerNumber}) async {
    if (marketId <= 0) throw const FormatException('Ungültige Markt-ID.');
    try {
      final response = await api.request('GET', '/markets/$marketId/export');
      final package = MarketPackage.parse(
        response.body,
        registerNumber: registerNumber ?? _store?.session.registerNumber ?? 1,
      );
      if (package.session.marketId != '$marketId' || package.isLegacy) {
        throw const FormatException(
          'Backend liefert einen falschen Markt oder kein V2-Paket.',
        );
      }
      return package;
    } on AccountLockedException {
      throw const ApiException(
        'Markt nicht eingefroren. Zuerst in der Web-App einfrieren.',
        statusCode: 423,
      );
    } on ApiException catch (error) {
      if (error.statusCode == 422) {
        throw const ApiException(
          'Feldprofil ungültig: Pflichtfeld Preis fehlt.',
          statusCode: 422,
        );
      }
      rethrow;
    }
  }

  Future<SyncResult> uploadSales({bool retryOnly = false}) async {
    _validateUpload();
    var events = await store.pendingEvents();
    if (retryOnly) {
      final queue = ((await store.setting('syncReuploadQueue')) as List? ?? [])
          .cast<String>()
          .toSet();
      events = events.where((event) => queue.contains(event.id)).toList();
    }
    return _run('sales-batch', events, () async {
      if (events.isEmpty) return const SyncResult('sales-batch', 0, 0, []);
      for (final event in events) {
        if (!RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-7[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
            ).hasMatch(event.id) ||
            event.listing.priceCents < 0 ||
            event.registerNumber <= 0 ||
            (!event.listing.unexpected && event.listing.labelRevision <= 0)) {
          throw const FormatException(
            'Verkauf benötigt UUIDv7, positive Kasse und einen gültigen Preis-/Revisionssnapshot.',
          );
        }
        if (event.listing.marketId != store.session.marketId ||
            event.listing.exportGeneration != store.session.exportGeneration) {
          throw const FormatException(
            'Verkauf gehört zu einem anderen Marktexport.',
          );
        }
      }
      final response = await api.request(
        'POST',
        '/sales/batch',
        json: {
          'marketId': int.parse(store.session.marketId),
          'exportGeneration': store.session.exportGeneration,
          'sales': [
            for (final event in events)
              {
                'vorgangId': event.id,
                'occurredAt': event.occurredAt,
                'kassenNummer': event.registerNumber,
                'kundenNummer': event.customerNumber,
                'cancelOf': event.cancelOf,
                'items': [
                  {
                    'listingId': event.listing.unexpected
                        ? null
                        : event.listing.listingId,
                    // Only JSON's external euro representation; calculations stay integer cents.
                    'priceSnapshot': num.parse(
                      '${event.listing.priceCents ~/ 100}.${(event.listing.priceCents % 100).toString().padLeft(2, '0')}',
                    ),
                    'priceSnapshotCents': event.listing.priceCents,
                    if (event.listing.labelRevision > 0)
                      'labelRevision': event.listing.labelRevision,
                  },
                ],
              },
          ],
        },
      );
      final results = _parseResults(
        response.body,
        ['results', 'sales', 'items'],
        'vorgangId',
        events.map((e) => e.id).toSet(),
      );
      final acknowledged = results
          .where((r) => {'created', 'skipped_duplicate'}.contains(r['result']))
          .length;
      return SyncResult('sales-batch', events.length, acknowledged, results);
    });
  }

  Future<SyncResult> uploadListingStatus() async {
    _validateUpload();
    final all = await store.events();
    final effective = _effective(all);
    final ids = effective
        .where((e) => !e.listing.unexpected)
        .map((e) => e.listing.listingId)
        .toSet();
    return _run('listing-status', all, () async {
      if (ids.isEmpty) return const SyncResult('listing-status', 0, 0, []);
      final response = await api.request(
        'POST',
        '/listings/status',
        json: {
          'marketId': int.parse(store.session.marketId),
          'updates': [
            for (final id in ids.toList()..sort())
              {'listingId': id, 'fromStatus': 'For Sale', 'toStatus': 'Sold'},
          ],
        },
      );
      final results = _parseResults(
        response.body,
        ['results', 'updates', 'items'],
        'listingId',
        ids,
      );
      return SyncResult('listing-status', ids.length, 0, results);
    });
  }

  Future<SyncResult> uploadSummary() async {
    _validateUpload();
    final all = await store.events();
    final effective = _effective(all);
    return _run('sales-summary', all, () async {
      if (all.isEmpty) return const SyncResult('sales-summary', 0, 0, []);
      final days = all.map((e) => e.occurredAt.substring(0, 10)).toList()
        ..sort();
      await api.request(
        'POST',
        '/markets/${store.session.marketId}/sales-summary',
        json: {
          'marketDay': days.first,
          'totalRevenueCents': effective.fold<int>(
            0,
            (sum, e) => sum + e.listing.priceCents,
          ),
          'salesCount': effective.length,
          'cancelCount': all.where((e) => e.cancelOf != null).length,
        },
      );
      return SyncResult('sales-summary', all.length, 0, const []);
    });
  }

  Future<SyncResult> _run(
    String stage,
    List<SaleEvent> events,
    Future<SyncResult> Function() action,
  ) async {
    final protocol = <String, Object?>{
      'stage': stage,
      'marketId': store.session.marketId,
      'exportGeneration': store.session.exportGeneration,
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final result = await action();
      protocol.addAll({
        'status': result.sent == 0
            ? 'skipped'
            : (stage == 'sales-batch' && result.acknowledged != result.sent) ||
                  result.results.any(
                    (r) => {
                      'conflict',
                      'invalid',
                      'not_found',
                      'missing_ack',
                    }.contains(r['result']),
                  )
            ? 'needs_review'
            : 'success',
        'sent': result.sent,
        'acknowledged': result.acknowledged,
        'results': result.results,
      });
      await _save(protocol);
      if (stage == 'sales-batch') {
        final ids = result.results
            .where(
              (r) => {'created', 'skipped_duplicate'}.contains(r['result']),
            )
            .map((r) => r['vorgangId'] as String)
            .toList();
        final queue =
            ((await store.setting('syncReuploadQueue')) as List? ?? [])
                .cast<String>()
                .toSet();
        final cancellations = events
            .where((e) => e.cancelOf != null)
            .map((e) => e.id)
            .toSet();
        for (final row in result.results) {
          final id = row['vorgangId'] as String;
          if (ids.contains(id)) {
            queue.remove(id);
          } else if (row['result'] == 'invalid' && cancellations.contains(id)) {
            queue.add(id);
          }
        }
        await store.setSetting('syncReuploadQueue', queue.toList()..sort());
        await store.acknowledgeEvents(ids);
        final pending = events
            .where((e) => !ids.contains(e.id))
            .map((e) => e.id)
            .toList();
        if (pending.isNotEmpty) {
          await store.recordSyncFailure(
            pending,
            'Keine bestätigte Übernahme; Importprotokoll prüfen.',
          );
        }
      }
      return result;
    } catch (error) {
      await store.recordSyncFailure(
        events.map((e) => e.id).toList(),
        error.toString(),
      );
      if (!protocol.containsKey('status')) {
        protocol.addAll({
          'status': 'error',
          'error': error.toString(),
          if (error is ApiException) 'httpStatus': error.statusCode,
        });
        await _save(protocol);
      }
      rethrow;
    }
  }

  Future<void> referConflict(String eventId, String conflictType) async {
    _validateUpload();
    final events = (await store.events())
        .where((event) => event.id == eventId)
        .toList();
    if (events.length != 1) {
      throw const FormatException('Konfliktvorgang nicht gefunden.');
    }
    final event = events.single;
    final existing = await referrals();
    if (existing.any((r) => r['vorgangId'] == eventId)) return;
    await api.request(
      'POST',
      '/markets/${store.session.marketId}/sale-conflicts',
      json: {
        'conflictType': conflictType,
        'vorgangIdA': event.id,
        'vorgangIdB': null,
        'listingId': event.listing.unexpected ? null : event.listing.listingId,
        'raisedByKasseNummer': event.registerNumber,
      },
    );
    existing.add({
      'vorgangId': eventId,
      'conflictType': conflictType,
      'raisedAt': DateTime.now().toUtc().toIso8601String(),
      'kassenNummer': event.registerNumber,
    });
    await store.setSetting('syncReferrals', existing);
    await store.log(
      'sync',
      'Konflikt $eventId an Organisator verwiesen; Entscheidung offen.',
    );
  }

  Future<void> cancelConflict(String eventId) async {
    final events = await store.events();
    if (!events.any((e) => e.id == eventId && e.cancelOf == null)) {
      throw const FormatException('Originalverkauf nicht gefunden.');
    }
    if (events.any((e) => e.cancelOf == eventId)) return;
    await store.cancel(eventId);
  }

  /// Deletes one exact protocol snapshot; never sales, queue or referrals.
  Future<void> deleteProtocol(Map<String, Object?> selected) async {
    final archive = await protocols();
    final fingerprint = pythonCanonicalJson(selected);
    final index = archive.indexWhere(
      (row) => pythonCanonicalJson(row) == fingerprint,
    );
    if (index < 0) {
      throw StateError('Protokoll wurde inzwischen verändert oder gelöscht.');
    }
    archive.removeAt(index);
    await store.setSetting(_archiveKey, archive);
  }

  Future<String> exportProtocols() async =>
      const JsonEncoder.withIndent('  ').convert({
        'marketId': store.session.marketId,
        'protocols': await protocols(),
        'referrals': await referrals(),
      });

  /// Conflict exports include unresolved responses and unexpected legacy sales.
  Future<List<Map<String, Object?>>> conflicts() async {
    final rows = <Map<String, Object?>>[];
    for (final protocol in await protocols()) {
      for (final result in protocol['results'] as List? ?? []) {
        if (result is! Map ||
            !{
              'conflict',
              'invalid',
              'not_found',
              'missing_ack',
            }.contains(result['result'])) {
          continue;
        }
        rows.add({
          'marketId': store.session.marketId,
          'quelle': 'sync',
          'stufe': protocol['stage'],
          'erstellt': protocol['at'],
          'kind': result['vorgangId'] != null ? 'sale' : 'listing',
          'identifier': result['vorgangId'] ?? result['listingId'],
          'result': result['result'],
          'detail': result['message'] ?? result['currentStatus'] ?? '',
        });
      }
    }
    for (final event in await store.events()) {
      if (!event.listing.unexpected) continue;
      rows.add({
        'marketId': store.session.marketId,
        'quelle': 'local',
        'stufe': 'audit',
        'erstellt': event.occurredAt,
        'kind': 'sale',
        'identifier': event.id,
        'result': 'missing_listing',
        'detail': 'Verkauf ohne Backend-Listing; Prüfung erforderlich.',
      });
    }
    return rows;
  }

  Future<String> exportConflicts({bool csv = false, String? stage}) async {
    final rows = (await conflicts())
        .where((row) => stage == null || row['stufe'] == stage)
        .toList();
    if (!csv) {
      return const JsonEncoder.withIndent('  ').convert({
        'erstellt': DateTime.now().toUtc().toIso8601String(),
        'anzahl': rows.length,
        'konflikte': rows,
      });
    }
    const keys = [
      'marketId',
      'quelle',
      'stufe',
      'erstellt',
      'kind',
      'identifier',
      'result',
      'detail',
    ];
    String cell(Object? value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';
    return '${[keys.join(','), ...rows.map((row) => keys.map((key) => cell(row[key])).join(','))].join('\r\n')}\r\n';
  }

  static List<SaleEvent> _effective(List<SaleEvent> all) {
    final canceled = all
        .where((e) => e.cancelOf != null)
        .map((e) => e.cancelOf)
        .toSet();
    return all
        .where((e) => e.cancelOf == null && !canceled.contains(e.id))
        .toList();
  }

  static List<Map<String, Object?>> _parseResults(
    String raw,
    List<String> containers,
    String idKey,
    Set<String> sent,
  ) {
    final body = jsonDecode(raw);
    Object? rows = body;
    if (body is Map) {
      rows = null;
      for (final key in containers) {
        if (body[key] is List) {
          rows = body[key];
          break;
        }
      }
    }
    if (rows is! List) {
      throw const FormatException(
        'Backend bestätigt keine einzelnen Vorgänge. Nichts quittiert.',
      );
    }
    final results = <Map<String, Object?>>[], seen = <String>{};
    for (final row in rows) {
      if (row is! Map ||
          row[idKey] is! String ||
          row['result'] is! String ||
          !sent.contains(row[idKey]) ||
          !seen.add(row[idKey] as String)) {
        throw const FormatException(
          'Backend-Ergebnisse sind unvollständig oder mehrdeutig. Nichts quittiert.',
        );
      }
      results.add(Map<String, Object?>.from(row));
    }
    if (results.isEmpty && sent.isNotEmpty) {
      throw const FormatException(
        'Leere Backend-Bestätigung. Nichts quittiert.',
      );
    }
    for (final id in sent.difference(seen)) {
      results.add({
        idKey: id,
        'result': 'missing_ack',
        'message': 'Keine Einzelbestätigung; Vorgang bleibt unbestätigt.',
      });
    }
    return results;
  }
}
