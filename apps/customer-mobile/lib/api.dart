import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// API base: localhost for iOS sim / desktop; pass
/// --dart-define=API_BASE=http://10.0.2.2:8080 for the Android emulator.
const String apiBase =
    String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');

/// Thrown for any non-2xx response. [detail] is taken from the RFC-9457
/// problem+json "detail" field when present, otherwise a best-effort message.
class ApiException implements Exception {
  ApiException(this.detail, {this.status});
  final String detail;
  final int? status;

  @override
  String toString() => detail;
}

/// Lightweight HTTP client that holds the auth session in memory and attaches
/// the bearer token automatically. All paths are relative to /api/v1.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final http.Client _http = http.Client();

  String? accessToken;
  String? refreshToken;
  String? userId;
  List<String> roles = const [];

  bool get isAuthenticated => accessToken != null;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = '$apiBase/api/v1$path';
    if (query == null || query.isEmpty) return Uri.parse(base);
    final cleaned = <String, String>{};
    query.forEach((k, v) {
      if (v != null) cleaned[k] = '$v';
    });
    return Uri.parse(base).replace(queryParameters: cleaned);
  }

  Map<String, String> _headers({bool auth = true, Map<String, String>? extra}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (auth && accessToken != null) {
      h['Authorization'] = 'Bearer $accessToken';
    }
    if (extra != null) h.addAll(extra);
    return h;
  }

  /// Decodes a response, throwing [ApiException] on failure.
  dynamic _decode(http.Response res) {
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (res.body.isEmpty) {
      if (ok) return null;
      throw ApiException(_statusMessage(res.statusCode), status: res.statusCode);
    }
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      if (ok) return null;
      throw ApiException(res.body, status: res.statusCode);
    }
    if (ok) return body;
    // problem+json: { "detail": "...", "title": "...", "status": 4xx }
    String detail = _statusMessage(res.statusCode);
    if (body is Map) {
      detail = (body['detail'] ?? body['title'] ?? body['message'] ?? detail)
          .toString();
    }
    throw ApiException(detail, status: res.statusCode);
  }

  String _statusMessage(int status) {
    switch (status) {
      case 400:
        return 'Bad request.';
      case 401:
        return 'Session expired. Please sign in again.';
      case 403:
        return 'You do not have permission to do that.';
      case 404:
        return 'Not found.';
      case 409:
        return 'Conflict.';
      case 422:
        return 'The request could not be processed.';
      default:
        return status >= 500
            ? 'The server had a problem (HTTP $status).'
            : 'Request failed (HTTP $status).';
    }
  }

  Future<T> _send<T>(Future<http.Response> Function() run) async {
    http.Response res;
    try {
      res = await run().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('The request timed out. Is the backend running?');
    } catch (e) {
      throw ApiException('Could not reach the server. Is it running?');
    }
    return _decode(res) as T;
  }

  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, bool auth = true}) {
    return _send(() =>
        _http.get(_uri(path, query), headers: _headers(auth: auth)));
  }

  Future<dynamic> post(String path,
      {Object? body, bool auth = true, Map<String, String>? headers}) {
    return _send(() => _http.post(
          _uri(path),
          headers: _headers(auth: auth, extra: headers),
          body: body == null ? null : jsonEncode(body),
        ));
  }

  /// POST with a raw (non-JSON) body, e.g. text/csv.
  Future<dynamic> postRaw(String path, String rawBody, String contentType,
      {bool auth = true}) {
    final h = <String, String>{'Content-Type': contentType};
    if (auth && accessToken != null) h['Authorization'] = 'Bearer $accessToken';
    return _send(() => _http.post(_uri(path), headers: h, body: rawBody));
  }

  Future<dynamic> patch(String path, {Object? body, bool auth = true}) {
    return _send(() => _http.patch(
          _uri(path),
          headers: _headers(auth: auth),
          body: body == null ? null : jsonEncode(body),
        ));
  }

  Future<dynamic> put(String path, {Object? body, bool auth = true}) {
    return _send(() => _http.put(
          _uri(path),
          headers: _headers(auth: auth),
          body: body == null ? null : jsonEncode(body),
        ));
  }

  Future<dynamic> delete(String path, {Object? body, bool auth = true}) {
    return _send(() => _http.delete(
          _uri(path),
          headers: _headers(auth: auth),
          body: body == null ? null : jsonEncode(body),
        ));
  }

  // --------------------------------------------------------------------------
  // Auth
  // --------------------------------------------------------------------------

  void _applyAuth(Map<String, dynamic> data) {
    accessToken = data['accessToken'] as String?;
    refreshToken = data['refreshToken'] as String?;
    userId = data['userId'] as String?;
    final r = data['roles'];
    roles = r is List ? r.map((e) => '$e').toList() : const [];
  }

  Future<void> login(String email, String password) async {
    final data = await post('/auth/portal/login',
        body: {'email': email, 'password': password}, auth: false) as Map<String, dynamic>;
    _applyAuth(data);
  }

  Future<void> register(String email, String password, String displayName) async {
    final data = await post('/auth/register', body: {
      'email': email,
      'password': password,
      'role': 'CUSTOMER',
      'displayName': displayName,
    }, auth: false) as Map<String, dynamic>;
    _applyAuth(data);
  }

  Future<void> logout() async {
    final token = refreshToken;
    accessToken = null;
    refreshToken = null;
    userId = null;
    roles = const [];
    if (token != null) {
      try {
        await post('/auth/logout', body: {'refreshToken': token}, auth: false);
      } catch (_) {
        // best-effort; local session already cleared.
      }
    }
  }

  /// RFC-4122-ish v4 idempotency key for checkout.
  static String newIdempotencyKey() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int i) => i.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
        '-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
