import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../domain/barcode.dart';
import '../domain/models.dart';
import 'demo_catalog.dart';

class CheckoutStore {
  final Database _db;
  static const _uuid = Uuid();
  CheckoutStore._(this._db);

  // Separate demo database; production import/session activation is a later slice.
  static Future<CheckoutStore> open({
    required DatabaseFactory factory,
    required String path,
  }) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA synchronous = FULL');
        },
        onCreate: (db, version) async {
          const snapshot = '''
          listingId TEXT NOT NULL, articleId TEXT NOT NULL, codeFull TEXT NOT NULL,
          title TEXT NOT NULL, priceCents INTEGER NOT NULL CHECK(priceCents >= 0),
          labelRevision INTEGER NOT NULL CHECK(labelRevision > 0),
          exportGeneration INTEGER NOT NULL CHECK(exportGeneration = 1),
          boxNumber INTEGER NOT NULL, marketId TEXT NOT NULL CHECK(marketId = 'demo-market')
        ''';
          await db.execute(
            'CREATE TABLE listings ($snapshot, PRIMARY KEY(listingId), UNIQUE(codeFull))',
          );
          await db.execute('''CREATE TABLE cart (
          listingId TEXT PRIMARY KEY REFERENCES listings(listingId),
          inputMethod TEXT NOT NULL CHECK(inputMethod IN ('scan', 'manual'))
        )''');
          await db.execute('''CREATE TABLE receipts (
          number INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
          occurredAt TEXT NOT NULL, totalCents INTEGER NOT NULL CHECK(totalCents >= 0),
          tenderedCents INTEGER NOT NULL CHECK(tenderedCents >= totalCents)
        )''');
          await db.execute('''CREATE TABLE events (
          id TEXT PRIMARY KEY, receiptId TEXT NOT NULL REFERENCES receipts(id),
          occurredAt TEXT NOT NULL, registerNumber INTEGER NOT NULL CHECK(registerNumber = 1),
          inputMethod TEXT NOT NULL, cancelOf TEXT UNIQUE REFERENCES events(id),
          $snapshot
        )''');
          await db.execute('''CREATE TABLE active_sales (
          listingId TEXT PRIMARY KEY REFERENCES listings(listingId),
          eventId TEXT NOT NULL UNIQUE REFERENCES events(id)
        )''');
          for (final action in ['UPDATE', 'DELETE']) {
            await db.execute('''CREATE TRIGGER events_no_${action.toLowerCase()}
            BEFORE $action ON events BEGIN
            SELECT RAISE(ABORT, 'Sale events are immutable'); END''');
          }
          for (final listing in demoCatalog) {
            LabelCode.manual(listing.codeFull, listing.labelRevision);
            await db.insert('listings', listing.toMap());
          }
        },
      ),
    );
    return CheckoutStore._(db);
  }

  Future<void> addScan(String raw) => _add(LabelCode.parse(raw), 'scan');
  Future<void> addManual(String raw, int revision) =>
      _add(LabelCode.manual(raw, revision), 'manual');

  Future<void> _add(LabelCode label, String inputMethod) =>
      _db.transaction((tx) async {
        final rows = await tx.query(
          'listings',
          where: 'codeFull = ?',
          whereArgs: [label.codeFull],
        );
        if (rows.length != 1) {
          throw StateError('Artikel gehört nicht zu diesem Demomarkt.');
        }
        final listing = ArticleListing.fromMap(rows.single);
        listing.validateLabel(label);
        if ((await tx.query(
          'active_sales',
          where: 'listingId = ?',
          whereArgs: [listing.listingId],
        )).isNotEmpty) {
          throw StateError('Artikel wurde an dieser Kasse bereits verkauft.');
        }
        if ((await tx.query(
          'cart',
          where: 'listingId = ?',
          whereArgs: [listing.listingId],
        )).isNotEmpty) {
          throw StateError('Artikel liegt bereits im Warenkorb.');
        }
        await tx.insert('cart', {
          'listingId': listing.listingId,
          'inputMethod': inputMethod,
        });
      });

  Future<void> remove(String listingId) async {
    await _db.delete('cart', where: 'listingId = ?', whereArgs: [listingId]);
  }

  Future<Receipt> checkout(int tenderedCents) => _db.transaction((tx) async {
    final rows = await tx.rawQuery(
      'SELECT l.*, c.inputMethod FROM cart c JOIN listings l ON l.listingId = c.listingId ORDER BY c.rowid',
    );
    if (rows.isEmpty) throw StateError('Der Warenkorb ist leer.');
    final total = rows.fold(0, (sum, row) => sum + (row['priceCents'] as int));
    if (tenderedCents < total) {
      throw StateError('Der erhaltene Betrag reicht nicht aus.');
    }
    final id = _uuid.v7();
    final occurredAt = DateTime.now().toUtc().toIso8601String();
    final number = await tx.insert('receipts', {
      'id': id,
      'occurredAt': occurredAt,
      'totalCents': total,
      'tenderedCents': tenderedCents,
    });
    for (final row in rows) {
      final eventId = _uuid.v7();
      await tx.insert('events', {
        ...row,
        'id': eventId,
        'receiptId': id,
        'occurredAt': occurredAt,
        'registerNumber': 1,
        'cancelOf': null,
      });
      await tx.insert('active_sales', {
        'listingId': row['listingId'],
        'eventId': eventId,
      });
    }
    await tx.delete('cart');
    return Receipt(
      id: id,
      occurredAt: occurredAt,
      number: number,
      totalCents: total,
      tenderedCents: tenderedCents,
    );
  });

  Future<void> cancel(String saleId) => _db.transaction((tx) async {
    final rows = await tx.query(
      'events',
      where: 'id = ? AND cancelOf IS NULL',
      whereArgs: [saleId],
    );
    if (rows.length != 1) throw StateError('Verkauf wurde nicht gefunden.');
    final active = await tx.query(
      'active_sales',
      where: 'eventId = ?',
      whereArgs: [saleId],
    );
    if (active.isEmpty) {
      throw StateError('Dieser Verkauf ist bereits storniert.');
    }
    await tx.insert('events', {
      ...rows.single,
      'id': _uuid.v7(),
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
      'cancelOf': saleId,
    });
    await tx.delete('active_sales', where: 'eventId = ?', whereArgs: [saleId]);
  });

  Future<List<ArticleListing>> cart() async => (await _db.rawQuery(
    'SELECT l.* FROM cart c JOIN listings l ON l.listingId = c.listingId ORDER BY c.rowid',
  )).map(ArticleListing.fromMap).toList();
  Future<List<Receipt>> receipts() async => (await _db.query(
    'receipts',
    orderBy: 'number DESC',
  )).map(Receipt.fromMap).toList();
  Future<List<SaleEvent>> events() async => (await _db.query(
    'events',
    orderBy: 'rowid',
  )).map(SaleEvent.fromMap).toList();
  Future<void> close() => _db.close();
}
