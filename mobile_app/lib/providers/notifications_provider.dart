import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../services/api_client.dart';
import '../screens/notifications_screen.dart';

/// Сервис системных push-уведомлений (flutter_local_notifications)
class _PushService {
  static final _PushService _i = _PushService._();
  factory _PushService() => _i;
  _PushService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios));
    // Android 13+ — запрашиваем разрешение на уведомления
    await _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  Future<void> show(int id, String title, String body) async {
    if (!_ready) await init();
    const android = AndroidNotificationDetails(
      'rso_channel',
      'РСО Уведомления',
      channelDescription: 'Уведомления приложения РСО',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const ios = DarwinNotificationDetails(
        presentAlert: true, presentBadge: true, presentSound: true);
    await _plugin.show(
        id, title, body, const NotificationDetails(android: android, iOS: ios));
  }
}

class NotificationsProvider extends ChangeNotifier {
  NotificationsProvider({required this.api});

  final ApiClient api;
  final _push = _PushService();

  List<AppNotification> notifications = [];
  int unreadCount = 0;
  bool loading = false;
  String? error;

  // ID уведомлений для которых уже показали системный push
  final Set<int> _shownIds = {};
  Timer? _timer;

  /// Инициализируем push и запускаем polling каждые 30 секунд
  Future<void> startPolling() async {
    await _push.init();
    _timer?.cancel();
    // Сразу при старте — загружаем все существующие и регистрируем как «уже показанные»
    await _initialLoad();
    // Затем каждые 30 секунд проверяем новые
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  /// При первом запуске — помечаем все существующие уведомления
  /// как «уже виденные» чтобы не спамить при старте приложения
  Future<void> _initialLoad() async {
    try {
      final raw = await api.listNotifications();
      for (final n in raw) {
        _shownIds.add(n.id);
      }
      notifications = raw;
      unreadCount = raw.where((n) => !n.isRead).length;
      notifyListeners();
    } catch (_) {}
  }

  /// Polling — проверяем новые уведомления и показываем push
  Future<void> _poll() async {
    try {
      final raw = await api.listNotifications();
      bool hasNew = false;
      for (final n in raw) {
        // Если это новое непрочитанное уведомление — показываем системный push
        if (!n.isRead && !_shownIds.contains(n.id)) {
          _shownIds.add(n.id);
          hasNew = true;
          // Показываем системное уведомление на телефоне
          await _push.show(n.id, n.title, n.body);
        }
      }
      notifications = raw;
      unreadCount = raw.where((n) => !n.isRead).length;
      if (hasNew) notifyListeners();
    } catch (_) {}
  }

  /// Явная загрузка (pull-to-refresh или открытие экрана)
  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final raw = await api.listNotifications();
      // Регистрируем все как виденные
      for (final n in raw) {
        _shownIds.add(n.id);
      }
      notifications = raw;
      unreadCount = raw.where((n) => !n.isRead).length;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    try {
      await api.markAllNotificationsRead();
      notifications = notifications
          .map((n) => AppNotification(
        id: n.id,
        typeCode: n.typeCode,
        title: n.title,
        body: n.body,
        data: n.data,
        isRead: true,
        createdAt: n.createdAt,
      ))
          .toList();
      unreadCount = 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markOneRead(int notifId) async {
    try {
      await api.markNotificationRead(notifId);
      final idx = notifications.indexWhere((n) => n.id == notifId);
      if (idx >= 0 && !notifications[idx].isRead) {
        final n = notifications[idx];
        notifications[idx] = AppNotification(
          id: n.id,
          typeCode: n.typeCode,
          title: n.title,
          body: n.body,
          data: n.data,
          isRead: true,
          createdAt: n.createdAt,
        );
        if (unreadCount > 0) unreadCount--;
        notifyListeners();
      }
    } catch (_) {}
  }
}