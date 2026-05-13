import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../services/api_client.dart';
import '../screens/notifications_screen.dart';

// ── Background FCM handler — top-level, вне классов ──────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] background: ${message.notification?.title}');
}

// ── FCM инициализация ─────────────────────────────────────────────────────────
class _FcmInit {
  static final _FcmInit _i = _FcmInit._();
  factory _FcmInit() => _i;
  _FcmInit._();
  bool _done = false;

  Future<void> init({
    required Future<void> Function(String) onToken,
    required void Function(RemoteMessage) onForeground,
  }) async {
    if (_done) return;
    _done = true;
    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission(alert: true, sound: true, badge: true);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(onForeground);
    final token = await fcm.getToken();
    debugPrint('[FCM] token: $token');
    if (token != null) await onToken(token);
    fcm.onTokenRefresh.listen((t) async => await onToken(t));
  }
}

// ── Локальные уведомления (foreground без FCM) ────────────────────────────────
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

// ── NotificationsProvider ─────────────────────────────────────────────────────
class NotificationsProvider extends ChangeNotifier {
  NotificationsProvider({required this.api, this.onProfileChanged});

  final ApiClient api;
  final Future<void> Function()? onProfileChanged;
  final _push = _PushService();

  List<AppNotification> notifications = [];
  int unreadCount = 0;
  bool loading = false;
  String? error;

  final Set<int> _shownIds = {};
  final Set<int> _appliedRoles = {};
  Timer? _timer;

  Future<void> startPolling() async {
    await _push.init();

    await _FcmInit().init(
      onToken: (token) async {
        try { await api.registerFcmToken(token); } catch (_) {}
      },
      onForeground: (msg) async {
        // FCM уже показал системное уведомление Android —
        // только обновляем список, не показываем дубль
        await _poll(skipLocalPush: true);
      },
    );

    _timer?.cancel();
    await _initialLoad();
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

  Future<void> _initialLoad() async {
    try {
      final raw = await api.listNotifications();
      for (final n in raw) { _shownIds.add(n.id); }
      notifications = raw;
      unreadCount = raw.where((n) => !n.isRead).length;
      notifyListeners();
    } catch (_) {}
  }

  // skipLocalPush=true когда FCM уже доставил уведомление —
  // избегаем дублирования
  Future<void> _poll({bool skipLocalPush = false}) async {
    try {
      final raw = await api.listNotifications();
      bool hasNew = false;
      bool needProfileRefresh = false;
      for (final n in raw) {
        if (!n.isRead && !_shownIds.contains(n.id)) {
          _shownIds.add(n.id);
          hasNew = true;
          if (!skipLocalPush) await _push.show(n.id, n.title, n.body);
        }
        if (!n.isRead &&
            (n.typeCode == 'position_change_approved' ||
                n.typeCode == 'hq_staff_approved') &&
            !_appliedRoles.contains(n.id)) {
          _appliedRoles.add(n.id);
          needProfileRefresh = true;
        }
      }
      if (needProfileRefresh) await onProfileChanged?.call();
      notifications = raw;
      unreadCount = raw.where((n) => !n.isRead).length;
      if (hasNew || needProfileRefresh) notifyListeners();
    } catch (_) {}
  }

  Future<void> load() async {
    loading = true; error = null; notifyListeners();
    try {
      final raw = await api.listNotifications();
      for (final n in raw) { _shownIds.add(n.id); }
      notifications = raw;
      unreadCount = raw.where((n) => !n.isRead).length;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false; notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    try {
      await api.markAllNotificationsRead();
      notifications = notifications.map((n) => AppNotification(
        id: n.id, typeCode: n.typeCode, title: n.title,
        body: n.body, refId: n.refId, refType: n.refType,
        refApproved: n.refApproved, isRead: true, createdAt: n.createdAt,
      )).toList();
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
          id: n.id, typeCode: n.typeCode, title: n.title,
          body: n.body, refId: n.refId, refType: n.refType,
          refApproved: n.refApproved, isRead: true, createdAt: n.createdAt,
        );
        if (unreadCount > 0) unreadCount--;
        notifyListeners();
      }
    } catch (_) {}
  }
}