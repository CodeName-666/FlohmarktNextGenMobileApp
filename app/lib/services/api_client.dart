import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class AuthenticationRequiredException extends ApiException {
  const AuthenticationRequiredException()
    : super('Anmeldung erforderlich.', statusCode: 401);
}

class AccountLockedException extends ApiException {
  final String? lockedUntil;
  const AccountLockedException(this.lockedUntil)
    : super('Konto oder Markt gesperrt (HTTP 423).', statusCode: 423);
}

/// Backend token is deliberately held only in memory. There is no refresh API.
class ApiClient {
  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;
  final int maxAttempts;
  final Future<void> Function(Duration) _delay;
  String? _token;
  ApiClient(
    String base, {
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.maxAttempts = 3,
    Future<void> Function(Duration)? delay,
  }) : baseUrl = _parseBase(base),
       _client = client ?? http.Client(),
       _delay = delay ?? Future<void>.delayed {
    if (maxAttempts < 1 || timeout <= Duration.zero) {
      throw ArgumentError('Ungültige Timeout-/Retry-Konfiguration.');
    }
  }
  static Uri _parseBase(String base) {
    var text = base.trim().replaceAll(RegExp(r'/+$'), '');
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.parse(text);
    if (!['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('Ungültige API-Adresse.');
    }
    return uri;
  }

  bool get hasToken => _token != null;
  void setToken(String value) {
    if (value.isEmpty) throw ArgumentError('Leeres Token.');
    _token = value;
  }

  void clearToken() => _token = null;
  void close() {
    clearToken();
    _client.close();
  }

  Future<void> login(String email, String password) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const ApiException('E-Mail und Passwort dürfen nicht leer sein.');
    }
    clearToken();
    final response = await request(
      'POST',
      '/auth/login',
      json: {'email': email, 'password': password},
    );
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw const ApiException('Login-Antwort enthält kein gültiges JSON.');
    }
    if (body is! Map ||
        body['token'] is! String ||
        (body['token'] as String).isEmpty) {
      throw const ApiException('Login-Antwort enthält kein gültiges Token.');
    }
    setToken(body['token'] as String);
  }

  Future<http.Response> request(
    String method,
    String path, {
    Object? json,
    Map<String, Object?>? params,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/${path.replaceFirst(RegExp(r"^/+"), "")}',
    ).replace(queryParameters: params?.map((k, v) => MapEntry(k, '$v')));
    final headers = <String, String>{
      'Accept': 'application/json',
      if (json != null) 'Content-Type': 'application/json; charset=utf-8',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      http.Response? response;
      try {
        final request = http.Request(method, uri)..headers.addAll(headers);
        if (json != null) request.body = jsonEncode(json);
        response = await _client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(timeout);
      } on TimeoutException {
        if (attempt == maxAttempts - 1) {
          throw const ApiException('Zeitüberschreitung bei der API-Anfrage.');
        }
      } on SocketException {
        if (attempt == maxAttempts - 1) {
          throw const ApiException('Verbindung zum Backend fehlgeschlagen.');
        }
      } on http.ClientException {
        if (attempt == maxAttempts - 1) {
          throw const ApiException('Verbindung zum Backend fehlgeschlagen.');
        }
      }
      if (response != null &&
          (!{500, 502, 503, 504}.contains(response.statusCode) ||
              attempt == maxAttempts - 1)) {
        _check(response);
        return response;
      }
      if (attempt < maxAttempts - 1) {
        await _delay(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    throw const ApiException('API-Anfrage fehlgeschlagen.');
  }

  void _check(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    if (status == 401) {
      clearToken();
      throw const AuthenticationRequiredException();
    }
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    if (status == 423) {
      throw AccountLockedException(
        body is Map
            ? (body['lockedUntil'] ?? body['locked_until'])?.toString()
            : null,
      );
    }
    final errorBody = body is Map ? body : <String, Object?>{};
    final details = ['message', 'error', 'details']
        .where((key) => errorBody[key] != null)
        .map(
          (key) => errorBody[key] is String
              ? errorBody[key] as String
              : jsonEncode(errorBody[key]),
        )
        .join(' | ');
    throw ApiException(
      'HTTP $status${details.isEmpty ? "" : ": $details"}',
      statusCode: status,
    );
  }
}
