import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/ui/settings_page.dart';

Future<void> waitForSettings(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
  fail('Settings did not load.');
}

void main() {
  setUpAll(sqfliteFfiInit);
  for (final save in [false, true]) {
    testWidgets(
      save
          ? 'settings commit before theme callback'
          : 'cancel preserves all saved settings',
      (tester) async {
        await tester.runAsync(() async {
          final store = await CheckoutStore.open(
            factory: databaseFactoryFfi,
            path: inMemoryDatabasePath,
          );
          final original = <String, Object?>{
            'cameraEnabled': true,
            'themeMode': 'system',
          };
          await store.setSetting('uiSettings', original);
          ThemeMode? applied;
          Object? seenAtCallback;
          await tester.pumpWidget(
            MaterialApp(
              home: SettingsPage(
                store: store,
                themeMode: ThemeMode.system,
                onThemeChanged: (value) {
                  applied = value;
                  seenAtCallback = store.setting('uiSettings');
                },
              ),
            ),
          );
          await waitForSettings(tester);
          await tester.ensureVisible(find.text('Kamera aktivieren'));
          await tester.tap(find.text('Kamera aktivieren'));
          await tester.pump();
          expect(await store.setting('uiSettings'), original);
          final button = find.text(
            save ? 'Einstellungen speichern' : 'Abbrechen',
          );
          await tester.scrollUntilVisible(
            button,
            500,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(button);
          for (var i = 0; i < 30; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
          }
          if (save) {
            expect(applied, ThemeMode.system);
            final committed = await (seenAtCallback as Future<Object?>);
            expect((committed as Map)['cameraEnabled'], false);
            expect(
              (await store.setting('uiSettings') as Map)['logMaxBytes'],
              5242880,
            );
          } else {
            expect(applied, isNull);
            expect(await store.setting('uiSettings'), original);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await store.close();
        });
      },
    );
  }
  testWidgets(
    'failed persistence leaves settings page open and theme unchanged',
    (tester) async {
      await tester.runAsync(() async {
        final store = await CheckoutStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        var callbacks = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: SettingsPage(
              store: store,
              themeMode: ThemeMode.system,
              onThemeChanged: (_) => callbacks++,
            ),
          ),
        );
        await waitForSettings(tester);
        await store.close();
        await tester.scrollUntilVisible(
          find.text('Einstellungen speichern'),
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Einstellungen speichern'));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
        expect(callbacks, 0);
        expect(find.byType(SettingsPage), findsOneWidget);
        await tester.scrollUntilVisible(
          find.textContaining('Nicht gespeichert:'),
          -500,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining('Nicht gespeichert:'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );
}
