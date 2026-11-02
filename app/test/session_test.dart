import 'dart:convert';
import 'dart:io';

import 'package:flohmarkt_mobile/services/api_client.dart';
import 'package:flohmarkt_mobile/services/app_diagnostics.dart';
import 'package:flohmarkt_mobile/services/session_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'contract/openapi_contract.dart';

/// KAN-592: the session survives restarts, ends on logout or 401 and never
/// leaks token or password.
void main() {
  final contract = OpenApiContract.load();
  const base = 'https://kasse.example.test';

  ApiClient client(
    SessionStore sessions,
    http.Response Function(http.Request request) answer,
  ) => ApiClient(
    base,
    maxAttempts: 1,
    sessions: sessions,
    client: MockClient((request) async {
      expect(contract.checkRequest(request), isEmpty, reason: request.url.path);
      return answer(request);
    }),
  );

  http.Response loginOk(http.Request _) => http.Response(
    jsonEncode({
      'token': 'session-token-123',
      'user': {
        'id': 'u1',
        'email': 'kasse@example.test',
        'name': 'Kasse',
        'role': 'user',
      },
    }),
    200,
  );

  test(
    'a stored session is resumed after a restart for the same server',
    () async {
      final sessions = MemorySessionStore();
      await client(sessions, loginOk).login('kasse@example.test', 'geheim');
      final stored = await sessions.read();
      expect(stored?.token, 'session-token-123');
      expect(
        jsonEncode([stored?.baseUrl, stored?.token]),
        isNot(contains('geheim')),
      );

      final restarted = client(sessions, (_) => http.Response('{}', 500));
      expect(await restarted.restoreSession(), isTrue);
      expect(restarted.hasToken, isTrue);

      final otherServer = ApiClient(
        'https://anderer.example.test',
        sessions: sessions,
      );
      expect(await otherServer.restoreSession(), isFalse);
      expect(otherServer.hasToken, isFalse);
    },
  );

  test('a 401 removes the stored session', () async {
    final sessions = MemorySessionStore();
    await sessions.write(const StoredSession(base, 'abgelaufen'));
    final api = client(
      sessions,
      (_) => http.Response(
        jsonEncode({'message': 'Invalid authentication token'}),
        401,
      ),
    );
    await api.restoreSession();
    await expectLater(
      api.request('GET', '/markets/1/export'),
      throwsA(isA<AuthenticationRequiredException>()),
    );
    expect(api.hasToken, isFalse);
    expect(await sessions.read(), isNull);
  });

  for (final (everywhere, path) in [
    (false, '/auth/logout'),
    (true, '/auth/logout-all'),
  ]) {
    test(
      'logout ${everywhere ? 'everywhere' : ''} ends server and device session',
      () async {
        final sessions = MemorySessionStore();
        final paths = <String>[];
        final api = client(sessions, (request) {
          paths.add(request.url.path);
          return request.url.path == '/auth/login'
              ? loginOk(request)
              : http.Response('', 204);
        });
        await api.login('kasse@example.test', 'geheim');
        await api.logout(everywhere: everywhere);
        expect(paths.last, path);
        expect(api.hasToken, isFalse);
        expect(await sessions.read(), isNull);
      },
    );
  }

  test('logout without network still removes the device session', () async {
    final sessions = MemorySessionStore();
    await sessions.write(const StoredSession(base, 'offline-token'));
    final api = ApiClient(
      base,
      maxAttempts: 1,
      sessions: sessions,
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    await api.restoreSession();
    await api.logout();
    expect(await sessions.read(), isNull);
  });

  test('closing the page keeps the session for the next start', () async {
    final sessions = MemorySessionStore();
    final api = client(sessions, loginOk);
    await api.login('kasse@example.test', 'geheim');
    api.close();
    expect((await sessions.read())?.token, 'session-token-123');
  });

  test(
    'secure store keeps only token and address and drops damaged entries',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      await store.write(const StoredSession(base, 'session-token-123'));
      final restored = await store.read();
      expect((restored?.baseUrl, restored?.token), (base, 'session-token-123'));
      FlutterSecureStorage.setMockInitialValues({'backendSession': 'kaputt'});
      expect(await SecureSessionStore().read(), isNull);
    },
  );

  test('token and password never reach the diagnostics export', () async {
    final dir = await Directory.systemTemp.createTemp('diag_test_');
    addTearDown(() => dir.delete(recursive: true));
    AppDiagnostics.initialize(dir.path);
    final validationEcho = ApiException(
      'HTTP 422: ${jsonEncode({
        'detail': [
          {
            'input': {'email': 'kasse@example.test', 'password': 'geheim'},
          },
        ],
      })}',
    );
    await AppDiagnostics.record('sync', validationEcho, null);
    await AppDiagnostics.record(
      'sync',
      Exception('Authorization: Bearer session-token-123'),
      StackTrace.fromString('token=session-token-123'),
    );
    final exported = await AppDiagnostics.read();
    expect(exported, isNot(contains('geheim')));
    expect(exported, isNot(contains('session-token-123')));
  });
}
