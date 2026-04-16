import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

class AvatarService {
  static final AvatarService _instance = AvatarService._();
  factory AvatarService() => _instance;
  AvatarService._();

  static const _prefix = 'avatar_';

  /// Сохранить из файла (пикер галереи/камера)
  Future<void> saveFromFile(int userId, File file) async {
    final bytes = await file.readAsBytes();
    await saveBytes(userId, bytes);
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

  /// Удалить локальный кэш аватарки
  Future<void> delete(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$userId');
  }
}