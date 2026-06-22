import 'dart:convert';

import 'package:http/http.dart' as http;

/// API base: localhost for iOS sim / desktop.
/// Pass --dart-define=API_BASE=http://10.0.2.2:8080 for the Android emulator.
const String apiBase =
    String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');

/// Thrown for any non-2xx response. Carries the RFC-9457 problem+json `detail`
/// when the backend supplied one, otherwise a sensible fallback message.
class ApiException implements Exception {
  ApiException(this.statusCode, this.detail, {this.title});

  final int statusCode;
  final String detail;
  final String? title;

  @override
  String toString() => detail;
}

/// In-memory session for the signed-in driver. Tokens never touch disk in this
/// dev build; killing the app logs out.
class Session {
  Session({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.roles,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final List<String> roles;

  bool get isDriver =>
      roles.any((r) => r.toUpperCase() == 'DRIVER');
}

/// Minimal typed client around the Grocery-Mart REST API. Holds the auth tokens
/// in memory and attaches `Authorization: Bearer <accessToken>` to every
/// non-public call. All paths are under `/api/v1`.
class ApiClient {
  ApiClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  Session? session;

  bool get isAuthenticated => session != null;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final qp = query?.map((k, v) => MapEntry(k, '$v'));
    return Uri.parse('$apiBase/api/v1$path').replace(
      queryParameters: (qp == null || qp.isEmpty) ? null : qp,
    );
  }

  Map<String, String> _headers({bool auth = true, Map<String, String>? extra}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (auth && session != null) {
      h['Authorization'] = 'Bearer ${session!.accessToken}';
    }
    if (extra != null) h.addAll(extra);
    return h;
  }

  Never _raise(http.Response res) {
    String detail = 'Request failed (${res.statusCode})';
    String? title;
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          final d = decoded['detail'] ?? decoded['message'] ?? decoded['error'];
          if (d is String && d.trim().isNotEmpty) detail = d;
          final t = decoded['title'];
          if (t is String && t.trim().isNotEmpty) title = t;
        }
      } catch (_) {
        // Non-JSON error body; keep the generic detail.
      }
    }
    throw ApiException(res.statusCode, detail, title: title);
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) _raise(res);
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  Future<dynamic> _get(String path,
      {Map<String, dynamic>? query, bool auth = true}) async {
    try {
      final res = await _http.get(_uri(path, query), headers: _headers(auth: auth));
      return _decode(res);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(0, _networkMessage(e));
    }
  }

  Future<dynamic> _post(String path,
      {Object? body,
      bool auth = true,
      Map<String, String>? extraHeaders}) async {
    try {
      final res = await _http.post(
        _uri(path),
        headers: _headers(
          auth: auth,
          extra: {'Content-Type': 'application/json', ...?extraHeaders},
        ),
        body: body == null ? null : jsonEncode(body),
      );
      return _decode(res);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(0, _networkMessage(e));
    }
  }

  String _networkMessage(Object e) =>
      'Could not reach the server at $apiBase. Is the backend running? ($e)';

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// POST /auth/portal/login -> stores the session and returns it.
  Future<Session> portalLogin(String email, String password) async {
    final json = await _post(
      '/auth/portal/login',
      auth: false,
      body: {'email': email, 'password': password},
    ) as Map<String, dynamic>;
    final s = Session(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      userId: '${json['userId']}',
      roles: ((json['roles'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(growable: false),
    );
    session = s;
    return s;
  }

  /// POST /auth/logout — best-effort, then clears the in-memory session.
  Future<void> logout() async {
    final s = session;
    if (s != null) {
      try {
        await _post('/auth/logout',
            auth: false, body: {'refreshToken': s.refreshToken});
      } catch (_) {
        // Ignore logout failures; we clear locally regardless.
      }
    }
    session = null;
  }

  // ---------------------------------------------------------------------------
  // Driver jobs
  // ---------------------------------------------------------------------------

  /// GET /driver/jobs
  Future<List<DriverJob>> jobs() async {
    final list = await _get('/driver/jobs') as List<dynamic>;
    return list
        .map((e) => DriverJob.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// POST /driver/orders/{orderId}/accept
  Future<void> acceptJob(String orderId) =>
      _post('/driver/orders/$orderId/accept');

  /// POST /driver/orders/{orderId}/reject
  Future<void> rejectJob(String orderId) =>
      _post('/driver/orders/$orderId/reject');

  /// POST /driver/orders/{orderId}/pickup
  Future<void> pickupJob(String orderId) =>
      _post('/driver/orders/$orderId/pickup');

  /// POST /driver/orders/{orderId}/deliver
  Future<void> deliverJob(String orderId) =>
      _post('/driver/orders/$orderId/deliver');

  /// POST /driver/orders/{orderId}/consent {consent}
  Future<void> setConsent(String orderId, bool consent) =>
      _post('/driver/orders/$orderId/consent', body: {'consent': consent});

  /// POST /driver/orders/{orderId}/location {lat,lng}
  Future<void> sendLocation(String orderId, double lat, double lng) =>
      _post('/driver/orders/$orderId/location', body: {'lat': lat, 'lng': lng});

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  /// GET /notifications?cursor&limit
  Future<NotificationPage> notifications({String? cursor, int limit = 30}) async {
    final json = await _get('/notifications', query: {
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
    }) as Map<String, dynamic>;
    return NotificationPage.fromJson(json);
  }

  /// POST /notifications/read — marks everything read.
  Future<void> markAllNotificationsRead() => _post('/notifications/read');

  /// POST /notifications/{id}/read — marks a single notification read.
  Future<void> markNotificationRead(String id) =>
      _post('/notifications/$id/read');

  void close() => _http.close();
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

enum JobState { assigned, accepted, pickedUp, unknown }

JobState jobStateFrom(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'assigned':
      return JobState.assigned;
    case 'accepted':
      return JobState.accepted;
    case 'picked_up':
      return JobState.pickedUp;
    default:
      return JobState.unknown;
  }
}

extension JobStateLabel on JobState {
  String get label {
    switch (this) {
      case JobState.assigned:
        return 'Assigned';
      case JobState.accepted:
        return 'Accepted';
      case JobState.pickedUp:
        return 'Picked up';
      case JobState.unknown:
        return 'Unknown';
    }
  }
}

class DriverJob {
  DriverJob({
    required this.orderId,
    required this.state,
    required this.rawState,
    required this.timing,
    required this.pickupStore,
    required this.destination,
    required this.destLat,
    required this.destLng,
  });

  final String orderId;
  final JobState state;
  final String rawState;
  final String timing;
  final String pickupStore;
  final String destination;
  final double? destLat;
  final double? destLng;

  factory DriverJob.fromJson(Map<String, dynamic> j) {
    double? toD(dynamic v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    final raw = '${j['state'] ?? ''}';
    return DriverJob(
      orderId: '${j['orderId']}',
      state: jobStateFrom(raw),
      rawState: raw,
      timing: '${j['timing'] ?? ''}',
      pickupStore: '${j['pickupStore'] ?? ''}',
      destination: '${j['destination'] ?? ''}',
      destLat: toD(j['destLat']),
      destLng: toD(j['destLng']),
    );
  }
}

class NotificationPage {
  NotificationPage({
    required this.items,
    required this.nextCursor,
    required this.unreadCount,
  });

  final List<AppNotification> items;
  final String? nextCursor;
  final int unreadCount;

  factory NotificationPage.fromJson(Map<String, dynamic> j) {
    final items = ((j['items'] as List?) ?? const [])
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return NotificationPage(
      items: items,
      nextCursor: j['nextCursor'] as String?,
      unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.category,
    required this.orderId,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final String category;
  final String? orderId;
  final bool read;
  final String createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    return AppNotification(
      id: '${j['id']}',
      type: '${j['type'] ?? ''}',
      title: '${j['title'] ?? ''}',
      body: '${j['body'] ?? ''}',
      category: '${j['category'] ?? ''}',
      orderId: j['orderId'] == null ? null : '${j['orderId']}',
      read: j['read'] == true,
      createdAt: '${j['createdAt'] ?? ''}',
    );
  }
}
