import 'dart:convert';
import 'dart:io';

import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/domain/models.dart';
import 'package:flohmarkt_mobile/services/api_client.dart';
import 'package:flohmarkt_mobile/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'contract/openapi_contract.dart';

/// KAN-590: every request the app sends and every backend answer it reads
/// conform to the shared OpenAPI. Answers are real backend exchanges recorded
/// by FlohmarktNextGen `tests/test_mobile_api_contract.py`.
void main() {
  final contract = OpenApiContract.load();
  final exchanges =
      (jsonDecode(
                File(
                  'test/contract/fixtures/backend_exchanges.json',
                ).readAsStringSync(),
              )
              as List)
          .cast<Map<String, Object?>>();
  Map<String, Object?> fixture(String name) =>
      exchanges.singleWhere((e) => e['name'] == name);
  String body(String name) {
    final response = fixture(name)['response'];
    return response == null ? '' : jsonEncode(response);
  }

  /// A mock backend that rejects any request outside the specification.
  ApiClient api(http.Response Function(http.Request request) answer) =>
      ApiClient(
        'https://example.test',
        maxAttempts: 1,
        client: MockClient((request) async {
          expect(
            contract.checkRequest(request),
            isEmpty,
            reason: request.url.path,
          );
          final response = answer(request);
          expect(
            contract.checkResponse(
              request.method,
              request.url.path,
              response.statusCode,
              response.body,
            ),
            isEmpty,
            reason: '${request.url.path} ${response.statusCode}',
          );
          return response;
        }),
      );

  group('spec copy', () {
    test('matches the recorded backend commit', () {
      expect(contract.source['commit'], matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(OpenApiContract.copySha256(), contract.source['sha256']);
    });

    test('every recorded backend exchange conforms to the copy', () {
      for (final exchange in exchanges) {
        final method = exchange['method'] as String;
        final path = exchange['path'] as String;
        final query = (exchange['query'] as Map).map(
          (k, v) => MapEntry('$k', '$v'),
        );
        final request =
            http.Request(
                method,
                Uri.https('example.test', path, query.isEmpty ? null : query),
              )
              ..headers['Authorization'] = 'Bearer test-token'
              ..body = exchange['request'] == null
                  ? ''
                  : jsonEncode(exchange['request']);
        final requestErrors = contract
            .checkRequest(request)
            .where((e) => e != 'Bearer-Token fehlt');
        expect(requestErrors, isEmpty, reason: '${exchange['name']}');
        expect(
          contract.checkResponse(
            method,
            path,
            exchange['status'] as int,
            body(exchange['name'] as String),
          ),
          isEmpty,
          reason: '${exchange['name']}',
        );
      }
    });

    test('validator rejects undocumented fields and wrong types', () {
      final schema = {r'$ref': '#/components/schemas/LoginRequest'};
      expect(
        contract.validate(schema, {'email': 'a', 'password': 'b'}, r'$'),
        isEmpty,
      );
      expect(
        contract.validate(schema, {
          'email': 'a',
          'password': 'b',
          'pin': 1,
        }, r'$'),
        isNotEmpty,
      );
      expect(
        contract.validate(schema, {'email': 'a', 'password': 3}, r'$'),
        isNotEmpty,
      );
      expect(contract.validate(schema, {'email': 'a'}, r'$'), isNotEmpty);
    });
  });

  group('login', () {
    test('sends a documented request and keeps the token', () async {
      final client = api((_) => http.Response(body('login_ok'), 200));
      await client.login('mobile.contract@example.com', 'ExportPass123!');
      expect(client.hasToken, isTrue);
    });

    test('wrong password is a documented 401', () async {
      final client = api(
        (_) => http.Response(body('login_wrong_password'), 401),
      );
      await expectLater(
        client.login('mobile.contract@example.com', 'falsch'),
        throwsA(isA<AuthenticationRequiredException>()),
      );
    });

    test('a locked account is a documented 423', () async {
      final client = api(
        (_) => http.Response(
          jsonEncode({'message': 'Account locked', 'lockedUntil': null}),
          423,
        ),
      );
      await expectLater(
        client.login('mobile.contract@example.com', 'x'),
        throwsA(isA<AccountLockedException>()),
      );
    });
  });

  group('market list and export', () {
    final export = fixture('export')['response'] as Map<String, Object?>;
    final marketId = (export['market'] as Map)['id'] as int;
    final organizationId =
        (fixture('markets')['query'] as Map)['organizationId'] as String;

    test('market list request and answer', () async {
      final client = api((_) => http.Response(body('markets'), 200))
        ..setToken('test-token');
      final markets = await SyncService(null, client).markets(organizationId);
      expect(markets.map((m) => m['id']), contains(marketId));
    });

    test('real backend export parses, including its checksum', () async {
      final client = api((_) => http.Response(body('export'), 200))
        ..setToken('test-token');
      final package = await SyncService(null, client).download(marketId);
      expect(package.session.marketId, '$marketId');
      expect(package.isLegacy, isFalse);
      expect(package.listings, hasLength((export['listings'] as List).length));
      final cents = (export['listings'] as List)
          .map((l) => (l as Map)['priceSnapshotCents'])
          .toSet();
      expect(package.listings.map((l) => l.priceCents).toSet(), cents);
    });

    for (final (name, status, matcher) in [
      ('export_without_token', 401, isA<AuthenticationRequiredException>()),
      (
        'export_forbidden',
        403,
        isA<ApiException>().having((e) => e.statusCode, 'status', 403),
      ),
    ]) {
      test('export answer $status is documented and surfaced', () async {
        final client = api((_) => http.Response(body(name), status))
          ..setToken('test-token');
        await expectLater(
          SyncService(null, client).download(marketId),
          throwsA(matcher),
        );
      });
    }
  });

  group('uploads', () {
    late CheckoutStore store;
    late Directory dir;
    const session = MarketSession(
      marketId: '9',
      name: 'Vertrag',
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
    const unknown = ArticleListing(
      listingId: 'U1',
      articleId: 'U1',
      codeFull: '092700104200062',
      title: 'Unbekannt',
      priceCents: 100,
      labelRevision: 1,
      exportGeneration: 7,
      boxNumber: 17,
      marketId: '9',
      unexpected: true,
    );
    setUpAll(sqfliteFfiInit);
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('contract_test_');
      store = await CheckoutStore.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/cash.db',
        session: session,
        listings: [listing, unknown],
      );
      await store.addResolved(listing);
      await store.addResolved(unknown);
      await store.checkout(350);
    });
    tearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });

    /// The recorded backend answer with this test's event identifier.
    String batchAnswer(String name, String vorgangId) {
      final answer = Map<String, Object?>.from(
        fixture(name)['response'] as Map,
      );
      answer['marketId'] = 9;
      answer['items'] = [
        for (final item in answer['items'] as List)
          {...(item as Map), 'vorgangId': vorgangId},
      ];
      return jsonEncode(answer);
    }

    test(
      'sales batch is documented; sales without listing stay local',
      () async {
        final sold = (await store.events()).singleWhere(
          (e) => !e.listing.unexpected,
        );
        final client = api((request) {
          final sales = (jsonDecode(request.body) as Map)['sales'] as List;
          expect(sales.map((s) => (s as Map)['vorgangId']), [sold.id]);
          return http.Response(batchAnswer('sales_batch', sold.id), 200);
        })..setToken('test-token');
        final service = SyncService(store, client);
        final result = await service.uploadSales();
        expect(result.acknowledged, 1);
        final pending = await store.pendingEvents();
        expect(pending.single.listing.unexpected, isTrue);
        expect(
          (await service.conflicts()).map((c) => c['result']),
          contains('missing_listing'),
        );
      },
    );

    test('409 batch answer is read as per-sale review, not an error', () async {
      final sold = (await store.events()).singleWhere(
        (e) => !e.listing.unexpected,
      );
      final client = api(
        (_) => http.Response(batchAnswer('sales_batch_conflict', sold.id), 409),
      )..setToken('test-token');
      final service = SyncService(store, client);
      final result = await service.uploadSales();
      expect(result.results.single['result'], 'conflict');
      expect((await service.protocols()).last['status'], 'needs_review');
      expect((await store.pendingEvents()).map((e) => e.id), contains(sold.id));
    });

    test('daily summary request and answer', () async {
      final client = api(
        (_) => http.Response(body('sales_summary_created'), 201),
      )..setToken('test-token');
      await SyncService(store, client).uploadSummary();
    });

    test('conflict referral request and answer', () async {
      final sold = (await store.events()).singleWhere(
        (e) => !e.listing.unexpected,
      );
      final client = api(
        (_) => http.Response(body('sale_conflict_referral'), 201),
      )..setToken('test-token');
      await SyncService(store, client).referConflict(sold.id, 'doppelverkauf');
      expect(await SyncService(store, client).referrals(), hasLength(1));
    });

    test('expired session is a documented 401 and clears the token', () async {
      final client = api(
        (_) => http.Response(body('export_after_logout_all'), 401),
      )..setToken('test-token');
      await expectLater(
        SyncService(store, client).uploadSales(),
        throwsA(isA<AuthenticationRequiredException>()),
      );
      expect(client.hasToken, isFalse);
    });
  });
}
