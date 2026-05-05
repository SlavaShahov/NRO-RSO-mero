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

/// Регистрация пользователя на мероприятие
class MyRegistration {
  final int id, eventId;
  final String eventTitle, eventDate, startTime, location, status, qrCode;
  final bool isUpcoming, isAttended;

  const MyRegistration({
    required this.id, required this.eventId,
    required this.eventTitle, required this.eventDate,
    required this.startTime, required this.location,
    required this.status, required this.qrCode,
    required this.isUpcoming, required this.isAttended,
  });

  factory MyRegistration.fromJson(Map<String, dynamic> j) {
    final s = (j['status_code'] ?? j['status'] ?? 'registered') as String;
    final d = (j['event_date'] ?? '') as String;
    return MyRegistration(
      id:         j['registration_id'] as int? ?? j['id'] as int? ?? 0,
      eventId:    j['event_id'] as int? ?? 0,
      eventTitle: (j['event_title'] ?? j['title'] ?? '') as String,
      eventDate:  d,
      startTime:  (j['start_time'] ?? '') as String,
      location:   (j['location'] ?? '') as String,
      status:     s,
      qrCode:     (j['qr_code'] ?? '') as String,
      isUpcoming: DateTime.tryParse(d)?.isAfter(DateTime.now()) ?? false,
      isAttended: s == 'attended',
    );
  }

  String get dayStr        => eventDate.length >= 10 ? eventDate.substring(8, 10) : '';
  String get startTimeShort => startTime.length >= 5 ? startTime.substring(0, 5) : startTime;

  String get monthStr {
    if (eventDate.length < 7) return '';
    final m = int.tryParse(eventDate.substring(5, 7)) ?? 0;
    const ms = ['', 'ЯНВ', 'ФЕВ', 'МАР', 'АПР', 'МАЙ', 'ИЮН',
      'ИЮЛ', 'АВГ', 'СЕН', 'ОКТ', 'НОЯ', 'ДЕК'];
    return (m > 0 && m <= 12) ? ms[m] : '';
  }
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

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String middleName         = '',
    String phone              = '',
    String memberCardNumber   = '',
    String memberCardLocation = 'with_user',
    int? unitId,
    int? unitPositionId,
    int? hqId,
    int? hqPositionId,
  }) async {
    final body = <String, dynamic>{
      'email': email,           'password': password,
      'first_name': firstName,  'last_name': lastName,
      'middle_name': middleName,
      'phone': phone,
      'member_card_number': memberCardNumber,
      'member_card_location': memberCardLocation,
    };
    if (unitId != null)          body['unit_id']          = unitId;
    if (unitPositionId != null)  body['unit_position_id'] = unitPositionId;
    if (hqId != null)            body['hq_id']            = hqId;
    if (hqPositionId != null)    body['hq_position_id']   = hqPositionId;
    final res = await _post('/api/v1/auth/register', body, auth: false);
    accessToken  = res['access_token']  as String?;
    refreshToken = res['refresh_token'] as String?;
    return res;
  }

  Future<void> login({required String email, required String password}) async {
    final res = await _post('/api/v1/auth/login',
        {'email': email, 'password': password}, auth: false);
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

  // ── Подтверждение email ───────────────────────────────────────────────────

  Future<void> verifyEmail({required int userId, required String code}) async {
    await _post('/api/v1/auth/verify-email',
        {'user_id': userId, 'code': code}, auth: false);
  }

  Future<void> resendVerificationCode({
    required int userId, required String email,
  }) async {
    await _post('/api/v1/auth/resend-code',
        {'user_id': userId, 'email': email}, auth: false);
  }

  // ── Сброс пароля ─────────────────────────────────────────────────────────

  Future<void> forgotPassword(String email) async {
    await _post('/api/v1/auth/forgot-password', {'email': email}, auth: false);
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _post('/api/v1/auth/reset-password',
        {'email': email, 'code': code, 'new_password': newPassword},
        auth: false);
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
      'last_name':           lastName,
      'first_name':          firstName,
      'middle_name':         middleName,
      'phone':               phone,
      'member_card_number':  memberCardNumber,
      'member_card_location': memberCardLocation,
    }, auth: true);
    return UserProfile.fromJson(res);
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _put('/api/v1/me/password', {
      'old_password': oldPassword,
      'new_password': newPassword,
    }, auth: true);
  }

  Future<void> deleteAccount(String password) async {
    final uri = Uri.parse('$baseUrl/api/v1/me');
    final req  = http.Request('DELETE', uri);
    req.headers.addAll(_headers(auth: true));
    req.body = jsonEncode({'password': password});
    final streamed = await req.send().timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    _handle(res);
  }

  Future<List<MyRegistration>> myRegistrations() async {
    final raw = await _rawGet(Uri.parse('$baseUrl/api/v1/me/registrations'),
        headers: _headers(auth: true));
    if (raw is! List) return [];
    return raw
        .map((e) => MyRegistration.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Аватар ───────────────────────────────────────────────────────────────

  Future<void> uploadAvatar(List<int> bytes) async {
    await _post('/api/v1/me/avatar',
        {'avatar_base64': base64Encode(bytes)}, auth: true);
  }

  Future<String> getMyAvatar() async {
    final raw = await _rawGet(Uri.parse('$baseUrl/api/v1/me/avatar'),
        headers: _headers(auth: true));
    if (raw is Map<String, dynamic>) {
      return (raw['avatar_base64'] ?? '') as String;
    }
    return '';
  }

  // ── Unit members ──────────────────────────────────────────────────────────

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
    String? level, String? type, String? search,
  }) async {
    final params = <String, String>{};
    if (level  != null && level.isNotEmpty)  params['level']  = level;
    if (type   != null && type.isNotEmpty)   params['type']   = type;
    if (search != null && search.isNotEmpty) params['search'] = search;
    final uri = Uri.parse('$baseUrl/api/v1/events')
        .replace(queryParameters: params);
    final h = <String, String>{'Content-Type': 'application/json'};
    if (accessToken != null) h['Authorization'] = 'Bearer $accessToken';
    final raw = await _rawGet(uri, headers: h);
    if (raw is! List) return [];
    return raw
        .map((e) => EventItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> registerToEvent(int eventId) async =>
      _postEmpty('/api/v1/events/$eventId/register', auth: true);

  Future<Map<String, dynamic>> scanAttendance(String qrCode) async =>
      _post('/api/v1/attendance/scan', {'qr_code': qrCode}, auth: true);

  Future<Map<String, dynamic>> createEvent({
    required String title,
    required String description,
    required String location,
    required String eventDate,
    required String startTime,
    required String levelCode,
    required String typeCode,
  }) async =>
      _post('/api/v1/events', {
        'title': title,       'description': description,
        'location': location, 'event_date': eventDate,
        'start_time': startTime,
        'level_code': levelCode, 'type_code': typeCode,
        'status_code': 'published',
      }, auth: true);

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

  // ── HQ Staff ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> checkHQPosition(int hqId, int positionId) async {
    final raw = await _rawGet(Uri.parse(
        '$baseUrl/api/v1/hq_staff/check_position?hq_id=$hqId&position_id=$positionId'),
        headers: _headers(auth: true));
    if (raw is Map<String, dynamic>) return raw;
    return {};
  }

  Future<Map<String, dynamic>> reviewHQStaffRequest(int id, {
    required bool approved,
    String comment = '',
  }) async =>
      _post('/api/v1/hq_staff/$id/review',
          {'approved': approved, 'comment': comment}, auth: true);

  Future<List<UnitItem>> myHQUnits() async {
    final raw = await _rawGet(Uri.parse('$baseUrl/api/v1/me/hq_units'),
        headers: _headers(auth: true));
    if (raw is! List) return [];
    return raw
        .map((e) => UnitItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Уведомления ──────────────────────────────────────────────────────────

  Future<List<AppNotification>> listNotifications() async {
    final raw = await _rawGet(Uri.parse('$baseUrl/api/v1/notifications'),
        headers: _headers(auth: true));
    if (raw is! List) return [];
    return raw
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markAllNotificationsRead() async {
    await _post('/api/v1/notifications/read_all', {}, auth: true);
  }

  Future<void> markNotificationRead(int id) async {
    await _post('/api/v1/notifications/$id/read', {}, auth: true);
  }


  // ── Смена email ───────────────────────────────────────────────────────────

  Future<void> requestEmailChange({required String newEmail}) async {
    await _post('/api/v1/me/email/change', {'new_email': newEmail}, auth: true);
  }

  Future<void> confirmEmailChange({required String code}) async {
    await _post('/api/v1/me/email/confirm', {'code': code}, auth: true);
  }

  // ── Смена должности ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> requestPositionChange({
    required int positionId,
    required String positionCode,
    required String positionName,
    int? unitId,
    String unitName = '',
    String hqName = '',
  }) async {
    final body = <String, dynamic>{
      'position_id':   positionId,
      'position_code': positionCode,
      'position_name': positionName,
      'unit_name':     unitName,
      'hq_name':       hqName,
    };
    if (unitId != null) body['unit_id'] = unitId;
    return _post('/api/v1/me/position/change', body, auth: true);
  }

  Future<List<dynamic>> listPositionRequests() async {
    final raw = await _rawGet(
        Uri.parse('\$baseUrl/api/v1/admin/position-requests'),
        headers: _headers(auth: true));
    if (raw is! List) return [];
    return raw;
  }

  Future<void> reviewPositionRequest(int id, {
    required bool approved,
    String comment = '',
  }) async {
    await _post('/api/v1/admin/position-requests/$id/review',
        {'approved': approved, 'comment': comment}, auth: true);
  }

  // ── Заявка на должность ШСО ───────────────────────────────────────────────

  Future<Map<String, dynamic>> requestHQStaffPosition({
    required int hqId,
    required int positionId,
    String hqName = '',
    String positionName = '',
  }) async =>
      _post('/api/v1/hq_staff/request', {
        'hq_id':          hqId,
        'hq_position_id': positionId,
        'hq_name':        hqName,
        'position_name':  positionName,
      }, auth: true);

  Future<dynamic> _put(String path, Map<String, dynamic> body, {bool auth = false}) async {
    final res = await http.put(
        Uri.parse('$baseUrl$path'),
        headers: _headers(auth: auth),
        body: jsonEncode(body));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.body.isEmpty ? {} : jsonDecode(res.body);
    }
    throw ApiException(_extractError(res.body), statusCode: res.statusCode);
  }


  // ── Редактирование мероприятия ────────────────────────────────────────────

  Future<void> updateEvent({
    required int id,
    required String title,
    String description = '',
    String location = '',
    required String eventDate,
    required String startTime,
    String levelCode = 'regional',
    String typeCode = 'sport',
    String participationMode = 'open',
    int? maxParticipants,
  }) async {
    await _put('/api/v1/events/$id', {
      'title': title, 'description': description, 'location': location,
      'event_date': eventDate, 'start_time': startTime,
      'level_code': levelCode, 'type_code': typeCode,
      'participation_mode': participationMode,
      if (maxParticipants != null) 'max_participants': maxParticipants,
    }, auth: true);
  }

  Future<void> cancelEvent(int id) async {
    await _post('/api/v1/events/$id/cancel', {}, auth: true);
  }

  // ── Баннер мероприятия ────────────────────────────────────────────────────

  Future<void> uploadEventBanner(int eventId, String base64Image) async {
    await _post('/api/v1/events/$eventId/banner', {'image': base64Image}, auth: true);
  }

  Future<String> getEventBanner(int eventId) async {
    final res = await _get('/api/v1/events/$eventId/banner', auth: true);
    return (res['image'] as String?) ?? '';
  }

  // ── Пользователи (F-19) ───────────────────────────────────────────────────

  Future<List<UserProfile>> listUsers({String search = '', bool blockedOnly = false}) async {
    final raw = await _rawGet(
        Uri.parse('$baseUrl/api/v1/admin/users?search=$search&blocked=${blockedOnly ? 'true' : 'false'}'),
        headers: _headers(auth: true));
    if (raw is! List) return [];
    return (raw as List).map((e) => UserProfile.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> blockUser(int userId, {String reason = ''}) async {
    await _post('/api/v1/admin/users/$userId/block', {'reason': reason}, auth: true);
  }

  Future<void> unblockUser(int userId) async {
    await _post('/api/v1/admin/users/$userId/unblock', {}, auth: true);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path, {bool auth = false}) async {
    final raw = await _rawGet(Uri.parse('$baseUrl$path'),
        headers: _headers(auth: auth));
    return raw as Map<String, dynamic>;
  }

  Future<dynamic> _rawGet(Uri uri, {Map<String, String>? headers}) async {
    try {
      final res = await http
          .get(uri, headers: headers ?? {})
          .timeout(_timeout);
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
      throw const ApiException('Нет подключения к серверу.');
    } on TimeoutException {
      throw const ApiException('Сервер не отвечает.');
    }
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body, {bool auth = false}
      ) async {
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
      throw const ApiException('Нет подключения к серверу.');
    } on TimeoutException {
      throw const ApiException('Сервер не отвечает.');
    }
  }

  Future<Map<String, dynamic>> _postEmpty(
      String path, {bool auth = false}
      ) async {
    try {
      final res = await http
          .post(Uri.parse('$baseUrl$path'), headers: _headers(auth: auth))
          .timeout(_timeout);
      if (res.statusCode == 401 && auth && !_isRefreshing) {
        return _retryAfterRefresh(() async {
          final r2 = await http
              .post(Uri.parse('$baseUrl$path'), headers: _headers(auth: true))
              .timeout(_timeout);
          return _handle(r2) as Map<String, dynamic>;
        });
      }
      return _handle(res) as Map<String, dynamic>;
    } on SocketException {
      throw const ApiException('Нет подключения к серверу.');
    } on TimeoutException {
      throw const ApiException('Сервер не отвечает.');
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
    throw ApiException(_extractError(res.body), statusCode: res.statusCode);
  }

  String _extractError(String body,
      {String fallback = 'Произошла ошибка'}) {
    try {
      final j = jsonDecode(body);
      if (j is Map<String, dynamic> && j['message'] is String) {
        return j['message'] as String;
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }
}