import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../domain/models.dart';
import '../services/desktop_draft.dart';
import 'checkout_store.dart';
import 'large_text.dart';
import 'market_package.dart';

class SavedSession {
  final String id;
  final MarketSession session;
  final String? error;
  const SavedSession(this.id, this.session, {this.error});
}

/// Registry and original imports remain durable independently of an open cash desk.
class MarketLibrary {
  final Database _db;
  final DatabaseFactory factory;
  final String directory;
  CheckoutStore? _active;
  String? _activeId;
  MarketLibrary._(this._db, this.factory, this.directory);
  CheckoutStore? get active => _active;
  String? get activeId => _activeId;
  static Future<MarketLibrary> open({
    required DatabaseFactory factory,
    required String directory,
  }) async {
    await Directory(directory).create(recursive: true);
    final db = await factory.openDatabase(
      p.join(directory, 'library.db'),
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: (db, old, version) async {
          await db.execute('ALTER TABLE sessions ADD COLUMN sourceHash TEXT');
          for (final row in await db.query('sessions')) {
            await db.update(
              'sessions',
              {
                'sourceHash': sha256
                    .convert(utf8.encode(row['source'] as String))
                    .toString(),
              },
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        },
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE sessions (id TEXT PRIMARY KEY, data TEXT NOT NULL, source TEXT NOT NULL, sourceHash TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    return MarketLibrary._(db, factory, directory);
  }

  Future<List<SavedSession>> sessions({bool validate = false}) async {
    final result = <SavedSession>[];
    // Never SELECT *: data/source may exceed Android's CursorWindow.
    final ids = await _db.query(
      'sessions',
      columns: ['id'],
      orderBy: 'rowid DESC',
    );
    for (final row in ids) {
      final id = row['id'] as String;
      MarketSession? session;
      try {
        final full = MarketSession.fromMap(
          Map<String, Object?>.from(
            jsonDecode(
                  (await readLargeText(_db, 'sessions', 'data', 'id = ?', [
                    id,
                  ]))!,
                )
                as Map,
          ),
        );
        session = DesktopDraft.compactSession(full);
        if (!identical(session, full)) {
          await _db.update(
            'sessions',
            {'data': jsonEncode(session.toMap())},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        if (validate) {
          await source(id);
          if (!await factory.databaseExists(_path(id))) {
            throw StateError('Kassendatei fehlt. Sicherung wiederherstellen.');
          }
          if (_activeId != id) {
            final checked = await CheckoutStore.open(
              factory: factory,
              path: _path(id),
              session: session,
              requireExisting: true,
            );
            await checked.close();
          }
        }
        result.add(SavedSession(id, session));
      } catch (e) {
        result.add(
          SavedSession(
            id,
            session ??
                MarketSession(
                  marketId: 'invalid',
                  name: 'Beschädigter Markteintrag',
                  registerNumber: 1,
                  exportGeneration: 0,
                ),
            error: e.toString(),
          ),
        );
      }
    }
    return result;
  }

  Future<String> source(String id) async {
    final rows = await _db.query(
      'sessions',
      columns: ['sourceHash'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.length != 1) throw StateError('Kasse nicht gefunden.');
    final source = (await readLargeText(_db, 'sessions', 'source', 'id = ?', [
      id,
    ]))!;
    if (sha256.convert(utf8.encode(source)).toString() !=
        rows.single['sourceHash']) {
      throw const FormatException('Gespeicherte Importquelle ist beschädigt.');
    }
    return source;
  }

  /// Inspect an archived cash desk without changing the active market or drafts.
  Future<T> withSession<T>(
    String id,
    Future<T> Function(CheckoutStore) action,
  ) async {
    if (_activeId == id && _active != null) return action(_active!);
    final saved = (await sessions()).singleWhere((s) => s.id == id);
    if (saved.error != null) throw StateError(saved.error!);
    await source(id);
    final store = await CheckoutStore.open(
      factory: factory,
      path: _path(id),
      session: saved.session,
      requireExisting: true,
    );
    try {
      return await action(store);
    } finally {
      await store.close();
    }
  }

  Future<SavedSession> importPackage(
    MarketPackage package, {
    required String originalSource,
  }) =>
      createSession(package.session, package.listings, source: originalSource);
  Future<SavedSession> createSession(
    MarketSession session,
    List<ArticleListing> listings, {
    required String source,
  }) async {
    session = DesktopDraft.compactSession(session);
    final id = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              session.marketId,
              session.registerNumber,
              session.exportGeneration,
              session.exportChecksum,
            ]),
          ),
        )
        .toString();
    final existing = await _db.query(
      'sessions',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (existing.isNotEmpty) {
      return (await sessions()).singleWhere((s) => s.id == id);
    }
    // Finish creating the cash desk before publishing it in the registry.
    final store = await CheckoutStore.open(
      factory: factory,
      path: _path(id),
      session: session,
      listings: listings,
    );
    await store.close();
    await _db.insert('sessions', {
      'id': id,
      'data': jsonEncode(session.toMap()),
      'source': source,
      'sourceHash': sha256.convert(utf8.encode(source)).toString(),
    });
    return SavedSession(id, session);
  }

  Future<SavedSession> createRegister(String fromId, int number) async {
    if (number < 1 || number > 9999) {
      throw const FormatException(
        'Kassennummer muss zwischen 1 und 9999 liegen.',
      );
    }
    final original = (await sessions())
        .singleWhere((s) => s.id == fromId)
        .session;
    final previous = _activeId == fromId
        ? _active!
        : await CheckoutStore.open(
            factory: factory,
            path: _path(fromId),
            session: original,
            requireExisting: true,
          );
    try {
      final session = MarketSession(
        marketId: original.marketId,
        name: original.name,
        registerNumber: number,
        exportGeneration: original.exportGeneration,
        exportChecksum: original.exportChecksum,
        isDemo: original.isDemo,
        metadata: original.metadata,
      );
      return await createSession(
        session,
        await previous.allListings(),
        source: await source(fromId),
      );
    } finally {
      if (_activeId != fromId) await previous.close();
    }
  }

  String _path(String id) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) {
      throw ArgumentError('Ungültige Sitzungs-ID.');
    }
    return p.join(directory, 'cash_$id.db');
  }

  Future<CheckoutStore> activate(String id) async {
    if (_activeId == id && _active != null) return _active!;
    if (_active != null &&
        ((await _active!.cartLines()).isNotEmpty ||
            (await _active!.heldCart()).isNotEmpty)) {
      throw StateError(
        'Vor dem Kassenwechsel den offenen Warenkorb abschließen oder verwerfen.',
      );
    }
    final matches = (await sessions()).where((s) => s.id == id).toList();
    if (matches.length != 1) throw StateError('Kasse nicht gefunden.');
    if (matches.single.error != null) throw StateError(matches.single.error!);
    await source(id);
    final next = await CheckoutStore.open(
      factory: factory,
      path: _path(id),
      session: matches.single.session,
      requireExisting: true,
    );
    try {
      await setPreference('lastSession', id);
    } catch (_) {
      await next.close();
      rethrow;
    }
    final previous = _active;
    _active = next;
    _activeId = id;
    try {
      await previous?.close();
    } catch (error) {
      await next.log(
        'io',
        'Vorherige Kasse konnte nicht geschlossen werden: $error',
        level: 'WARNING',
      );
    }
    return next;
  }

  Future<Object?> preference(String key) async {
    final rows = await _db.query(
      'preferences',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : jsonDecode(rows.single['value'] as String);
  }

  Future<void> setPreference(String key, Object? value) async {
    await _db.insert('preferences', {
      'key': key,
      'value': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() async {
    await _active?.close();
    await _db.close();
  }
}
