import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user.dart';
import '../services/api_client.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({required this.api}) {
    api.onTokenExpired = _doRefresh;
  }

  final ApiClient api;
  final _storage = const FlutterSecureStorage();
  UserProfile? _user;
  bool _loading = true;

  UserProfile? get user    => _user;
  bool get isLoading       => _loading;
  bool get isAuthorized    => _user != null;

  Future<void> tryRestoreSession() async {
    _loading = true;
    notifyListeners();
    try {
      final access  = await _storage.read(key: 'access_token');
      final refresh = await _storage.read(key: 'refresh_token');
      if (access == null || refresh == null) { _loading = false; notifyListeners(); return; }
      api.accessToken  = access;
      api.refreshToken = refresh;
      try {
        _user = await api.me();
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          try {
            await _doRefresh();
            _user = await api.me();
          } catch (_) { await _clear(); }
        } else { await _clear(); }
      }
    } catch (_) { await _clear(); }
    finally { _loading = false; notifyListeners(); }
  }

  Future<void> login(String email, String password) async {
    await api.login(email: email, password: password);
    await _save();
    _user = await api.me();
    notifyListeners();
  }

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
    await api.register(
      email:              email,
      password:           password,
      firstName:          firstName,
      lastName:           lastName,
      middleName:         middleName,
      phone:              phone,
      memberCardNumber:   memberCardNumber,
      memberCardLocation: memberCardLocation,
      unitId:             unitId,
      unitPositionId:     unitPositionId,
      hqId:               hqId,
      hqPositionId:       hqPositionId,
    );
    await _save();
    _user = await api.me();
    notifyListeners();
  }

  Future<void> logout() async {
    await api.logout();
    await _clear();
    _user = null;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    try { _user = await api.me(); notifyListeners(); } catch (_) {}
  }

  Future<void> updateProfile({
    required String lastName,
    required String firstName,
    String middleName         = '',
    String phone              = '',
    String memberCardNumber   = '',
    String memberCardLocation = 'with_user',
  }) async {
    _user = await api.updateProfile(
      lastName:           lastName,
      firstName:          firstName,
      middleName:         middleName,
      phone:              phone,
      memberCardNumber:   memberCardNumber,
      memberCardLocation: memberCardLocation,
    );
    notifyListeners();
  }

  Future<void> _doRefresh() async {
    await api.doRefresh();
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    if (api.accessToken  != null) await _storage.write(key: 'access_token',  value: api.accessToken);
    if (api.refreshToken != null) await _storage.write(key: 'refresh_token', value: api.refreshToken);
  }

  Future<void> _clear() async {
    await _storage.deleteAll();
    api.accessToken = null; api.refreshToken = null;
  }
}