import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/data/demo_catalog.dart';
import 'package:flohmarkt_mobile/data/large_text.dart';
import 'package:flohmarkt_mobile/data/market_library.dart';
import 'package:flohmarkt_mobile/domain/models.dart';
import 'package:flohmarkt_mobile/services/desktop_draft.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('large TEXT cells are reassembled exactly across slices', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE t (id TEXT, v TEXT)');
    // > 3 slices, multi-byte characters straddle slice borders.
    const chars = ['a', 'ä', '€', '😀'];
    final value = List.generate(900000, (i) => chars[i % 4]).join();
    await db.insert('t', {'id': 'x', 'v': value});
    final read = await readLargeText(db, 't', 'v', 'id = ?', ['x']);
    expect(read == value, isTrue, reason: 'length ${read?.length}');
    expect(await readLargeText(db, 't', 'v', 'id = ?', ['y']), isNull);
    await db.close();
  });

  test('big export body is stored compact with unchanged fingerprint and '
      'legacy oversized rows are compacted on read', () async {
    final body = <String, Object?>{
      'version': '2.0',
      'market': {'id': 7, 'name': 'H26'},
      'articles': [
        for (var i = 0; i < 20000; i++) {'articleId': 'a$i', 'x': 'y' * 40},
      ],
    };
    final full = MarketSession(
      marketId: '7',
      name: 'H26',
      registerNumber: 1,
      exportGeneration: 1,
      exportChecksum: 'c',
      metadata: body,
    );
    final compact = DesktopDraft.compactSession(full);
    expect(compact.metadata.containsKey('articles'), isFalse);
    expect(compact.metadata['market'], body['market']);
    expect(
      DesktopDraft.exportFingerprint(compact.metadata),
      DesktopDraft.exportFingerprint(body),
    );
    expect(identical(DesktopDraft.compactSession(compact), compact), isTrue);
    expect(
      identical(DesktopDraft.compactSession(demoSession), demoSession),
      isTrue,
    );

    final dir = await Directory.systemTemp.createTemp('large_market_');
    final library = await MarketLibrary.open(
      factory: databaseFactoryFfi,
      directory: dir.path,
    );
    final saved = await library.createSession(
      full,
      demoCatalog
          .map(
            (l) => ArticleListing.fromMap({
              ...l.toMap(),
              'marketId': '7',
              'exportGeneration': 1,
            }),
          )
          .toList(),
      source: 'x' * 3000000,
    );
    final store = await library.activate(saved.id);
    expect(store.session.metadata.containsKey('articles'), isFalse);
    expect((await library.source(saved.id)).length, 3000000);
    await library.close();

    // Installations from before the fix hold the full body in both rows.
    final fullJson = jsonEncode(full.toMap());
    final lib = await databaseFactoryFfi.openDatabase('${dir.path}/library.db');
    await lib.update('sessions', {'data': fullJson});
    await lib.close();
    final cash = await databaseFactoryFfi.openDatabase(
      '${dir.path}/cash_${saved.id}.db',
    );
    await cash.update('settings', {
      'value': fullJson,
    }, where: "key = 'session'");
    await cash.close();
    final reopened = await MarketLibrary.open(
      factory: databaseFactoryFfi,
      directory: dir.path,
    );
    final healed = await reopened.activate(saved.id);
    expect(healed.session.metadata.containsKey('articles'), isFalse);
    await reopened.close();
    final check = await databaseFactoryFfi.openDatabase(
      '${dir.path}/library.db',
    );
    final n = await check.rawQuery('SELECT length(data) AS n FROM sessions');
    expect(n.single['n'] as int, lessThan(10000));
    await check.close();
    await dir.delete(recursive: true);
  });
}
