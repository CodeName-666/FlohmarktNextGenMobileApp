import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/domain/models.dart';
import 'package:flohmarkt_mobile/services/api_client.dart';
import 'package:flohmarkt_mobile/services/sync_service.dart';

void main() {
  late CheckoutStore store;
  late Directory dir;
  const session = MarketSession(
    marketId: '9',
    name: 'Test',
    registerNumber: 1,
    exportGeneration: 7,
  );
  const listing = ArticleListing(
    listingId: 'L1',
    articleId: 'A1',
    codeFull: '092700104200054',
    title: 'Buch',
    priceCents: 250,
    labelRevision: 1,
    exportGeneration: 7,
    boxNumber: 17,
    marketId: '9',
  );
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sync_test_');
    store = await CheckoutStore.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/cash.db',
      session: session,
      listings: [listing],
    );
    await store.addResolved(listing);
    await store.checkout(250);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test('exact wire cents/revision and explicit created ack only', () async {
    final event = (await store.events()).single;
    final api = ApiClient(
      'https://example.test',
      client: MockClient((request) async {
        expect(request.url.path, '/sales/batch');
        final body = jsonDecode(request.body) as Map;
        expect(body['exportGeneration'], 7);
        expect(body['sales'][0]['items'][0], {
          'listingId': 'L1',
          'priceSnapshot': 2.5,
          'priceSnapshotCents': 250,
          'labelRevision': 1,
        });
        return http.Response(
          jsonEncode({
            'results': [
              {'vorgangId': event.id, 'result': 'created'},
            ],
          }),
          200,
        );
      }),
    )..setToken('test');
    final result = await SyncService(store, api).uploadSales();
    expect(result.acknowledged, 1);
    expect(await store.pendingEvents(), isEmpty);
    expect(await SyncService(store, api).protocols(), hasLength(1));
  });
  test('malformed success never acknowledges and persists failure', () async {
    final api = ApiClient(
      'https://example.test',
      client: MockClient((_) async => http.Response('{}', 200)),
    )..setToken('test');
    await expectLater(
      SyncService(store, api).uploadSales(),
      throwsA(isA<FormatException>()),
    );
    expect(await store.pendingEvents(), hasLength(1));
    expect(await SyncService(store, api).protocols(), hasLength(1));
  });
  test('summary is integer cents and does not acknowledge sales', () async {
    final api = ApiClient(
      'https://example.test',
      client: MockClient((request) async {
        expect(request.url.path, '/markets/9/sales-summary');
        expect((jsonDecode(request.body) as Map)['totalRevenueCents'], 250);
        return http.Response('{}', 200);
      }),
    )..setToken('test');
    await SyncService(store, api).uploadSummary();
    expect(await store.pendingEvents(), hasLength(1));
  });
  test(
    'out-of-order cancellation remains durable and retries only queued event',
    () async {
      final original = (await store.events()).single;
      await store.cancel(original.id);
      final cancellation = (await store.events()).last;
      var calls = 0;
      final api = ApiClient(
        'https://example.test',
        client: MockClient((request) async {
          final sent = (jsonDecode(request.body) as Map)['sales'] as List;
          calls++;
          if (calls == 1) {
            return http.Response(
              jsonEncode({
                'results': [
                  {'vorgangId': original.id, 'result': 'created'},
                  {'vorgangId': cancellation.id, 'result': 'invalid'},
                ],
              }),
              200,
            );
          }
          expect(sent.length, 1);
          expect((sent.single as Map)['cancelOf'], original.id);
          return http.Response(
            jsonEncode({
              'results': [
                {'vorgangId': cancellation.id, 'result': 'skipped_duplicate'},
              ],
            }),
            200,
          );
        }),
      )..setToken('test');
      await SyncService(store, api).uploadSales();
      expect(await store.setting('syncReuploadQueue'), [cancellation.id]);
      await SyncService(store, api).uploadSales(retryOnly: true);
      expect(await store.setting('syncReuploadQueue'), isEmpty);
      expect(await store.pendingEvents(), isEmpty);
    },
  );
  test('foreign acknowledgement ID cannot clear local outbox', () async {
    final api = ApiClient(
      'https://example.test',
      client: MockClient(
        (_) async => http.Response(
          '{"results":[{"vorgangId":"foreign","result":"created"}]}',
          200,
        ),
      ),
    )..setToken('test');
    await expectLater(
      SyncService(store, api).uploadSales(),
      throwsFormatException,
    );
    expect(await store.pendingEvents(), hasLength(1));
  });
  test(
    'local conflict cancellation is idempotent and selected protocol deletion preserves events',
    () async {
      final event = (await store.events()).single;
      final api = ApiClient('https://example.test');
      final service = SyncService(store, api);
      await service.cancelConflict(event.id);
      await service.cancelConflict(event.id);
      expect(await store.events(), hasLength(2));
      final selected = <String, Object?>{
        'stage': 'sales-batch',
        'at': 'one',
        'results': [],
      };
      await store.setSetting('syncProtocols', [
        selected,
        {'stage': 'other', 'at': 'two'},
      ]);
      await service.deleteProtocol(selected);
      expect((await service.protocols()).single['at'], 'two');
      expect(await store.pendingEvents(), hasLength(2));
      await expectLater(service.deleteProtocol(selected), throwsStateError);
      api.close();
    },
  );
  test(
    'partial acknowledgement exposes missing row and exports conflicts',
    () async {
      final original = (await store.events()).single;
      await store.cancel(original.id);
      final cancellation = (await store.events()).last;
      final api = ApiClient(
        'https://example.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'results': [
                {'vorgangId': original.id, 'result': 'created'},
              ],
            }),
            200,
          ),
        ),
      )..setToken('test');
      final service = SyncService(store, api);
      final result = await service.uploadSales();
      expect(result.acknowledged, 1);
      expect(result.results.last['result'], 'missing_ack');
      expect((await store.pendingEvents()).single.id, cancellation.id);
      expect((await service.protocols()).single['status'], 'needs_review');
      final exported = jsonDecode(await service.exportConflicts()) as Map;
      expect(exported['anzahl'], 1);
      expect(exported['konflikte'][0]['identifier'], cancellation.id);
      expect(await service.exportConflicts(csv: true), contains('missing_ack'));
    },
  );
}
