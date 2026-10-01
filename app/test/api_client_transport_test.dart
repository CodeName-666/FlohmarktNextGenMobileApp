import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flohmarkt_mobile/services/api_client.dart';

void main() {
  test('transient retry retains bearer and 401 clears it', () async {
    var calls = 0;
    final client = ApiClient(
      'https://example.test',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer opaque');
        calls++;
        return http.Response('', calls == 1 ? 503 : 401);
      }),
      delay: (_) async {},
    );
    client.setToken('opaque');
    await expectLater(
      client.request('GET', '/markets'),
      throwsA(isA<AuthenticationRequiredException>()),
    );
    expect(calls, 2);
    expect(client.hasToken, isFalse);
  });
  test('login uses opaque memory-only token; lock is typed', () async {
    final client = ApiClient(
      'example.test',
      client: MockClient(
        (request) async => request.url.path == '/auth/login'
            ? http.Response('{"token":"opaque"}', 200)
            : http.Response('{"lockedUntil":"2026-09-26T13:00:00Z"}', 423),
      ),
    );
    await client.login('organizer@example.test', 'secret');
    expect(client.hasToken, isTrue);
    await expectLater(
      client.request('GET', '/markets'),
      throwsA(isA<AccountLockedException>()),
    );
  });
}
