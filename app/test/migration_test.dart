import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/data/demo_catalog.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test(
    'v1 installed database migrates receipts, immutable events and open draft',
    () async {
      final dir = await Directory.systemTemp.createTemp('migrate_mobile_');
      final path = '${dir.path}/old.db';
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            const snapshot =
                'listingId TEXT,articleId TEXT,codeFull TEXT,title TEXT,priceCents INTEGER,labelRevision INTEGER,exportGeneration INTEGER,boxNumber INTEGER,marketId TEXT';
            await db.execute(
              'CREATE TABLE listings ($snapshot,PRIMARY KEY(listingId))',
            );
            await db.execute(
              'CREATE TABLE cart (listingId TEXT PRIMARY KEY,inputMethod TEXT)',
            );
            await db.execute(
              'CREATE TABLE receipts (number INTEGER PRIMARY KEY,id TEXT UNIQUE,occurredAt TEXT,totalCents INTEGER,tenderedCents INTEGER)',
            );
            await db.execute(
              'CREATE TABLE events (id TEXT PRIMARY KEY,receiptId TEXT,occurredAt TEXT,registerNumber INTEGER,inputMethod TEXT,cancelOf TEXT,$snapshot)',
            );
            await db.execute(
              'CREATE TABLE active_sales (listingId TEXT PRIMARY KEY,eventId TEXT)',
            );
            for (final item in demoCatalog) {
              final row = item.toMap()
                ..removeWhere(
                  (key, _) => [
                    'legacyArticleNumber',
                    'size',
                    'fieldsJson',
                    'unexpected',
                  ].contains(key),
                );
              await db.insert('listings', row);
            }
            await db.insert('receipts', {
              'number': 4,
              'id': 'old-receipt',
              'occurredAt': '2026-09-26T12:00:00Z',
              'totalCents': 250,
              'tenderedCents': 500,
            });
            final row = demoCatalog.first.toMap()
              ..removeWhere(
                (key, _) => [
                  'legacyArticleNumber',
                  'size',
                  'fieldsJson',
                  'unexpected',
                ].contains(key),
              );
            await db.insert('events', {
              ...row,
              'id': 'old-sale',
              'receiptId': 'old-receipt',
              'occurredAt': '2026-09-26T12:00:00Z',
              'registerNumber': 1,
              'inputMethod': 'scan',
              'cancelOf': null,
            });
            await db.insert('active_sales', {
              'listingId': demoCatalog.first.listingId,
              'eventId': 'old-sale',
            });
            await db.insert('cart', {
              'listingId': demoCatalog.last.listingId,
              'inputMethod': 'manual',
            });
          },
        ),
      );
      await db.close();
      final store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect((await store.events()).single.id, 'old-sale');
      expect((await store.events()).single.customerNumber, 4);
      expect((await store.receipts()).single.tenderedCents, 500);
      expect((await store.cart()).single.listingId, demoCatalog.last.listingId);
      await store.remove(demoCatalog.last.listingId);
      await store.addManual(demoCatalog.last.codeFull, 1);
      final receipt = await store.checkout(1000);
      expect(receipt.number, 5);
      await store.close();
      await dir.delete(recursive: true);
    },
  );
}
