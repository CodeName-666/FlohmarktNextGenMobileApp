import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/market_library.dart';
import 'package:flohmarkt_mobile/data/demo_catalog.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test(
    'missing registered cash file is never recreated on activation or copy',
    () async {
      final dir = await Directory.systemTemp.createTemp('missing_cash_');
      final library = await MarketLibrary.open(
        factory: databaseFactoryFfi,
        directory: dir.path,
      );
      final saved = await library.createSession(
        demoSession,
        demoCatalog,
        source: 'original',
      );
      final path = '${dir.path}/cash_${saved.id}.db';
      await databaseFactoryFfi.deleteDatabase(path);
      await expectLater(library.activate(saved.id), throwsStateError);
      await expectLater(library.createRegister(saved.id, 2), throwsStateError);
      expect((await library.sessions(validate: true)).single.error, isNotNull);
      expect(await databaseFactoryFfi.databaseExists(path), false);
      expect(library.active, isNull);
      await library.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'failed last-session save preserves active till and open database',
    () async {
      final dir = await Directory.systemTemp.createTemp('library_atomic_');
      final library = await MarketLibrary.open(
        factory: databaseFactoryFfi,
        directory: dir.path,
      );
      final first = await library.createSession(
        demoSession,
        demoCatalog,
        source: 'original',
      );
      await library.activate(first.id);
      final second = await library.createRegister(first.id, 2);
      final registry = await databaseFactoryFfi.openDatabase(
        '${dir.path}/library.db',
      );
      await registry.execute(
        "CREATE TRIGGER fail_selection BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT,'disk full'); END",
      );
      await expectLater(
        library.activate(second.id),
        throwsA(isA<DatabaseException>()),
      );
      expect(library.activeId, first.id);
      expect((await library.active!.allListings()).length, 2);
      await registry.execute('DROP TRIGGER fail_selection');
      await library.activate(second.id);
      expect(library.active!.session.registerNumber, 2);
      await library.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'library persists sessions and refuses switch with open draft',
    () async {
      final dir = await Directory.systemTemp.createTemp('market_library_');
      var library = await MarketLibrary.open(
        factory: databaseFactoryFfi,
        directory: dir.path,
      );
      final first = await library.createSession(
        demoSession,
        demoCatalog,
        source: 'original',
      );
      final store = await library.activate(first.id);
      await store.addManual(demoCatalog.first.codeFull, 1);
      await expectLater(library.activate('other'), throwsStateError);
      await store.discardCart();
      await library.close();
      library = await MarketLibrary.open(
        factory: databaseFactoryFfi,
        directory: dir.path,
      );
      expect((await library.sessions()).single.id, first.id);
      expect(await library.source(first.id), 'original');
      expect((await library.activate(first.id)).session.isDemo, true);
      await library.close();
      await dir.delete(recursive: true);
    },
  );
}
