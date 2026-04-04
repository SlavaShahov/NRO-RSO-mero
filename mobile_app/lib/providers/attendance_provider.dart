import 'package:flutter/material.dart';
import '../services/api_client.dart';

class AttendanceProvider extends ChangeNotifier {
  ApiClient _api;
  bool _isScanning = false;

  AttendanceProvider({required ApiClient api}) : _api = api;

  bool get isScanning => _isScanning;

  void updateApiClient(ApiClient api) {
    _api = api;
    notifyListeners();
  }

  void updateToken(String? token) {
    _api.accessToken = token;
  }

  Future<Map<String, dynamic>> scanQR(String qrCode) async {
    _isScanning = true;
    notifyListeners();

    try {
      final result = await _api.scanAttendance(qrCode);
      return result;
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }
}