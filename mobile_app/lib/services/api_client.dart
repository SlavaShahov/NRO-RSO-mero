import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/event.dart';
import '../models/user.dart';
import '../screens/notifications_screen.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;
  String? accessToken;
  String? refreshToken;
  Future<void> Function()? onTokenExpired;

  final Duration _timeout = const Duration(seconds: 30);
  bool _isRefreshing = false;

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<void> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String middleName         = '',
    String phone              = '',
    String memberCardNumber   = '',
    String memberCardLocation = 'with_user',
    int?   unitId,
    int?   unitPositionId,
    int?   hqId,
    int?   hqPositionId,
  }) async {
    final body = <String, dynamic>{
      'email':               email,
      'password':            password,
      'first_name':          firstName,
      'last_name':           lastName,
      'middle_name':         middleName,
      'phone':               phone,
      'member_card_number':  memberCardNumber,
      'member_card_location': memberCardLocation,
    };
    if (unitId         != null) body['unit_id']          = unitId;
    if (unitPositionId != null) body['unit_position_id'] = unitPositionId;
    if (hqId           != null) body['hq_id']            = hqId;
    if (hqPositionId   != null) body['hq_position_id']   = hqPositionId;

    final res = await _post('/api/v1/auth/register', body, auth: false);
    accessToken  = res['access_token']  as String?;
    refreshToken = res['refresh_token'] as String?;
  }

  Future<void> login({required String email, required String password}) async {
    final res = await _post(
        '/api/v1/auth/login', {'email': email, 'password': password},
        auth: false);
    accessToken  = res['access_token']  as String?;
    refreshToken = res['refresh_token'] as String?;
  }

  Future<void> doRefresh() async {
    final token = refreshToken;
    if (token == null) throw const ApiException('Нет refresh-токена');
    final res = await _post('/api/v1/auth/refresh',
        {'refresh_token': token}, auth: false);
    accessToken  = res['access_token']  as String?;
    refreshToken = res['refresh_token'] as String?;
  }

  Future<void> logout() async {
    try {
      await _post('/api/v1/auth/logout',
          {'refresh_token': refreshToken ?? ''}, auth: true);
    } catch (_) {}
    accessToken  = null;
    refreshToken = null;
  }

  // ── User ──────────────────────────────────────────────────────────────────

  Future<UserProfile> me() async =>
      UserProfile.fromJson(await _get('/api/v1/me', auth: true));

  Future<Map<String, dynamic>> portfolio() async =>
      _get('/api/v1/portfolio', auth: true);

  Future<UserProfile> updateProfile({
    required String lastName,
    required String firstName,
    String middleName         = '',
    String phone              = '',
    String memberCardNumber   = '',
    String memberCardLocation = 'with_user',
  }) async {
    final res = await _put('/api/v1/me', {
      'last_name':            lastName,
      'first_name':           firstName,
      'middle_name':          middleName,
      'phone':                phone,
      'member_card_number':   memberCardNumber,
      'member_card_location': memberCardLocation,
    }, auth: true);
    return UserProfile.fromJson(res);
  }

  Future<List<MyRegistration>> myRegistrations() async {
    final raw = await _rawGet(
        Uri.parse('$baseUrl/api/v1/me/registrations'),
        headers: _headers(auth: true));
    if (raw is! List) return [];
    return raw
        .map((e) => MyRegistration.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<UnitItem>> myHQUnits() async {
    final raw = await _rawGet(
        Uri.parse('$baseUrl/api/v1/me/hq_units'),
        headers: _headers(auth: true));
    if (raw is! List) return [];
    return raw
        .map((e) => UnitItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<UserProfile>> unitMembers(int unitId) async {
    final raw = await _rawGet(
        Uri.parse('$baseUrl/api/v1/units/$unitId/members'),
        headers: _headers(auth: true));
    if (raw is! List) return [];
    return raw
        .map((e) => UserProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserProfile> userById(int userId) async =>
      UserProfile.fromJson(await _get('/api/v1/users/$userId', auth: true));

  // ── Events ────────────────────────────────────────────────────────────────

  Future<List<EventItem>> events({
    String? level,
    String? type,
    String? search,
  }) async {
    final params = <String, String>{};
    if (level  != null && level.isNotEmpty)  params['level']  = level;
    if (type   != null && type.isNotEmpty)   params['type']   = type;
    if (search != null && search.isNotEmpty) params['search'] = search;
    final uri = Uri.parse('$baseUrl/api/v1/events')
        .replace(queryParameters: params);
    final raw = await _rawGet(uri, headers: _headers(auth: true));
    if (raw is! List) return [];
    return raw
        .map((e) => EventItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> registerToEvent(int eventId) async =>
      _postEmpty('/api/v1/events/$eventId/register', auth: true);

  Future<Map<String, dynamic>> scanAttendance(String qrCode) async =>
      _post('/api/v1/attendance/scan', {'qr_code': qrCode}, auth: true);

  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> body) async =>
      _post('/api/v1/events', body, auth: true);

  // ── Справочники ───────────────────────────────────────────────────────────

  Future<List<HQItem>> listHQs() async {
    final raw = await _rawGet(Uri.parse('$baseUrl/api/v1/hqs'));
    if (raw is! List) return [];
    return raw
        .map((e) => HQItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<UnitItem>> listUnits(int hqId) async {
    final raw = await _rawGet(Uri.parse('$baseUrl/api/v1/hqs/$hqId/units'));
    if (raw is! List) return [];
    return raw
        .map((e) => UnitItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PositionItem>> listPositions() async {
    final raw = await _rawGet(Uri.parse('$baseUrl/api/v1/positions'));
    if (raw is! List) return [];
    return raw
        .map((e) => PositionItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<HQPositionItem>> listHQPositions() async {
    final raw = await _rawGet(Uri.parse('$baseUrl/api/v1/hq_positions'));
    if (raw is! List) return [];
    return raw
        .map((e) => HQPositionItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── HQ Staff ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> hqStaffRequest(
      int hqId, int positionId) async =>
      _post('/api/v1/hq_staff/request',
          {'hq_id': hqId, 'hq_position_id': positionId},
          auth: true);

  Future<void> reviewHQStaffRequest(int requestId,
      {required bool approved, String comment = ''}) async {
    await _post('/api/v1/hq_staff/$requestId/review',
        {'approved': approved, 'comment': comment},
        auth: true);
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  Future<List<AppNotification>> listNotifications() async {
    final raw = await _rawGet(
        Uri.parse('$baseUrl/api/v1/notifications'),
        headers: _headers(auth: true));
    if (raw is! List) return [];
    return raw
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getUnreadCount() async =>
      _get('/api/v1/notifications/unread', auth: true);

  Future<void> markAllNotificationsRead() async =>
      _post('/api/v1/notifications/read_all', {}, auth: true);

  Future<void> markNotificationRead(int id) async =>
      _post('/api/v1/notifications/$id/read', {}, auth: true);

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path, {bool auth = false}) async {
    final raw = await _rawGet(Uri.parse('$baseUrl$path'),
        headers: _headers(auth: auth));
    return raw as Map<String, dynamic>;
  }

  Future<dynamic> _rawGet(Uri uri, {Map<String, String>? headers}) async {
    try {
      final res =
      await http.get(uri, headers: headers ?? {}).timeout(_timeout);
      if (res.statusCode == 401 && !_isRefreshing) {
        return _retryAfterRefresh(() async {
          final r2 = await http
              .get(uri, headers: _headers(auth: true))
              .timeout(_timeout);
          return _handle(r2);
        });
      }
      return _handle(res);
    } on SocketException {
      throw ApiException(
          'Нет подключения к серверу.\nЗапусти docker-compose up');
    } on TimeoutException {
      throw ApiException('Сервер не отвечает. Проверь docker-compose up');
    }
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body, {bool auth = false}) async {
    try {
      final res = await http
          .post(Uri.parse('$baseUrl$path'),
          headers: _headers(auth: auth), body: jsonEncode(body))
          .timeout(_timeout);
      if (res.statusCode == 401 && auth && !_isRefreshing) {
        return _retryAfterRefresh(() async {
          final r2 = await http
              .post(Uri.parse('$baseUrl$path'),
              headers: _headers(auth: true), body: jsonEncode(body))
              .timeout(_timeout);
          return _handle(r2) as Map<String, dynamic>;
        });
      }
      return _handle(res) as Map<String, dynamic>;
    } on SocketException {
      throw ApiException('Нет подключения к серверу.');
    } on TimeoutException {
      throw ApiException('Сервер не отвечает.');
    }
  }

  Future<Map<String, dynamic>> _put(
      String path, Map<String, dynamic> body, {bool auth = false}) async {
    try {
      final res = await http
          .put(Uri.parse('$baseUrl$path'),
          headers: _headers(auth: auth), body: jsonEncode(body))
          .timeout(_timeout);
      if (res.statusCode == 401 && auth && !_isRefreshing) {
        return _retryAfterRefresh(() async {
          final r2 = await http
              .put(Uri.parse('$baseUrl$path'),
              headers: _headers(auth: true), body: jsonEncode(body))
              .timeout(_timeout);
          return _handle(r2) as Map<String, dynamic>;
        });
      }
      return _handle(res) as Map<String, dynamic>;
    } on SocketException {
      throw ApiException('Нет подключения к серверу.');
    } on TimeoutException {
      throw ApiException('Сервер не отвечает.');
    }
  }

  Future<Map<String, dynamic>> _postEmpty(String path,
      {bool auth = false}) async {
    try {
      final res = await http
          .post(Uri.parse('$baseUrl$path'), headers: _headers(auth: auth))
          .timeout(_timeout);
      if (res.statusCode == 401 && auth && !_isRefreshing) {
        return _retryAfterRefresh(() async {
          final r2 = await http
              .post(Uri.parse('$baseUrl$path'),
              headers: _headers(auth: true))
              .timeout(_timeout);
          return _handle(r2) as Map<String, dynamic>;
        });
      }
      return _handle(res) as Map<String, dynamic>;
    } on SocketException {
      throw ApiException('Нет подключения к серверу.');
    } on TimeoutException {
      throw ApiException('Сервер не отвечает.');
    }
  }

  Future<T> _retryAfterRefresh<T>(Future<T> Function() retry) async {
    _isRefreshing = true;
    try {
      if (onTokenExpired != null) {
        await onTokenExpired!();
      } else {
        await doRefresh();
      }
      return await retry();
    } finally {
      _isRefreshing = false;
    }
  }

  Map<String, String> _headers({bool auth = false}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (auth && accessToken != null) {
      h['Authorization'] = 'Bearer $accessToken';
    }
    return h;
  }

  dynamic _handle(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(res.body);
    }
    String msg = 'Ошибка ${res.statusCode}';
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['message'] != null) msg = j['message'] as String;
    } catch (_) {}
    throw ApiException(msg, statusCode: res.statusCode);
  }
}