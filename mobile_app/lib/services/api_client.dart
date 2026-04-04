import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/event.dart';
import '../models/user.dart';

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

  final Duration _timeout = const Duration(seconds: 30);

  Future<void> register({required String email, required String password,
    required String firstName, required String lastName,
    String middleName = '', int? unitId, int? unitPositionId}) async {
    final body = <String, dynamic>{'email': email, 'password': password,
      'first_name': firstName, 'last_name': lastName, 'middle_name': middleName};
    if (unitId != null) body['unit_id'] = unitId;
    if (unitPositionId != null) body['unit_position_id'] = unitPositionId;
    final res = await _post('/api/v1/auth/register', body, auth: false);
    accessToken = res['access_token'] as String?;
    refreshToken = res['refresh_token'] as String?;
  }

  Future<void> login({required String email, required String password}) async {
    final res = await _post('/api/v1/auth/login',
        {'email': email, 'password': password}, auth: false);
    accessToken = res['access_token'] as String?;
    refreshToken = res['refresh_token'] as String?;
  }

  Future<void> doRefresh() async {
    final token = refreshToken;
    if (token == null) throw const ApiException('Нет refresh-токена');
    final res = await _post('/api/v1/auth/refresh',
        {'refresh_token': token}, auth: false);
    accessToken = res['access_token'] as String?;
    refreshToken = res['refresh_token'] as String?;
  }

  Future<void> logout() async {
    try {
      await _post('/api/v1/auth/logout',
          {'refresh_token': refreshToken ?? ''}, auth: true);
    } catch (_) {}
    accessToken = null;
    refreshToken = null;
  }

  Future<UserProfile> me() async =>
      UserProfile.fromJson(await _get('/api/v1/me', auth: true));

  Future<Map<String, dynamic>> portfolio() async =>
      _get('/api/v1/portfolio', auth: true);

  Future<List<EventItem>> events({String? level, String? type, String? search}) async {
    final params = <String, String>{};
    if (level  != null && level.isNotEmpty)  params['level']  = level;
    if (type   != null && type.isNotEmpty)   params['type']   = type;
    if (search != null && search.isNotEmpty) params['search'] = search;
    final uri = Uri.parse('$baseUrl/api/v1/events').replace(queryParameters: params);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (accessToken != null) headers['Authorization'] = 'Bearer $accessToken';
    final raw = await _rawGet(uri, headers: headers);
    if (raw is! List) return [];
    return raw.map((e) => EventItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> registerToEvent(int eventId) async =>
      _postEmpty('/api/v1/events/$eventId/register', auth: true);

  Future<Map<String, dynamic>> scanAttendance(String qrCode) async =>
      _post('/api/v1/attendance/scan', {'qr_code': qrCode}, auth: true);

  Future<List<HQItem>> listHQs() async {
    final raw = await _rawGet(Uri.parse('$baseUrl/api/v1/hqs'));
    if (raw is! List) return [];
    return raw.map((e) => HQItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<UnitItem>> listUnits(int hqId) async {
    final raw = await _rawGet(Uri.parse('$baseUrl/api/v1/hqs/$hqId/units'));
    if (raw is! List) return [];
    return raw.map((e) => UnitItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<PositionItem>> listPositions() async {
    final raw = await _rawGet(Uri.parse('$baseUrl/api/v1/positions'));
    if (raw is! List) return [];
    return raw.map((e) => PositionItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ── helpers ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path, {bool auth = false}) async =>
      (await _rawGet(Uri.parse('$baseUrl$path'), headers: _headers(auth: auth)))
          as Map<String, dynamic>;

  Future<dynamic> _rawGet(Uri uri, {Map<String, String>? headers}) async {
    try {
      final res = await http.get(uri, headers: headers ?? {}).timeout(_timeout);
      return _handle(res);
    } on SocketException {
      throw ApiException('Нет подключения к серверу ($baseUrl).\nЗапусти docker-compose up');
    } on TimeoutException {
      throw ApiException('Сервер не отвечает (${_timeout.inSeconds}с).\nПроверь docker-compose up');
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {bool auth = false}) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl$path'),
          headers: _headers(auth: auth), body: jsonEncode(body)).timeout(_timeout);
      return _handle(res) as Map<String, dynamic>;
    } on SocketException {
      throw ApiException('Нет подключения к серверу. Запусти docker-compose up');
    } on TimeoutException {
      throw ApiException('Сервер не отвечает. Проверь docker-compose up');
    }
  }

  Future<Map<String, dynamic>> _postEmpty(String path, {bool auth = false}) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl$path'),
          headers: _headers(auth: auth)).timeout(_timeout);
      return _handle(res) as Map<String, dynamic>;
    } on SocketException {
      throw ApiException('Нет подключения к серверу.');
    } on TimeoutException {
      throw ApiException('Сервер не отвечает.');
    }
  }

  Map<String, String> _headers({bool auth = false}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (auth && accessToken != null) h['Authorization'] = 'Bearer $accessToken';
    return h;
  }

  dynamic _handle(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(res.body);
    }
    throw ApiException(_extractError(res.body), statusCode: res.statusCode);
  }

  String _extractError(String body, {String fallback = 'Произошла ошибка'}) {
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