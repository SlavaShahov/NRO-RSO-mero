import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class AvatarService {
  static final AvatarService _instance = AvatarService._();
  factory AvatarService() => _instance;
  AvatarService._();

  static const _prefix = 'avatar_';

  /// Сохранить из файла (пикер галереи/камера) — локально + на сервер
  Future<void> saveFromFile(int userId, File file, {ApiClient? api}) async {
    final bytes = await file.readAsBytes();
    // Сохраняем локально
    await saveBytes(userId, bytes);
    // Загружаем на сервер чтобы аватар сохранился после переустановки
    if (api != null) {
      try {
        await api.uploadAvatar(bytes);
      } catch (_) {
        // Не блокируем UI если сервер недоступен — аватар уже есть локально
      }
    }
  }

  /// Сохранить из байтов (при загрузке с сервера)
  Future<void> saveBytes(int userId, Uint8List bytes) async {
    final b64 = base64Encode(bytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$userId', b64);
  }

  /// Получить аватарку как байты (null если нет)
  Future<Uint8List?> getBytes(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final b64 = prefs.getString('$_prefix$userId');
    if (b64 == null || b64.isEmpty) return null;
    try { return base64Decode(b64); } catch (_) { return null; }
  }

  /// Удалить локальный кэш аватарки (и на сервере если передан api)
  Future<void> delete(int userId, {ApiClient? api}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$userId');
    if (api != null) {
      try {
        await api.deleteAvatar();
      } catch (_) {}
    }
  }
}