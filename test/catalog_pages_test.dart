import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/domain/barcode.dart';
import 'package:flohmarkt_mobile/domain/models.dart';
import 'package:flohmarkt_mobile/ui/catalog_pages.dart';
import 'package:flohmarkt_mobile/domain/catalog_search.dart';
import 'package:flohmarkt_mobile/services/catalog_reports.dart';

void main() {
  late CheckoutStore store;
  late Directory directory;
  late List<ArticleListing> items;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('catalog_pages_');
    items = [
      for (var i = 0; i < 3; i++)
        ArticleListing(
          listingId: 'listing-$i',
          articleId: 'article-$i',
          codeFull: LabelCode.manual(
            '${i == 2 ? '0827001' : '0927001'}042000${i + 1}',
            1,
          ).codeFull,
          title: i == 0
              ? 'Hose'
              : i == 1
              ? 'Buch'
              : 'Jacke',
          priceCents: 250 + i * 100,
          labelRevision: 1,
          exportGeneration: 3,
          boxNumber: 7 + i,
          marketId: '42',
          size: '116',
          fields: {
            'description': i == 0
                ? 'Hose'
                : i == 1
                ? 'Buch'
                : 'Jacke',
            'size': '116',
            'hidden': 'Geheim',
            'price': 99,
          },
        ),
    ];
    store = await CheckoutStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/cash.db',
      listings: items,
      session: const MarketSession(
        marketId: '42',
        name: 'Herbstmarkt',
        registerNumber: 3,
        exportGeneration: 3,
        exportChecksum: 'fixture',
        metadata: {
          'fieldProfile': {
            'articleFields': [
              {'id': 'description', 'label': 'Beschreibung', 'type': 'string'},
              {'id': 'size', 'label': 'Größe', 'type': 'string'},
            ],
          },
          'market': {'date': '2026-09-26', 'freezeStatus': 'frozen'},
          'fees': {'revenueSharePercent': 15, 'sellerFeePerStammnummer': 5},
        },
      ),
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await tester.pump(const Duration(milliseconds: 25));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  test(
    'number search matches complete identities and rejects partial numeric input',
    () {
      final fields = catalogFields(store.session);
      List<ArticleListing> search(String text, ArticleSearchMode mode) =>
          filterCatalog(
            listings: items,
            soldListingIds: {},
            fields: fields,
            query: text,
            mode: mode,
          );
      expect(
        search('7-1', ArticleSearchMode.seller).single.listingId,
        'listing-0',
      );
      expect(search('42', ArticleSearchMode.seller), hasLength(3));
      expect(search('0927001042', ArticleSearchMode.seller), hasLength(2));
      expect(search('09-27-001-042', ArticleSearchMode.seller), hasLength(2));
      expect(
        search(items[2].codeFull, ArticleSearchMode.seller).single.listingId,
        'listing-2',
      );
      expect(
        search('3', ArticleSearchMode.article).single.listingId,
        'listing-2',
      );
      expect(search('3x', ArticleSearchMode.article), isEmpty);
      expect(search('99', ArticleSearchMode.description), isEmpty);
    },
  );

  test(
    'receipt and market PDFs generate locally with sale and refund history',
    () async {
      await store.addResolved(items[0]);
      final original = await store.checkout(500);
      await store.addReturn(items[0].listingId);
      final refund = await store.checkout(0);
      final events = await store.events();
      expect(receiptHistory(original, events), hasLength(2));
      expect(receiptHistory(refund, events), hasLength(1));
      for (final bytes in [
        await buildReceiptPdf(store.session, original, events),
        await buildReceiptPdf(store.session, refund, events),
        await buildMarketDetailsPdf(
          store.session,
          items,
          await store.activeSales(),
        ),
      ]) {
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      }
    },
  );

  testWidgets(
    'database errors offer retry instead of showing an empty catalog',
    (tester) async {
      await tester.runAsync(() async {
        await store.close();
        await tester.pumpWidget(
          MaterialApp(home: ArticleSearchPage(store: store)),
        );
        await settle(tester);
        expect(find.text('Erneut versuchen'), findsOneWidget);
        expect(
          find.textContaining('Lokale Speicherung fehlgeschlagen'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('article-query')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );

  testWidgets(
    'profile search uses all words and excludes hidden fields; status filter uses active sales',
    (tester) async {
      await tester.runAsync(() async {
        await store.addResolved(items[0]);
        await store.checkout(250);
        await tester.pumpWidget(
          MaterialApp(home: ArticleSearchPage(store: store)),
        );
        await settle(tester);
        await tester.enterText(
          find.byKey(const Key('article-query')),
          '116 HOSE',
        );
        await tester.pumpAndSettle();
        expect(find.text('Hose'), findsOneWidget);
        expect(find.textContaining('1 Treffer'), findsOneWidget);
        await tester.tap(find.byKey(const Key('status-available')));
        await tester.pumpAndSettle();
        expect(find.text('Hose'), findsNothing);
        await tester.tap(find.byKey(const Key('status-all')));
        await tester.enterText(
          find.byKey(const Key('article-query')),
          'Geheim',
        );
        await tester.pumpAndSettle();
        expect(find.text('Keine Artikel gefunden.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );

  testWidgets(
    'number lookup separates seller identities and returns selected available listing',
    (tester) async {
      await tester.runAsync(() async {
        ArticleListing? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selected = await Navigator.push<ArticleListing>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ArticleSearchPage(
                          store: store,
                          selectForCheckout: true,
                        ),
                      ),
                    );
                  },
                  child: const Text('Wählen'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Wählen'));
        await settle(tester);
        await tester.tap(find.byKey(const Key('mode-seller')));
        await tester.enterText(find.byKey(const Key('article-query')), '42');
        await tester.pumpAndSettle();
        expect(find.textContaining('09-27-001-042'), findsWidgets);
        expect(find.textContaining('08-27-001-042'), findsWidgets);
        await tester.tap(find.byKey(const Key('article-listing-0')));
        await tester.pumpAndSettle();
        expect(selected?.listingId, 'listing-0');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );

  testWidgets(
    'customer lookup shows original and later return without confusing receipt totals',
    (tester) async {
      await tester.runAsync(() async {
        await store.addResolved(items[0]);
        final original = await store.checkout(500);
        await store.addReturn(items[0].listingId);
        await store.checkout(0);
        await tester.pumpWidget(
          MaterialApp(home: CustomerSearchPage(store: store)),
        );
        await settle(tester);
        await tester.enterText(
          find.byKey(const Key('customer-query')),
          original.id,
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(find.textContaining('Kunde 1'), findsWidgets);
        expect(find.textContaining('Storno / Rückgabe'), findsOneWidget);
        expect(
          find.textContaining('Ursprünglicher Beleg: 2,50 €'),
          findsOneWidget,
        );
        await tester.enterText(find.byKey(const Key('customer-query')), '999');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(find.text('Kein Beleg gefunden.'), findsOneWidget);
        expect(find.textContaining('Ursprünglicher Beleg:'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );

  testWidgets(
    'market details stay readable on narrow phone and group full seller identity',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(home: MarketDetailsPage(store: store)),
        );
        await settle(tester);
        expect(find.text('Herbstmarkt'), findsOneWidget);
        expect(find.text('2 Verkäufer · 3 Boxen'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );
}
