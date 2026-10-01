import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../domain/barcode.dart';
import '../domain/models.dart';
import 'demo_catalog.dart';
import 'large_text.dart';
import '../services/desktop_draft.dart';

const demoSession = MarketSession(
  marketId: demoMarketId,
  name: 'Demomarkt',
  registerNumber: 1,
  exportGeneration: 1,
  isDemo: true,
);

/// One durable market/register session. No process-global current-market state.
class CheckoutStore {
  final Database _db;
  final MarketSession session;
  static const _uuid = Uuid();
  CheckoutStore._(this._db, this.session);

  static Future<CheckoutStore> open({
    required DatabaseFactory factory,
    required String path,
    MarketSession? session,
    List<ArticleListing>? listings,
    bool requireExisting = false,
  }) async {
    if (requireExisting && !await factory.databaseExists(path)) {
      throw StateError(
        'Gespeicherte Kassendatei fehlt. Keine neue Kasse angelegt.',
      );
    }
    final requested = DesktopDraft.compactSession(session ?? demoSession);
    if (requested.marketId.isEmpty ||
        requested.registerNumber < 1 ||
        requested.exportGeneration < 0) {
      throw ArgumentError('Ungültige Kassensitzung.');
    }
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA synchronous = FULL');
        },
        onCreate: (db, _) => _create(db),
        onUpgrade: (db, old, _) async {
          if (old >= 2 && old <= 4) {
            await db.execute('ALTER TABLE cart RENAME TO cart_before_entries');
            await _createCart(db);
            for (final row in await db.query('cart_before_entries')) {
              await db.insert('cart', {...row, 'entryId': row['listingId']});
            }
            await db.execute('DROP TABLE cart_before_entries');
            final held = await db.query(
              'settings',
              where: 'key = ?',
              whereArgs: ['heldCart'],
            );
            if (held.isNotEmpty) {
              final rows = jsonDecode(held.single['value'] as String) as List;
              await db.update(
                'settings',
                {
                  'value': jsonEncode([
                    for (final row in rows)
                      {
                        ...Map<String, Object?>.from(row as Map),
                        'entryId': row['entryId'] ?? row['listingId'],
                      },
                  ]),
                },
                where: 'key = ?',
                whereArgs: ['heldCart'],
              );
            }
          }
          if (old == 4) return;
          if (old >= 2 && old <= 3) {
            if (old == 2) {
              await db.execute(
                'ALTER TABLE receipts ADD COLUMN tenderedKnown INTEGER NOT NULL DEFAULT 1',
              );
              await db.execute(
                "ALTER TABLE logs ADD COLUMN level TEXT NOT NULL DEFAULT 'INFO'",
              );
            }
            await db.execute(
              'ALTER TABLE receipts ADD COLUMN customerNumber INTEGER',
            );
            for (final row in await db.query('receipts')) {
              final related = await db.query(
                'events',
                where: 'receiptId = ?',
                whereArgs: [row['id']],
              );
              final numbers = related
                  .map((e) => _decode(e['data'])['customerNumber'])
                  .whereType<int>()
                  .toSet();
              if (numbers.length > 1) {
                throw const FormatException(
                  'Beleg enthält widersprüchliche Kundennummern.',
                );
              }
              await db.update(
                'receipts',
                {
                  'customerNumber': numbers.isEmpty
                      ? row['number']
                      : numbers.single,
                },
                where: 'id = ?',
                whereArgs: [row['id']],
              );
            }
            return;
          }
          if (old != 1) throw StateError('Unbekannte Datenbankversion.');
          final oldListings = await db.query('listings');
          final oldCart = await db.query('cart');
          final oldReceipts = await db.query('receipts');
          final oldEvents = await db.query('events');
          for (final action in ['update', 'delete']) {
            await db.execute('DROP TRIGGER IF EXISTS events_no_$action');
          }
          // Preserve the previous tables as an internal migration safety copy.
          for (final table in [
            'listings',
            'cart',
            'receipts',
            'events',
            'active_sales',
          ]) {
            await db.execute('ALTER TABLE $table RENAME TO legacy_v1_$table');
          }
          await _create(db);
          await db.insert('settings', {
            'key': 'session',
            'value': jsonEncode(demoSession.toMap()),
          });
          for (final row in oldListings) {
            await db.insert('listings', {
              'id': row['listingId'],
              'data': jsonEncode(row),
            });
          }
          for (final row in oldReceipts) {
            await db.insert('receipts', {
              ...row,
              'registerNumber': 1,
              'customerNumber': row['number'],
            });
          }
          for (final row in oldEvents) {
            await _insertEvent(
              db,
              SaleEvent.fromMap({
                ...row,
                'customerNumber': oldReceipts.singleWhere(
                  (r) => r['id'] == row['receiptId'],
                )['number'],
              }),
            );
          }
          for (final row in oldCart) {
            final listing = oldListings.singleWhere(
              (l) => l['listingId'] == row['listingId'],
            );
            await db.insert('cart', {
              'entryId': row['listingId'],
              'listingId': row['listingId'],
              'data': jsonEncode(listing),
              'inputMethod': row['inputMethod'],
              'cancelOf': null,
            });
          }
        },
      ),
    );
    try {
      final actual = await db.transaction((tx) async {
        final saved = await readLargeText(tx, 'settings', 'value', 'key = ?', [
          'session',
        ]);
        if (saved != null) {
          final full = MarketSession.fromMap(_decode(saved));
          final stored = DesktopDraft.compactSession(full);
          if (!identical(stored, full)) {
            await tx.update(
              'settings',
              {'value': jsonEncode(stored.toMap())},
              where: 'key = ?',
              whereArgs: ['session'],
            );
          }
          if (session != null &&
              (stored.marketId != requested.marketId ||
                  stored.registerNumber != requested.registerNumber ||
                  stored.exportGeneration != requested.exportGeneration ||
                  stored.exportChecksum != requested.exportChecksum)) {
            throw StateError(
              'Diese Kassendatei gehört zu einem anderen Markt, Export oder einer anderen Kasse.',
            );
          }
          await _migrateDrafts(tx, stored);
          await _validateState(tx, stored);
          return stored;
        }
        if (requireExisting) {
          throw const FormatException('Gespeicherte Kassensitzung fehlt.');
        }
        await tx.insert('settings', {
          'key': 'session',
          'value': jsonEncode(requested.toMap()),
        });
        for (final item
            in listings ??
                (session == null ? demoCatalog : <ArticleListing>[])) {
          _validateListing(item, requested);
          await tx.insert('listings', {
            'id': item.listingId,
            'data': jsonEncode(item.toMap()),
          });
        }
        return requested;
      });
      return CheckoutStore._(db, actual);
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  static Future<void> _create(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE listings (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
    );
    await _createCart(db);
    await db.execute(
      '''CREATE TABLE receipts (number INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
      occurredAt TEXT NOT NULL, totalCents INTEGER NOT NULL, tenderedCents INTEGER NOT NULL CHECK(tenderedCents >= 0),
      registerNumber INTEGER NOT NULL CHECK(registerNumber > 0), customerNumber INTEGER NOT NULL CHECK(customerNumber >= 0), tenderedKnown INTEGER NOT NULL DEFAULT 1, CHECK(tenderedCents >= totalCents))''',
    );
    await db.execute(
      '''CREATE TABLE events (id TEXT PRIMARY KEY, receiptId TEXT NOT NULL REFERENCES receipts(id),
      listingId TEXT NOT NULL, cancelOf TEXT UNIQUE REFERENCES events(id), data TEXT NOT NULL)''',
    );
    await db.execute('CREATE INDEX events_listing ON events(listingId)');
    await db.execute(
      'CREATE TABLE outbox (eventId TEXT PRIMARY KEY REFERENCES events(id), acknowledged INTEGER NOT NULL DEFAULT 0, error TEXT)',
    );
    await db.execute(
      'CREATE TABLE reconciliation (listingId TEXT PRIMARY KEY, data TEXT NOT NULL)',
    );
    await db.execute(
      "CREATE TABLE logs (sequence INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT NOT NULL, category TEXT NOT NULL, message TEXT NOT NULL, level TEXT NOT NULL DEFAULT 'INFO')",
    );
    for (final action in ['UPDATE', 'DELETE']) {
      await db.execute(
        "CREATE TRIGGER events_no_${action.toLowerCase()} BEFORE $action ON events BEGIN SELECT RAISE(ABORT, 'Sale events are immutable'); END",
      );
    }
  }

  static Map<String, Object?> _decode(Object? value) =>
      Map<String, Object?>.from(jsonDecode(value as String) as Map);
  static Future<void> _createCart(DatabaseExecutor db) => db.execute(
    'CREATE TABLE cart (entryId TEXT PRIMARY KEY, listingId TEXT NOT NULL, data TEXT NOT NULL, inputMethod TEXT NOT NULL, cancelOf TEXT UNIQUE, pendingEventId TEXT UNIQUE)',
  );
  static Future<Object?> _readSetting(DatabaseExecutor db, String key) async {
    final value = await readLargeText(db, 'settings', 'value', 'key = ?', [
      key,
    ]);
    return value == null ? null : jsonDecode(value);
  }

  static Future<void> _writeSetting(
    DatabaseExecutor db,
    String key,
    Object? value,
  ) => db
      .insert('settings', {
        'key': key,
        'value': jsonEncode(value),
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});

  static Future<List<Map<String, Object?>>> _draftRows(
    DatabaseExecutor db,
  ) async {
    final value = await _readSetting(db, 'parkedDrafts');
    if (value == null) return [];
    if (value is! List) {
      throw const FormatException('Geparkte Vorgänge sind beschädigt.');
    }
    return value.map((r) => Map<String, Object?>.from(r as Map)).toList();
  }

  static List<Map<String, Object?>> _positions(Map<String, Object?> draft) =>
      (draft['rows'] as List)
          .map((r) => Map<String, Object?>.from(r as Map))
          .toList();

  static Future<List<Map<String, Object?>>> _heldRows(
    DatabaseExecutor db,
  ) async => (await _draftRows(db)).expand(_positions).toList();

  static Future<int> _nextNumber(
    DatabaseExecutor db,
    MarketSession session,
  ) async {
    final savedNext = await _readSetting(db, 'nextDraftNumber');
    if (savedNext != null && (savedNext is! int || savedNext < 1)) {
      throw const FormatException('Nächste Vorgangsnummer ist beschädigt.');
    }
    var next = savedNext as int? ?? 1;
    void include(int? number) {
      if (number != null && number >= next) next = number + 1;
    }

    include(await _highestCommittedNumber(db, session));
    include(await _readSetting(db, 'draftCustomerNumber') as int?);
    for (final draft in await _draftRows(db)) {
      include(draft['number'] as int?);
    }
    return next;
  }

  static Future<int> _allocateNumber(
    DatabaseExecutor db,
    MarketSession session,
  ) async {
    final next = await _nextNumber(db, session);
    await _writeSetting(db, 'nextDraftNumber', next + 1);
    return next;
  }

  static Future<int> _ensureNumber(
    DatabaseExecutor db,
    MarketSession session,
  ) async {
    final saved = await _readSetting(db, 'draftCustomerNumber') as int?;
    if (saved != null) return saved;
    final number = await _allocateNumber(db, session);
    await _writeSetting(db, 'draftCustomerNumber', number);
    return number;
  }

  /// Legacy two-cart data lives in settings too; migrate inside the open/restore
  /// transaction so failures preserve the original database or backup intact.
  static Future<void> _migrateDrafts(
    DatabaseExecutor db,
    MarketSession session,
  ) async {
    final legacy = await _readSetting(db, 'heldCart');
    if (legacy != null) {
      if (legacy is! List) {
        throw const FormatException('Wartender Warenkorb ist beschädigt.');
      }
      if (legacy.isNotEmpty) {
        final drafts = await _draftRows(db);
        final number =
            await _readSetting(db, 'heldDraftCustomerNumber') as int? ??
            await _allocateNumber(db, session);
        drafts.add({
          'id': _uuid.v7(),
          'number': number,
          'rows': legacy
              .map(
                (r) => {
                  ...Map<String, Object?>.from(r as Map),
                  'entryId': r['entryId'] ?? r['listingId'],
                },
              )
              .toList(),
          'paymentInput': await _readSetting(db, 'heldPaymentInput'),
        });
        await _writeSetting(db, 'parkedDrafts', drafts);
      }
      await db.delete(
        'settings',
        where: 'key IN (?, ?, ?)',
        whereArgs: ['heldCart', 'heldDraftCustomerNumber', 'heldPaymentInput'],
      );
    }
    if ((await db.query('cart', limit: 1)).isNotEmpty) {
      await _ensureNumber(db, session);
    }
    await _writeSetting(db, 'nextDraftNumber', await _nextNumber(db, session));
  }

  static CartEntry _entry(Map<String, Object?> row) => CartEntry(
    entryId: row['entryId'] as String?,
    pendingEventId: row['pendingEventId'] as String?,
    listing: ArticleListing.fromMap(_decode(row['data'])),
    inputMethod: row['inputMethod'] as String,
    cancelOf: row['cancelOf'] as String?,
  );

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  static String _eventIdentity(SaleEvent event) {
    final data = event.toMap()..remove('receiptId');
    // Desktop archives reconstruct their receipt key from till/customer and the
    // legacy number from the label, so compare those semantic identities.
    data['legacyArticleNumber'] = event.listing.articleNumber;
    data['fieldsJson'] = _canonical(event.listing.fields);
    data['occurredAt'] = DateTime.parse(
      event.occurredAt,
    ).toUtc().toIso8601String();
    return jsonEncode(_canonical(data));
  }

  static void _validateListing(ArticleListing item, MarketSession session) {
    if (item.marketId != session.marketId ||
        item.exportGeneration != session.exportGeneration ||
        item.listingId.isEmpty ||
        item.articleId.isEmpty ||
        item.priceCents < 0 ||
        item.boxNumber < 0) {
      throw const FormatException(
        'Artikel und Marktexport stimmen nicht überein.',
      );
    }
    if (session.exportGeneration > 0) {
      LabelCode.manual(item.codeFull, item.labelRevision);
    }
  }

  static Future<void> _insertEvent(
    DatabaseExecutor db,
    SaleEvent event, {
    bool acknowledged = false,
  }) async {
    await db.insert('events', {
      'id': event.id,
      'receiptId': event.receiptId,
      'listingId': event.listing.listingId,
      'cancelOf': event.cancelOf,
      'data': jsonEncode(event.toMap()),
    });
    await db.insert('outbox', {
      'eventId': event.id,
      'acknowledged': acknowledged ? 1 : 0,
    });
  }

  static Future<List<SaleEvent>> _active(
    DatabaseExecutor db, {
    String? listingId,
  }) async {
    final rows = await db.rawQuery(
      'SELECT e.data FROM events e WHERE e.cancelOf IS NULL '
      'AND NOT EXISTS (SELECT 1 FROM events c WHERE c.cancelOf = e.id) '
      '${listingId == null ? '' : 'AND e.listingId = ?'} ORDER BY e.rowid',
      listingId == null ? [] : [listingId],
    );
    return rows.map((r) => SaleEvent.fromMap(_decode(r['data']))).toList();
  }

  Future<List<ArticleListing>> allListings() async => (await _db.query(
    'listings',
  )).map((r) => ArticleListing.fromMap(_decode(r['data']))).toList();
  Future<List<ArticleListing>> searchArticles(String query) async {
    final q = query.trim().toLowerCase();
    return (await allListings())
        .where(
          (a) =>
              '${a.sellerNumber} ${a.articleNumber} ${a.title} ${a.size} ${a.codeFull} ${a.fields.values.join(' ')}'
                  .toLowerCase()
                  .contains(q),
        )
        .toList();
  }

  Future<ArticleListing> resolve(String raw, {int? revision}) async {
    final items = await allListings();
    final text = raw.trim();
    if (text.startsWith('MM1|') ||
        session.exportGeneration > 0 ||
        text.replaceAll(RegExp(r'[\s-]'), '').length >= 14) {
      final label = text.startsWith('MM1|')
          ? LabelCode.parse(text)
          : LabelCode.manual(
              text,
              revision ?? (session.exportGeneration == 0 ? 1 : 0),
            );
      final matches = items.where((a) => a.codeFull == label.codeFull).toList();
      if (matches.length != 1) {
        throw StateError('Artikel gehört nicht eindeutig zu diesem Markt.');
      }
      matches.single.validateLabel(label);
      return matches.single;
    }
    final short = RegExp(r'^(\d{1,3})-(\d{1,4})$').firstMatch(text);
    List<ArticleListing> found;
    if (short != null) {
      found = items
          .where(
            (a) =>
                a.boxNumber == int.parse(short[1]!) &&
                a.articleNumber == int.parse(short[2]!),
          )
          .toList();
    } else {
      // Legacy device encodings are retained by the importer in the barcode field.
      found = items
          .where(
            (a) =>
                a.fields['barcode']?.toString() == text || a.codeFull == text,
          )
          .toList();
    }
    if (found.length != 1) {
      throw StateError(
        'Artikel nicht eindeutig gefunden. Verkäufer-/Artikelsuche verwenden.',
      );
    }
    return found.single;
  }

  Future<List<ArticleListing>> sellerArticle(int seller, int article) async =>
      (await allListings())
          .where((a) => a.sellerNumber == seller && a.articleNumber == article)
          .toList();
  Future<void> addScan(String raw) async =>
      addResolved(await resolve(raw), inputMethod: 'scan');
  Future<void> addManual(String raw, int revision) async => addResolved(
    await resolve(raw, revision: revision),
    inputMethod: 'manual',
  );
  Future<void> addResolved(
    ArticleListing listing, {
    String inputMethod = 'manual',
    int? visibleRevision,
  }) => _db.transaction((tx) async {
    _validateListing(listing, session);
    if (visibleRevision != null &&
        listing.isRevisioned &&
        listing.labelRevision != visibleRevision) {
      throw const FormatException('Etikettenrevision veraltet.');
    }
    if ((await _heldRows(tx)).any((r) => r['listingId'] == listing.listingId)) {
      throw StateError('Artikel liegt in einem geparkten Vorgang.');
    }
    final stored = await tx.query(
      'listings',
      where: 'id = ?',
      whereArgs: [listing.listingId],
    );
    if (stored.length != 1 ||
        jsonEncode(
              ArticleListing.fromMap(_decode(stored.single['data'])).toMap(),
            ) !=
            jsonEncode(listing.toMap())) {
      throw StateError('Artikel stammt nicht aus dem aktiven Export.');
    }
    if ((await _active(tx, listingId: listing.listingId)).isNotEmpty) {
      throw StateError('Artikel wurde an dieser Kasse bereits verkauft.');
    }
    if ((await tx.query(
      'cart',
      where: 'listingId = ?',
      whereArgs: [listing.listingId],
    )).isNotEmpty) {
      throw StateError('Artikel liegt bereits im Warenkorb.');
    }
    await _ensureNumber(tx, session);
    await tx.insert('cart', {
      'entryId': _uuid.v7(),
      'pendingEventId': _uuid.v7(),
      'listingId': listing.listingId,
      'data': jsonEncode(listing.toMap()),
      'inputMethod': inputMethod,
      'cancelOf': null,
    });
  });
  Future<void> addReturn(String listingId) => _db.transaction((tx) async {
    if ((await _heldRows(tx)).any((r) => r['listingId'] == listingId)) {
      throw StateError('Artikel liegt in einem geparkten Vorgang.');
    }
    await _ensureNumber(tx, session);
    final active = await _active(tx, listingId: listingId);
    final pending = await tx.query(
      'cart',
      where: 'listingId = ?',
      whereArgs: [listingId],
    );
    if (active.isEmpty &&
        pending.length == 1 &&
        pending.single['cancelOf'] == null) {
      final originalId =
          pending.single['pendingEventId'] as String? ?? _uuid.v7();
      await tx.update(
        'cart',
        {'pendingEventId': originalId},
        where: 'entryId = ?',
        whereArgs: [pending.single['entryId']],
      );
      await tx.insert('cart', {
        'entryId': _uuid.v7(),
        'pendingEventId': _uuid.v7(),
        'listingId': listingId,
        'data': pending.single['data'],
        'inputMethod': 'manual',
        'cancelOf': originalId,
      });
      return;
    }
    if (active.length != 1) {
      throw StateError('Kein eindeutiger aktiver Verkauf für diese Rückgabe.');
    }
    if ((await tx.query(
      'cart',
      where: 'listingId = ?',
      whereArgs: [listingId],
    )).isNotEmpty) {
      throw StateError('Artikel liegt bereits im Warenkorb.');
    }
    await tx.insert('cart', {
      'entryId': _uuid.v7(),
      'pendingEventId': _uuid.v7(),
      'listingId': listingId,
      'data': jsonEncode(active.single.listing.toMap()),
      'inputMethod': 'manual',
      'cancelOf': active.single.id,
    });
  });
  Future<void> remove(String listingId) => _db.transaction((tx) async {
    final rows = await tx.query(
      'cart',
      where: 'listingId = ?',
      whereArgs: [listingId],
    );
    if (rows.length > 1) {
      throw StateError(
        'Mehrere Positionen: einzelne Warenkorbposition auswählen.',
      );
    }
    if (rows.isNotEmpty) {
      await _removeEntry(tx, rows.single['entryId'] as String);
    }
  });
  Future<void> removeEntry(String entryId) =>
      _db.transaction((tx) => _removeEntry(tx, entryId));
  static Future<void> _removeEntry(DatabaseExecutor db, String entryId) async {
    final rows = await db.query(
      'cart',
      where: 'entryId = ?',
      whereArgs: [entryId],
    );
    if (rows.isEmpty) return;
    final pending = rows.single['pendingEventId'];
    if (pending != null &&
        (await db.query(
          'cart',
          where: 'cancelOf = ?',
          whereArgs: [pending],
        )).isNotEmpty) {
      throw StateError('Zuerst die zugehörige Rückgabeposition entfernen.');
    }
    await db.delete('cart', where: 'entryId = ?', whereArgs: [entryId]);
  }

  Future<void> discardCart() => _db.transaction((tx) async {
    await tx.delete('cart');
    await tx.delete(
      'settings',
      where: 'key = ?',
      whereArgs: ['draftPaymentInput'],
    );
    await tx.delete(
      'settings',
      where: 'key = ?',
      whereArgs: ['draftCustomerNumber'],
    );
  });

  Future<List<CartEntry>> cartLines() async =>
      (await _db.query('cart', orderBy: 'rowid'))
          .map(
            (r) => CartEntry(
              entryId: r['entryId'] as String?,
              pendingEventId: r['pendingEventId'] as String?,
              listing: ArticleListing.fromMap(_decode(r['data'])),
              inputMethod: r['inputMethod'] as String,
              cancelOf: r['cancelOf'] as String?,
            ),
          )
          .toList();
  Future<List<ArticleListing>> cart() async =>
      (await cartLines()).map((l) => l.listing).toList();

  Future<Receipt> checkout(int tenderedCents, {bool tenderedKnown = true}) =>
      _db.transaction((tx) async {
        final rows = await tx.query('cart', orderBy: 'rowid');
        if (rows.isEmpty) throw StateError('Der Warenkorb ist leer.');
        final total = rows.fold(
          0,
          (sum, row) =>
              sum +
              (_decode(row['data'])['priceCents'] as int) *
                  (row['cancelOf'] == null ? 1 : -1),
        );
        if (tenderedCents < 0 || tenderedCents < total) {
          throw StateError('Der erhaltene Betrag reicht nicht aus.');
        }
        final id = _uuid.v7(),
            occurredAt = DateTime.now().toUtc().toIso8601String();
        final customerNumber = await _ensureNumber(tx, session);
        if ((await tx.query(
          'receipts',
          where: 'registerNumber = ? AND customerNumber = ?',
          whereArgs: [session.registerNumber, customerNumber],
        )).isNotEmpty) {
          throw StateError('Kundennummer ist bereits abgeschlossen.');
        }
        final number = await tx.insert('receipts', {
          'id': id,
          'occurredAt': occurredAt,
          'totalCents': total,
          'tenderedCents': tenderedCents,
          'tenderedKnown': tenderedKnown ? 1 : 0,
          'registerNumber': session.registerNumber,
          'customerNumber': customerNumber,
        });
        for (final row in [
          ...rows.where((r) => r['cancelOf'] == null),
          ...rows.where((r) => r['cancelOf'] != null),
        ]) {
          final listing = ArticleListing.fromMap(_decode(row['data']));
          final cancelOf = row['cancelOf'] as String?;
          final active = await _active(tx, listingId: listing.listingId);
          if (cancelOf == null
              ? active.isNotEmpty
              : active.length != 1 || active.single.id != cancelOf) {
            throw StateError(
              'Verkaufsstatus hat sich geändert. Warenkorb prüfen.',
            );
          }
          await _insertEvent(
            tx,
            SaleEvent(
              id: row['pendingEventId'] as String? ?? _uuid.v7(),
              receiptId: id,
              occurredAt: occurredAt,
              registerNumber: session.registerNumber,
              customerNumber: customerNumber,
              inputMethod: row['inputMethod'] as String,
              cancelOf: cancelOf,
              listing: listing,
            ),
          );
        }
        await tx.delete('cart');
        await tx.delete(
          'settings',
          where: 'key = ?',
          whereArgs: ['draftCustomerNumber'],
        );
        await tx.delete(
          'settings',
          where: 'key = ?',
          whereArgs: ['draftPaymentInput'],
        );
        return Receipt(
          id: id,
          occurredAt: occurredAt,
          number: number,
          totalCents: total,
          tenderedCents: tenderedCents,
          tenderedKnown: tenderedKnown,
          registerNumber: session.registerNumber,
          customerNumber: customerNumber,
        );
      });
  Future<void> cancel(String saleId) => _db.transaction((tx) async {
    final active = (await _active(tx)).where((e) => e.id == saleId).toList();
    if (active.length != 1) {
      throw StateError('Verkauf nicht gefunden oder bereits storniert.');
    }
    final original = active.single;
    final held = await _heldRows(tx);
    if (held.any((row) => row['listingId'] == original.listing.listingId)) {
      throw StateError(
        'Artikel liegt beim wartenden Kunden. Dort entfernen oder abschließen.',
      );
    }
    if ((await tx.query(
      'cart',
      where: 'listingId = ?',
      whereArgs: [original.listing.listingId],
    )).isNotEmpty) {
      throw StateError(
        'Artikel liegt im offenen Warenkorb. Dort entfernen oder abschließen.',
      );
    }
    final occurredAt = DateTime.now().toUtc().toIso8601String();
    final receiptId = _uuid.v7();
    final customerNumber = await _allocateNumber(tx, session);
    await tx.insert('receipts', {
      'id': receiptId,
      'occurredAt': occurredAt,
      'totalCents': -original.listing.priceCents,
      'tenderedCents': 0,
      'tenderedKnown': 0,
      'registerNumber': session.registerNumber,
      'customerNumber': customerNumber,
    });
    await _insertEvent(
      tx,
      SaleEvent(
        id: _uuid.v7(),
        receiptId: receiptId,
        occurredAt: occurredAt,
        registerNumber: session.registerNumber,
        customerNumber: customerNumber,
        inputMethod: original.inputMethod,
        cancelOf: original.id,
        listing: original.listing,
      ),
    );
  });
  Future<List<SaleEvent>> activeSales() => _active(_db);
  Future<List<Receipt>> receipts() async => (await _db.query(
    'receipts',
    orderBy: 'number DESC',
  )).map(Receipt.fromMap).toList();
  Future<List<SaleEvent>> events() async => (await _db.query(
    'events',
    orderBy: 'rowid',
  )).map((r) => SaleEvent.fromMap(_decode(r['data']))).toList();
  Future<List<SaleEvent>> pendingEvents() async => (await _db.rawQuery(
    'SELECT e.data FROM events e JOIN outbox o ON e.id=o.eventId WHERE o.acknowledged=0 ORDER BY e.rowid',
  )).map((r) => SaleEvent.fromMap(_decode(r['data']))).toList();
  Future<void> acknowledgeEvents(List<String> ids) =>
      _db.transaction((tx) async {
        for (final id in ids) {
          await tx.update(
            'outbox',
            {'acknowledged': 1, 'error': null},
            where: 'eventId = ?',
            whereArgs: [id],
          );
        }
      });
  Future<void> recordSyncFailure(List<String> ids, String error) =>
      _db.transaction((tx) async {
        for (final id in ids) {
          await tx.update(
            'outbox',
            {'error': error},
            where: 'eventId = ?',
            whereArgs: [id],
          );
        }
      });
  Future<Object?> setting(String key) async {
    if (key == 'heldPaymentInput' || key == 'heldDraftCustomerNumber') {
      final drafts = await _draftRows(_db);
      return drafts.isEmpty
          ? null
          : drafts.first[key == 'heldPaymentInput' ? 'paymentInput' : 'number'];
    }
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : jsonDecode(rows.single['value'] as String);
  }

  Future<void> setSettings(Map<String, Object?> values) =>
      _db.transaction((tx) async {
        if (values.containsKey('session')) {
          throw ArgumentError('Sitzung ist unveränderlich.');
        }
        for (final entry in values.entries) {
          await tx.insert('settings', {
            'key': entry.key,
            'value': jsonEncode(entry.value),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
  Future<void> setSetting(String key, Object? value) async {
    if (key == 'session') throw ArgumentError('Sitzung ist unveränderlich.');
    await _db.insert('settings', {
      'key': key,
      'value': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Map<String, Object?>>> reconciliationStates() async => {
    for (final r in await _db.query('reconciliation'))
      r['listingId'] as String: _decode(r['data']),
  };
  Future<void> saveReconciliation(Map<String, Map<String, Object?>> states) =>
      _db.transaction((tx) async {
        for (final entry in states.entries) {
          await tx.insert('reconciliation', {
            'listingId': entry.key,
            'data': jsonEncode(entry.value),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
  String? loggingFailure;
  Future<void> log(
    String category,
    String message, {
    String level = 'INFO',
  }) async {
    try {
      const ranks = {'DEBUG': 0, 'INFO': 1, 'WARNING': 2, 'ERROR': 3};
      if (!ranks.containsKey(level)) return;
      final raw = await setting('uiSettings');
      final config = raw is Map ? raw : {};
      final accepted = config['logCategories'] is List
          ? (config['logCategories'] as List).whereType<String>().toSet()
          : {'scanner', 'sync', 'io'};
      final mapped = category == 'import' ? 'io' : category;
      if (!{'scanner', 'sync', 'io'}.contains(mapped) ||
          !accepted.contains(mapped) ||
          ranks[level]! < (ranks[config['logLevel']] ?? 1)) {
        return;
      }
      final safe = message
          .replaceAll(
            RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
            'Bearer [redigiert]',
          )
          .replaceAllMapped(
            RegExp(
              r'(password|passwort|token|authorization)\s*[:=]\s*[^\s,;]+',
              caseSensitive: false,
            ),
            (m) => '${m[1]}=[redigiert]',
          );
      final days =
          (config['logRetentionDays'] is int
                  ? config['logRetentionDays'] as int
                  : 14)
              .clamp(1, 365);
      final maxBytes =
          (config['logMaxBytes'] is int
                  ? config['logMaxBytes'] as int
                  : 1048576)
              .clamp(4096, 10485760);
      final backups =
          (config['logBackups'] is int ? config['logBackups'] as int : 3).clamp(
            1,
            10,
          );
      await _db.transaction((tx) async {
        await tx.insert('logs', {
          'at': DateTime.now().toUtc().toIso8601String(),
          'category': mapped,
          'message': safe,
          'level': level,
        });
        await tx.delete(
          'logs',
          where: 'at < ?',
          whereArgs: [
            DateTime.now()
                .toUtc()
                .subtract(Duration(days: days))
                .toIso8601String(),
          ],
        );
        var used = 0;
        for (final row in await tx.query('logs', orderBy: 'sequence DESC')) {
          used += utf8.encode(jsonEncode(row)).length;
          if (used > maxBytes * (backups + 1)) {
            await tx.delete(
              'logs',
              where: 'sequence <= ?',
              whereArgs: [row['sequence']],
            );
            break;
          }
        }
      });
      loggingFailure = null;
    } catch (e) {
      loggingFailure = 'Diagnose konnte nicht gespeichert werden: $e';
    }
  }

  Future<List<Map<String, Object?>>> logs() =>
      _db.query('logs', orderBy: 'sequence DESC');
  Future<Map<String, Object?>> backup() => _db.transaction(
    (tx) async => {
      'appSchema': 2,
      'session': session.toMap(),
      for (final table in [
        'listings',
        'cart',
        'receipts',
        'events',
        'outbox',
        'reconciliation',
        'settings',
      ])
        table: table == 'settings'
            ? [
                for (final row in await tx.query('settings', columns: ['key']))
                  {
                    'key': row['key'],
                    'value': await readLargeText(
                      tx,
                      'settings',
                      'value',
                      'key = ?',
                      [row['key']],
                    ),
                  },
              ]
            : await tx.query(table),
    },
  );
  Future<void> restoreBackup(Map<String, Object?> backup) => _db.transaction((
    tx,
  ) async {
    if (backup['appSchema'] != 2 ||
        backup['session'] is! Map ||
        jsonEncode(
              DesktopDraft.compactSession(
                MarketSession.fromMap(
                  Map<String, Object?>.from(backup['session'] as Map),
                ),
              ).toMap(),
            ) !=
            jsonEncode(session.toMap())) {
      throw const FormatException('Sicherung passt nicht zur Kassensitzung.');
    }
    if ((await tx.query('events')).isNotEmpty ||
        (await tx.query('cart')).isNotEmpty ||
        (await _heldRows(tx)).isNotEmpty) {
      throw StateError('Wiederherstellung nur in eine leere Kasse.');
    }
    for (final table in [
      'listings',
      'receipts',
      'reconciliation',
      'settings',
    ]) {
      await tx.delete(table);
    }
    for (final table in [
      'listings',
      'receipts',
      'events',
      'cart',
      'outbox',
      'reconciliation',
      'settings',
    ]) {
      final rows = backup[table];
      if (rows is! List) {
        throw const FormatException('Sicherung ist unvollständig.');
      }
      for (final raw in rows) {
        final row = Map<String, Object?>.from(raw as Map);
        if (table == 'cart') row['entryId'] ??= row['listingId'];
        // Same identity as checked above, stored in the compact form.
        if (table == 'settings' && row['key'] == 'session') {
          row['value'] = jsonEncode(session.toMap());
        }
        if (table == 'settings' && row['key'] == 'heldCart') {
          final held = jsonDecode(row['value'] as String) as List;
          row['value'] = jsonEncode(
            held
                .map(
                  (r) => {
                    ...Map<String, Object?>.from(r as Map),
                    'entryId': r['entryId'] ?? r['listingId'],
                  },
                )
                .toList(),
          );
        }
        if (table == 'receipts' && row['customerNumber'] == null) {
          final linked = (backup['events'] as List)
              .map((e) => _decode((e as Map)['data']))
              .where((e) => e['receiptId'] == row['id'])
              .map((e) => e['customerNumber'])
              .whereType<int>()
              .toSet();
          if (linked.length > 1) {
            throw const FormatException(
              'Widersprüchliche Kundennummern in Sicherung.',
            );
          }
          row['customerNumber'] = linked.isEmpty
              ? row['number']
              : linked.single;
        }
        if (table == 'listings') {
          _validateListing(
            ArticleListing.fromMap(_decode(row['data'])),
            session,
          );
        }
        await tx.insert(table, row);
      }
    }
    final restored = await tx.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['session'],
    );
    if (restored.length != 1 ||
        jsonEncode(_decode(restored.single['value'])) !=
            jsonEncode(session.toMap())) {
      throw const FormatException(
        'Ungültiger Sitzungskontext in der Sicherung.',
      );
    }
    await _migrateDrafts(tx, session);
    await _validateState(tx, session);
  });

  /// Import preserves immutable IDs; divergent duplicates abort the entire batch.
  Future<void> importEvents(
    List<SaleEvent> imported, {
    Map<String, Map<String, Object?>> reconciliation = const {},
    List<Map<String, Object?>> sources = const [],
  }) => _db.transaction((tx) async {
    await _importEvents(tx, imported, reconciliation);
    await _recordSources(tx, sources);
  });

  Future<void> importEventsAndDraft(
    List<SaleEvent> imported,
    DesktopDraft draft, {
    Map<String, Map<String, Object?>> reconciliation = const {},
    List<Map<String, Object?>> sources = const [],
  }) => _db.transaction((tx) async {
    await _importEvents(tx, imported, reconciliation);
    await _recordSources(tx, sources);
    final validated = DesktopDraft.decode(
      draft.raw,
      session: session,
      catalog: (await tx.query(
        'listings',
      )).map((r) => ArticleListing.fromMap(_decode(r['data']))).toList(),
      committedEvents: (await tx.query(
        'events',
      )).map((r) => SaleEvent.fromMap(_decode(r['data']))).toList(),
      exportBody: session.metadata,
    )!;
    for (final position in validated.positions) {
      await tx.insert('cart', {
        'entryId': _uuid.v7(),
        'listingId': position.listing.listingId,
        'data': jsonEncode(position.listing.toMap()),
        'inputMethod': 'desktop-draft',
        'cancelOf': position.isReturn
            ? position.originalEventId ?? position.pendingEventId
            : null,
        'pendingEventId': position.isReturn
            ? _uuid.v7()
            : position.pendingEventId,
      });
    }
    await tx.insert('settings', {
      'key': 'draftCustomerNumber',
      'value': jsonEncode(validated.customerNumber),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await tx.insert('settings', {
      'key': 'importedDraftEvidence',
      'value': jsonEncode(validated.raw),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final exported = await _exportedNumbers(tx);
    for (final row in await tx.query('cart')) {
      exported[row['pendingEventId'] as String] = validated.customerNumber;
    }
    await _writeSetting(tx, 'exportedDraftNumbers', exported);
    await _validateState(tx, session);
  });

  Future<void> _recordSources(
    DatabaseExecutor tx,
    List<Map<String, Object?>> sources,
  ) async {
    if (sources.isEmpty) return;
    final rows = await tx.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['consolidationSources'],
    );
    final history = rows.isEmpty
        ? <Object?>[]
        : List<Object?>.from(
            jsonDecode(rows.single['value'] as String) as List,
          );
    history.addAll(sources);
    await tx.insert('settings', {
      'key': 'consolidationSources',
      'value': jsonEncode(history),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _importEvents(
    DatabaseExecutor tx,
    List<SaleEvent> imported,
    Map<String, Map<String, Object?>> reconciliation,
  ) async {
    if ((await tx.query('cart')).isNotEmpty ||
        (await _heldRows(tx)).isNotEmpty) {
      throw StateError('Vor dem Import Warenkorb abschließen.');
    }
    final existing = {
      for (final row in await tx.query('events'))
        row['id'] as String: SaleEvent.fromMap(_decode(row['data'])),
    };
    final fresh = <SaleEvent>[];
    for (final event in imported) {
      if (event.listing.marketId != session.marketId ||
          event.listing.exportGeneration != session.exportGeneration ||
          event.registerNumber < 1 ||
          event.listing.priceCents < 0 ||
          DateTime.tryParse(event.occurredAt) == null) {
        throw const FormatException('Ungültiger Marktkontext im Kassenarchiv.');
      }
      final previous = existing[event.id];
      if (previous != null) {
        if (_eventIdentity(previous) != _eventIdentity(event)) {
          throw StateError('Abweichende Daten für Vorgang ${event.id}.');
        }
        continue;
      }
      existing[event.id] = event;
      fresh.add(event);
    }
    final canceled = <String>{};
    for (final e in existing.values.where((e) => e.cancelOf != null)) {
      final original = existing[e.cancelOf];
      if (original == null ||
          original.cancelOf != null ||
          original.listing.listingId != e.listing.listingId ||
          original.listing.priceCents != e.listing.priceCents ||
          !canceled.add(original.id)) {
        throw StateError('Ungültiger oder doppelter Storno im Archiv.');
      }
    }
    final receiptRows = await tx.query('receipts');
    final receiptsByCustomer = <String, Map<String, Object?>>{};
    for (final row in receiptRows) {
      final key = '${row['registerNumber']}:${row['customerNumber']}';
      if (receiptsByCustomer.containsKey(key)) {
        throw const FormatException('Mehrdeutige Kassen-/Kundenzuordnung.');
      }
      receiptsByCustomer[key] = row;
    }
    final groups = <String, List<SaleEvent>>{};
    for (final e in fresh) {
      groups
          .putIfAbsent('${e.registerNumber}:${e.customerNumber}', () => [])
          .add(e);
    }
    final receiptIds = <String, String>{};
    for (final group in groups.entries) {
      final savedReceipt = receiptsByCustomer[group.key];
      if (savedReceipt != null) {
        if (group.value.any((e) => e.cancelOf == null)) {
          throw StateError(
            'Abgeschlossener Kunde darf nicht um neue Verkäufe erweitert werden.',
          );
        }
        for (final e in group.value) {
          final original = existing[e.cancelOf]!;
          if ('${original.registerNumber}:${original.customerNumber}' !=
              group.key) {
            throw StateError('Rückgabe benötigt einen eigenen Kundenbeleg.');
          }
        }
        receiptIds[group.key] = savedReceipt['id'] as String;
      } else {
        final proposed = group.value.first.receiptId;
        if (group.value.any((e) => e.receiptId != proposed) ||
            receiptRows.any((r) => r['id'] == proposed) ||
            receiptIds.values.contains(proposed)) {
          throw StateError('Beleg-ID gehört zu unterschiedlichen Kunden.');
        }
        receiptIds[group.key] = proposed;
        final total = group.value.fold(0, (sum, e) {
          if (e.cancelOf != null) {
            final original = existing[e.cancelOf]!;
            if ('${original.registerNumber}:${original.customerNumber}' ==
                group.key) {
              return sum;
            }
          }
          return sum + e.listing.priceCents * (e.cancelOf == null ? 1 : -1);
        });
        await tx.insert('receipts', {
          'id': proposed,
          'occurredAt': group.value.first.occurredAt,
          'totalCents': total,
          'tenderedCents': total < 0 ? 0 : total,
          'tenderedKnown': 0,
          'registerNumber': group.value.first.registerNumber,
          'customerNumber': group.value.first.customerNumber,
        });
      }
    }
    // Foreign-key originals must be inserted before their cancellations.
    for (final e in [
      ...fresh.where((e) => e.cancelOf == null),
      ...fresh.where((e) => e.cancelOf != null),
    ]) {
      await _insertEvent(
        tx,
        SaleEvent.fromMap({
          ...e.toMap(),
          'receiptId': receiptIds['${e.registerNumber}:${e.customerNumber}'],
        }),
      );
    }
    for (final entry in reconciliation.entries) {
      await tx.insert('reconciliation', {
        'listingId': entry.key,
        'data': jsonEncode(entry.value),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await _validateState(tx, session);
  }

  /// Compatibility aggregate for guards, counts and older callers.
  Future<List<CartEntry>> heldCart() async =>
      (await _heldRows(_db)).map(_entry).toList();

  Future<List<ParkedDraft>> parkedDrafts() async => (await _draftRows(_db))
      .map(
        (d) => ParkedDraft(
          id: d['id'] as String,
          number: d['number'] as int,
          entries: _positions(d).map(_entry).toList(),
          paymentInput: d['paymentInput'] as String?,
        ),
      )
      .toList();

  Future<int> activeDraftNumber() => _db.transaction(
    (tx) async =>
        await _readSetting(tx, 'draftCustomerNumber') as int? ??
        await _nextNumber(tx, session),
  );

  Future<void> _parkCurrent(
    DatabaseExecutor tx,
    List<Map<String, Object?>> drafts,
  ) async {
    final current = await tx.query('cart', orderBy: 'rowid');
    if (current.isNotEmpty) {
      drafts.add({
        'id': _uuid.v7(),
        'number': await _ensureNumber(tx, session),
        'rows': current,
        'paymentInput': await _readSetting(tx, 'draftPaymentInput'),
      });
    }
    await tx.delete('cart');
    await tx.delete(
      'settings',
      where: 'key IN (?, ?)',
      whereArgs: ['draftCustomerNumber', 'draftPaymentInput'],
    );
  }

  Future<void> parkCart() => _db.transaction((tx) async {
    final drafts = await _draftRows(tx);
    await _parkCurrent(tx, drafts);
    await _writeSetting(tx, 'parkedDrafts', drafts);
  });

  Future<void> _resumeDraft(DatabaseExecutor tx, String id) async {
    final drafts = await _draftRows(tx);
    final index = drafts.indexWhere((d) => d['id'] == id);
    if (index < 0) throw StateError('Geparkter Vorgang wurde nicht gefunden.');
    final selected = drafts.removeAt(index);
    await _parkCurrent(tx, drafts);
    for (final row in _positions(selected)) {
      await tx.insert('cart', row);
    }
    await _writeSetting(tx, 'draftCustomerNumber', selected['number']);
    if (selected['paymentInput'] != null) {
      await _writeSetting(tx, 'draftPaymentInput', selected['paymentInput']);
    }
    await _writeSetting(tx, 'parkedDrafts', drafts);
  }

  Future<void> resumeDraft(String id) =>
      _db.transaction((tx) => _resumeDraft(tx, id));

  /// Legacy two-cart interaction; the UI uses the explicit dynamic operations.
  Future<void> swapCustomer() => _db.transaction((tx) async {
    final drafts = await _draftRows(tx);
    if (drafts.isNotEmpty) {
      await _resumeDraft(tx, drafts.first['id'] as String);
    } else {
      await _parkCurrent(tx, drafts);
      await _writeSetting(tx, 'parkedDrafts', drafts);
    }
  });
  static String _stableJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${_stableJson(value[k])}').join(',')}}';
    }
    if (value is List) return '[${value.map(_stableJson).join(',')}]';
    return jsonEncode(value);
  }

  static Future<void> _validateState(
    DatabaseExecutor db,
    MarketSession session,
  ) async {
    await _exportedNumbers(db);
    final catalog = <String, ArticleListing>{};
    for (final row in await db.query('listings')) {
      final listing = ArticleListing.fromMap(_decode(row['data']));
      _validateListing(listing, session);
      if (row['id'] != listing.listingId) {
        throw const FormatException('Beschädigter Artikelindex.');
      }
      catalog[listing.listingId] = listing;
    }
    final events = <String, SaleEvent>{};
    for (final row in await db.query('events')) {
      final event = SaleEvent.fromMap(_decode(row['data']));
      if (row['id'] != event.id ||
          row['receiptId'] != event.receiptId ||
          row['listingId'] != event.listing.listingId ||
          row['cancelOf'] != event.cancelOf ||
          event.listing.marketId != session.marketId ||
          event.listing.exportGeneration != session.exportGeneration ||
          event.listing.priceCents < 0 ||
          event.registerNumber < 1 ||
          DateTime.tryParse(event.occurredAt) == null) {
        throw const FormatException('Beschädigter Verkaufskontext.');
      }
      events[event.id] = event;
    }
    final receipts = <String, Map<String, Object?>>{};
    final customers = <String>{};
    for (final row in await db.query('receipts')) {
      final receipt = Receipt.fromMap(row);
      if (receipt.customerNumber < 0 ||
          receipt.registerNumber < 1 ||
          receipt.tenderedCents < 0 ||
          receipt.tenderedCents < receipt.totalCents ||
          DateTime.tryParse(receipt.occurredAt) == null ||
          !customers.add(
            '${receipt.registerNumber}:${receipt.customerNumber}',
          )) {
        throw const FormatException('Beschädigter Kundenbeleg.');
      }
      receipts[receipt.id] = row;
    }
    final sums = <String, int>{};
    final sameReceiptRefunds = <String, int>{};
    final usedReceipts = <String>{};
    for (final event in events.values) {
      final receipt = receipts[event.receiptId];
      if (receipt == null ||
          receipt['registerNumber'] != event.registerNumber ||
          receipt['customerNumber'] != event.customerNumber) {
        throw const FormatException(
          'Verkauf und Kundenbeleg stimmen nicht überein.',
        );
      }
      usedReceipts.add(event.receiptId);
      final original = events[event.cancelOf];
      // Older mobile/desktop direct cancellations reference the original
      // immutable receipt. They change stock, not its historic printed total.
      if (event.cancelOf != null && original?.receiptId == event.receiptId) {
        sameReceiptRefunds[event.receiptId] =
            (sameReceiptRefunds[event.receiptId] ?? 0) +
            event.listing.priceCents;
        continue;
      }
      sums[event.receiptId] =
          (sums[event.receiptId] ?? 0) +
          event.listing.priceCents * (event.cancelOf == null ? 1 : -1);
    }
    for (final entry in receipts.entries) {
      if (!usedReceipts.contains(entry.key) ||
          (entry.value['totalCents'] != (sums[entry.key] ?? 0) &&
              entry.value['totalCents'] !=
                  (sums[entry.key] ?? 0) -
                      (sameReceiptRefunds[entry.key] ?? 0))) {
        throw const FormatException(
          'Belegsumme stimmt nicht mit gespeicherten Positionen überein.',
        );
      }
    }
    for (final event in events.values.where((e) => e.cancelOf != null)) {
      final original = events[event.cancelOf];
      if (original == null ||
          original.cancelOf != null ||
          original.listing.listingId != event.listing.listingId ||
          original.listing.priceCents != event.listing.priceCents) {
        throw const FormatException('Ungültiger Stornoverweis.');
      }
    }
    final drafts = await _draftRows(db);
    final draftIds = <String>{};
    final draftNumbers = <int>{};
    final activeNumber = await _readSetting(db, 'draftCustomerNumber');
    void checkNumber(Object? number) {
      if (number is! int ||
          number < 1 ||
          !draftNumbers.add(number) ||
          customers.contains('${session.registerNumber}:$number')) {
        throw const FormatException(
          'Vorgangsnummer ist beschädigt oder bereits vergeben.',
        );
      }
    }

    if (activeNumber != null) checkNumber(activeNumber);
    for (final draft in drafts) {
      if (draft['id'] is! String ||
          !draftIds.add(draft['id'] as String) ||
          draft['rows'] is! List ||
          (draft['rows'] as List).isEmpty ||
          (draft['paymentInput'] != null && draft['paymentInput'] is! String)) {
        throw const FormatException('Geparkter Vorgang ist beschädigt.');
      }
      checkNumber(draft['number']);
    }
    final baskets = [await db.query('cart'), ...drafts.map(_positions)];
    final acrossBaskets = <String>{},
        entryIds = <String>{},
        pendingIds = <String>{};
    final canceled = events.values
        .map((e) => e.cancelOf)
        .whereType<String>()
        .toSet();
    for (final rows in baskets) {
      final localListings = <String>{};
      final pending = <String, ArticleListing>{};
      final returns = <String>{};
      for (final row in [
        ...rows.where((r) => r['cancelOf'] == null),
        ...rows.where((r) => r['cancelOf'] != null),
      ]) {
        final item = ArticleListing.fromMap(_decode(row['data']));
        final entryId = row['entryId'], pendingId = row['pendingEventId'];
        if (entryId is! String ||
            !entryIds.add(entryId) ||
            row['listingId'] != item.listingId ||
            item.marketId != session.marketId ||
            item.exportGeneration != session.exportGeneration ||
            acrossBaskets.contains(item.listingId)) {
          throw const FormatException('Warenkorb ist beschädigt oder fremd.');
        }
        if (pendingId != null &&
            (pendingId is! String ||
                events.containsKey(pendingId) ||
                !pendingIds.add(pendingId))) {
          throw const FormatException('Doppelte vorgemerkte Vorgangs-ID.');
        }
        localListings.add(item.listingId);
        final cancel = row['cancelOf'];
        if (cancel == null) {
          final stored = catalog[item.listingId];
          if (stored == null ||
              _stableJson(stored.toMap()) != _stableJson(item.toMap()) ||
              pending.values.any((p) => p.listingId == item.listingId) ||
              events.values.any(
                (e) =>
                    e.cancelOf == null &&
                    !canceled.contains(e.id) &&
                    e.listing.listingId == item.listingId,
              )) {
            throw const FormatException(
              'Warenkorb passt nicht zum aktuellen Artikelstand.',
            );
          }
          pending[pendingId as String? ?? entryId] = item;
        } else {
          final original = events[cancel];
          final originalListing = original?.listing ?? pending[cancel];
          if (!returns.add(cancel as String) ||
              original?.cancelOf != null ||
              canceled.contains(cancel) ||
              originalListing == null ||
              originalListing.listingId != item.listingId ||
              originalListing.priceCents != item.priceCents) {
            throw const FormatException(
              'Rückgabeentwurf hat kein gültiges Original.',
            );
          }
        }
      }
      acrossBaskets.addAll(localListings);
    }
    if ((await db.rawQuery(
      'SELECT id FROM events WHERE id NOT IN (SELECT eventId FROM outbox)',
    )).isNotEmpty) {
      throw const FormatException('Upload-Warteschlange ist unvollständig.');
    }
  }

  static Future<int> _highestCommittedNumber(
    DatabaseExecutor tx,
    MarketSession session,
  ) async {
    final rows = await tx.rawQuery(
      'SELECT MAX(customerNumber) AS number FROM receipts WHERE registerNumber = ?',
      [session.registerNumber],
    );
    return rows.single['number'] as int? ?? 0;
  }

  static Future<Map<String, int>> _exportedNumbers(DatabaseExecutor db) async {
    final raw = await _readSetting(db, 'exportedDraftNumbers');
    if (raw == null) return {};
    if (raw is! Map ||
        raw.entries.any(
          (e) => e.key is! String || e.value is! int || (e.value as int) < 1,
        )) {
      throw const FormatException(
        'Exportierte Vorgangsnummern sind beschädigt.',
      );
    }
    return Map<String, int>.from(raw);
  }

  static Future<void> _checkExportNumber(
    DatabaseExecutor db,
    List<Map<String, Object?>> rows,
    int number,
  ) async {
    final exported = await _exportedNumbers(db);
    if (rows.any(
      (row) =>
          exported[row['pendingEventId']] != null &&
          exported[row['pendingEventId']] != number,
    )) {
      throw StateError(
        'Dieser Vorgang wurde bereits mit einer anderen Nummer exportiert. Eine erneute Desktop-Übergabe ist nach neueren Abschlüssen nicht möglich. Den bisherigen Export verwenden oder den Vorgang hier abschließen.',
      );
    }
  }

  /// Read-only preview; export rechecks in its transaction before changing data.
  Future<int?> desktopDraftExportNumber({String? draftId}) =>
      _db.transaction((tx) async {
        int number;
        List<Map<String, Object?>> rows;
        if (draftId == null) {
          rows = await tx.query('cart');
          if (rows.isEmpty) return null;
          number =
              await _readSetting(tx, 'draftCustomerNumber') as int? ??
              await _nextNumber(tx, session);
        } else {
          final matches = (await _draftRows(
            tx,
          )).where((d) => d['id'] == draftId).toList();
          if (matches.isEmpty) {
            throw StateError('Geparkter Vorgang wurde nicht gefunden.');
          }
          number = matches.single['number'] as int;
          rows = _positions(matches.single);
        }
        final proposed = number <= await _highestCommittedNumber(tx, session)
            ? await _nextNumber(tx, session)
            : number;
        await _checkExportNumber(tx, rows, proposed);
        return proposed;
      });

  Future<Map<String, Object?>?> exportDesktopDraft({
    bool held = false,
    String? draftId,
  }) => _db.transaction((tx) async {
    final drafts = await _draftRows(tx);
    Map<String, Object?>? selected;
    if (draftId != null) {
      final matches = drafts.where((d) => d['id'] == draftId).toList();
      if (matches.isEmpty) {
        throw StateError('Geparkter Vorgang wurde nicht gefunden.');
      }
      selected = matches.single;
    } else if (held) {
      if (drafts.isEmpty) return null;
      selected = drafts.first;
    }
    final rows = selected != null
        ? _positions(selected)
        : (await tx.query(
            'cart',
            orderBy: 'rowid',
          )).map((r) => Map<String, Object?>.from(r)).toList();
    if (rows.isEmpty) return null;
    for (final row in rows) {
      row['pendingEventId'] ??= _uuid.v7();
      if (selected == null) {
        await tx.update(
          'cart',
          {'pendingEventId': row['pendingEventId']},
          where: 'entryId = ?',
          whereArgs: [row['entryId']],
        );
      }
    }
    var customer = selected != null
        ? selected['number'] as int
        : await _ensureNumber(tx, session);
    // The desktop recovery format requires a number above all completed
    // checkouts. Persist the same number locally to keep event identities
    // identical if this draft is completed on either platform later.
    if (customer <= await _highestCommittedNumber(tx, session)) {
      customer = await _allocateNumber(tx, session);
      if (selected == null) {
        await _writeSetting(tx, 'draftCustomerNumber', customer);
      }
    }
    if (selected != null) {
      selected['rows'] = rows;
      selected['number'] = customer;
      await _writeSetting(tx, 'parkedDrafts', drafts);
    }
    await _checkExportNumber(tx, rows, customer);
    final exported = await _exportedNumbers(tx);
    for (final row in rows) {
      exported[row['pendingEventId'] as String] = customer;
    }
    await _writeSetting(tx, 'exportedDraftNumbers', exported);
    return DesktopDraft.encode(
      session: session,
      positions: rows
          .map(
            (r) => CartEntry(
              entryId: r['entryId'] as String,
              pendingEventId: r['pendingEventId'] as String?,
              listing: ArticleListing.fromMap(_decode(r['data'])),
              inputMethod: r['inputMethod'] as String,
              cancelOf: r['cancelOf'] as String?,
            ),
          )
          .toList(),
      customerNumber: customer,
      exportBody: session.metadata,
      occurredAt: DateTime.now().toUtc().toIso8601String(),
    );
  });
  Future<void> close() => _db.close();
}
