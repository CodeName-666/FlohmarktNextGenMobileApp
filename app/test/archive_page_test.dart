import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/data/demo_catalog.dart';
import 'package:flohmarkt_mobile/data/market_library.dart';
import 'package:flohmarkt_mobile/ui/archive_page.dart';
import 'widget_test.dart' show settleDatabase;

void main() {
  setUpAll(sqfliteFfiInit);
  testWidgets('archive inspection and exact deletion preserve active draft', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('archive_ui_');
      final library = await MarketLibrary.open(
        factory: databaseFactoryFfi,
        directory: dir.path,
      );
      final first = await library.createSession(
        demoSession,
        demoCatalog,
        source: '{}',
      );
      final second = await library.createRegister(first.id, 2);
      await library.withSession(second.id, (store) async {
        await store.setSetting('syncProtocols', [
          {
            'stage': 'sales-batch',
            'status': 'conflict',
            'at': '2026-09-26',
            'results': [],
          },
        ]);
        await store.setSetting('syncReferrals', [
          {'vorgangId': 'referral'},
        ]);
      });
      final active = await library.activate(first.id);
      await active.addManual(demoCatalog.first.codeFull, 1);
      await tester.pumpWidget(MaterialApp(home: ArchivePage(library: library)));
      await settleDatabase(tester);
      expect(find.text('Demomarkt · Kasse 2'), findsOneWidget);
      await tester.tap(find.text('Demomarkt · Kasse 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sales-batch · conflict'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dieses Protokoll löschen'));
      await tester.tap(find.text('Dieses Protokoll löschen'));
      // The protected archive operation keeps its progress indicator visible
      // while the confirmation dialog is open.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Protokoll löschen'));
      await settleDatabase(tester);
      expect(library.activeId, first.id);
      expect(await active.cartLines(), hasLength(1));
      await library.withSession(second.id, (store) async {
        expect(await store.setting('syncProtocols'), isEmpty);
        expect(await store.setting('syncReferrals'), hasLength(1));
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await library.close();
      await dir.delete(recursive: true);
    });
  });
}
