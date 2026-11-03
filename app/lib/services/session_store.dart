import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A backend session that survives app restarts: only the token and the API
/// address it belongs to, never the password (KAN-592).
class StoredSession {
  final String baseUrl;
  final String token;
  const StoredSession(this.baseUrl, this.token);
}

abstract class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// Platform key store: Android Keystore-backed storage (app backups are off),
/// iOS Keychain bound to this device, never synchronised or in a backup.
class SecureSessionStore implements SessionStore {
  static const _key = 'backendSession';
  final FlutterSecureStorage _storage;
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  @override
  Future<StoredSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map &&
          decoded['baseUrl'] is String &&
          decoded['token'] is String &&
          (decoded['token'] as String).isNotEmpty) {
        return StoredSession(
          decoded['baseUrl'] as String,
          decoded['token'] as String,
        );
      }
    } on FormatException {
      // A damaged entry is discarded below; the cashier simply logs in again.
    }
    await clear();
    return null;
  }

  @override
  Future<void> write(StoredSession session) => _storage.write(
    key: _key,
    value: jsonEncode({'baseUrl': session.baseUrl, 'token': session.token}),
  );

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Test and fallback store without persistence.
class MemorySessionStore implements SessionStore {
  StoredSession? _session;
  @override
  Future<StoredSession?> read() async => _session;
  @override
  Future<void> write(StoredSession session) async => _session = session;
  @override
  Future<void> clear() async => _session = null;
}
