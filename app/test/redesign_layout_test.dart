import 'dart:io';
import 'dart:convert';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/demo_catalog.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/data/market_library.dart';
import 'package:flohmarkt_mobile/domain/barcode.dart';
import 'package:flohmarkt_mobile/domain/models.dart';
import 'package:flohmarkt_mobile/ui/archive_page.dart';
import 'package:flohmarkt_mobile/ui/catalog_pages.dart';
import 'package:flohmarkt_mobile/ui/files_page.dart';
import 'package:flohmarkt_mobile/ui/home_page.dart';
import 'package:flohmarkt_mobile/ui/library_page.dart';
import 'package:flohmarkt_mobile/ui/operations_pages.dart';
import 'package:flohmarkt_mobile/ui/receipt_page.dart';
import 'package:flohmarkt_mobile/ui/settings_page.dart';
import 'package:flohmarkt_mobile/ui/sync_page.dart';
import 'package:flohmarkt_mobile/ui/tones.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
    if (i >= 10 &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Screen did not finish loading.');
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    // Use the SDK's bundled app font so screenshots are readable rather than
    // Flutter tests' square Ahem glyphs. This adds no runtime font dependency.
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
    final flutter = packages.cast<Map>().singleWhere(
      (p) => p['name'] == 'flutter',
    );
    final sdk = Directory.fromUri(
      config.uri.resolve(flutter['rootUri'] as String),
    ).parent.parent;
    final fonts = FontLoader('Roboto');
    for (final weight in ['regular', 'bold']) {
      fonts.addFont(
        File(
          '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      File(
        '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ).readAsBytes().then(ByteData.sublistView),
    );
    await icons.load();
  });

  for (final brightness in Brightness.values) {
    testWidgets('all app areas fit 320px with large text in ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp('redesign_ui_');
        final library = await MarketLibrary.open(
          factory: databaseFactoryFfi,
          directory: directory.path,
        );
        try {
          final extra = ArticleListing.fromMap({
            ...demoCatalog.first.toMap(),
            'listingId': 'demo-listing-3',
            'articleId': 'demo-article-3',
            'codeFull': LabelCode.manual('09270010420007', 1).codeFull,
            'title': 'Demo · Holzspielzeug',
          });
          final saved = await library.createSession(demoSession, [
            ...demoCatalog,
            extra,
          ], source: 'demo');
          final store = await library.activate(saved.id);
          await store.addManual(demoCatalog.first.codeFull, 1);
          await store.checkout(1000);
          await store.addManual(demoCatalog[1].codeFull, 1);
          await store.parkCart();
          await store.addReturn(demoCatalog.first.listingId);
          await store.parkCart();
          await store.addManual(extra.codeFull, 1);
          await store.checkout(1000);
          final mode = brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light;
          final boundary = GlobalKey();
          Future<void> screenshot(String name, {String? fileName}) async {
            if (!const bool.fromEnvironment('UI_QA_SCREENSHOTS')) return;
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            final output = File(
              'build/qa/${fileName ?? '$name-${brightness.name}-320.png'}',
            );
            await output.parent.create(recursive: true);
            await output.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          }

          Future<void> render(Widget page, {double textScale = 1.8}) async {
            await tester.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: marketTheme(brightness),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
                  home: page,
                ),
              ),
            );
            await _settle(tester);
            expect(
              tester.takeException(),
              isNull,
              reason: '${page.runtimeType}',
            );
          }

          await render(
            HomePage(library: library, themeMode: mode, onThemeChanged: (_) {}),
          );
          expect(find.text('Kasse öffnen · 2 vorgemerkt'), findsOneWidget);
          await screenshot('home');
          await tester.tap(find.text('Kasse'));
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: 'RegisterPage');
          await screenshot('register');
          await tester.tap(find.text('Mehr'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Darstellung'),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('System'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.text('Artikel suchen'),
            -400,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Artikel suchen'));
          await _settle(tester);
          expect(find.byType(ArticleSearchPage), findsOneWidget);
          await tester.pageBack();
          await _settle(tester);

          for (final page in <Widget>[
            LibraryPage(library: library),
            ReceiptPage(store: store),
            ArticleSearchPage(store: store),
            CustomerSearchPage(store: store),
            MarketDetailsPage(store: store),
            AccountingPage(store: store),
            StatisticsPage(store: store),
            UnsoldPage(store: store),
            ReconciliationPage(store: store),
            FilesPage(store: store),
            ArchivePage(library: library),
            SyncPage(store: store, library: library),
            SettingsPage(store: store, themeMode: mode, onThemeChanged: (_) {}),
          ]) {
            await render(page);
            if (page is FilesPage) {
              await tester.ensureVisible(find.text('Kassenarchiv exportieren'));
              await tester.tap(find.text('Kassenarchiv exportieren'));
              for (var i = 0; i < 15; i++) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
                await tester.pump(const Duration(milliseconds: 20));
              }
              final drafts = await store.parkedDrafts();
              for (final draft in drafts) {
                expect(
                  find.textContaining('Vorgang ${draft.number} · geparkt'),
                  findsOneWidget,
                );
              }
              expect(tester.takeException(), isNull);
              await tester.tap(
                find.textContaining('Vorgang ${drafts.first.number} · geparkt'),
              );
              for (var i = 0; i < 15; i++) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
                await tester.pump(const Duration(milliseconds: 20));
              }
              expect(find.text('Vorgangsnummer anpassen?'), findsOneWidget);
              await tester.tap(find.text('Abbrechen'));
              await _settle(tester);
              expect(
                (await store.parkedDrafts()).map((draft) => draft.number),
                drafts.map((draft) => draft.number),
              );
            }
            // Traverse long forms too: clipped controls often occur below the fold.
            for (var step = 0; step < 8; step++) {
              final scrollable = find.byType(Scrollable).first;
              await tester.drag(scrollable, const Offset(0, -500));
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '${page.runtimeType}',
              );
            }
          }
          if (brightness == Brightness.light &&
              const bool.fromEnvironment('UI_QA_SCREENSHOTS')) {
            // Capture the ordinary cashier workflow after all compact/large-text
            // assertions, using an existing demo draft rather than a new sale.
            final draft = (await store.parkedDrafts()).first;
            await store.resumeDraft(draft.id);
            tester.view.physicalSize = const Size(390, 844);
            await render(
              HomePage(
                library: library,
                themeMode: mode,
                onThemeChanged: (_) {},
              ),
              textScale: 1,
            );
            await tester.tap(find.text('Kasse'));
            await _settle(tester);
            expect(
              find.text(draft.entries.first.listing.title),
              findsOneWidget,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: 'RegisterPage phone',
            );
            await screenshot('register', fileName: 'register-light-phone.png');
          }
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await library.close();
          await directory.delete(recursive: true);
        }
      });
    });
  }
}
