import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';

/// Модель уведомления (здесь чтобы api_client мог импортировать)
class AppNotification {
  final int id;
  final String typeCode, title, body;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.typeCode,
    required this.title,
    required this.body,
    this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final rawData = j['data'];
    Map<String, dynamic>? data;
    if (rawData is Map<String, dynamic>) {
      data = rawData;
    } else if (rawData is String && rawData.isNotEmpty && rawData != '{}') {
      try {
        data = jsonDecode(rawData) as Map<String, dynamic>?;
      } catch (_) {}
    }
    return AppNotification(
      id:        j['id']       as int,
      typeCode:  (j['type_code']  ?? '') as String,
      title:     (j['title']      ?? '') as String,
      body:      (j['body']       ?? '') as String,
      data:      data,
      isRead:    (j['is_read']    ?? false) as bool,
      createdAt: DateTime.tryParse((j['created_at'] ?? '') as String)
          ?? DateTime.now(),
    );
  }
}

/// Иконка колокольчика с бейджем непрочитанных
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread =
        context.watch<NotificationsProvider>().unreadCount;
    return Stack(children: [
      IconButton(
        icon: const Icon(Icons.notifications_outlined),
        tooltip: 'Уведомления',
        onPressed: () =>
            Navigator.pushNamed(context, '/notifications'),
      ),
      if (unread > 0)
        Positioned(
          right: 6,
          top: 6,
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
                color: Colors.red, shape: BoxShape.circle),
            child: Center(
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Экран уведомлений
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationsProvider>();
    final user = context.watch<AuthProvider>().user;
    final isAdmin = user?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        actions: [
          if (provider.unreadCount > 0)
            TextButton(
              onPressed: () =>
                  context.read<NotificationsProvider>().markAllRead(),
              child: const Text('Прочитать все',
                  style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : provider.notifications.isEmpty
          ? const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.notifications_none,
              size: 64, color: Colors.black26),
          SizedBox(height: 12),
          Text('Нет уведомлений',
              style: TextStyle(
                  color: Colors.black45, fontSize: 16)),
        ]),
      )
          : RefreshIndicator(
        onRefresh: provider.load,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: provider.notifications.length,
          itemBuilder: (_, i) {
            final n = provider.notifications[i];
            final isHQRequest =
                n.typeCode == 'hq_staff_request' &&
                    isAdmin &&
                    !n.isRead;
            final requestId =
            n.data?['request_id'] is int
                ? n.data!['request_id'] as int
                : null;
            return _NotifTile(
              notif: n,
              onRead: () => context
                  .read<NotificationsProvider>()
                  .markOneRead(n.id),
              onApprove: isHQRequest && requestId != null
                  ? () => _review(context, n.id, requestId, true)
                  : null,
              onReject: isHQRequest && requestId != null
                  ? () => _review(context, n.id, requestId, false)
                  : null,
            );
          },
        ),
      ),
    );
  }

  Future<void> _review(
      BuildContext ctx, int notifId, int requestId, bool approve) async {
    String? comment;
    if (!approve) {
      comment = await showDialog<String>(
        context: ctx,
        builder: (d) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: const Text('Причина отклонения'),
            content: TextField(
              controller: ctrl,
              decoration:
              const InputDecoration(hintText: 'Необязательно'),
              autofocus: true,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d),
                  child: const Text('Отмена')),
              TextButton(
                  onPressed: () => Navigator.pop(d, ctrl.text),
                  child: const Text('Отклонить',
                      style: TextStyle(color: Colors.red))),
            ],
          );
        },
      );
      if (comment == null) return;
    }

    if (!ctx.mounted) return;
    try {
      final api = ctx.read<AuthProvider>().api;
      await api.reviewHQStaffRequest(
        requestId,
        approved: approve,
        comment: comment ?? '',
      );

      if (ctx.mounted) {
        // Помечаем прочитанным сразу
        ctx.read<NotificationsProvider>().markOneRead(notifId);
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content:
          Text(approve ? '✅ Заявка одобрена' : '❌ Заявка отклонена'),
          backgroundColor: approve ? Colors.green : Colors.red,
        ));
        // Перезагружаем список
        ctx.read<NotificationsProvider>().load();
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }
}

class _NotifTile extends StatelessWidget {
  const _NotifTile({
    required this.notif,
    required this.onRead,
    this.onApprove,
    this.onReject,
  });
  final AppNotification notif;
  final VoidCallback onRead;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  IconData get _icon {
    switch (notif.typeCode) {
      case 'hq_staff_request':  return Icons.person_add_outlined;
      case 'hq_staff_approved': return Icons.check_circle_outline;
      case 'hq_staff_rejected': return Icons.cancel_outlined;
      case 'new_event_created': return Icons.event_outlined;
      default:                  return Icons.notifications_outlined;
    }
  }

  Color get _color {
    switch (notif.typeCode) {
      case 'hq_staff_request':  return Colors.orange.shade700;
      case 'hq_staff_approved': return Colors.green.shade700;
      case 'hq_staff_rejected': return Colors.red.shade700;
      case 'new_event_created': return const Color(0xFF1E3A8A);
      default:                  return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: notif.isRead ? Colors.white : const Color(0xFFF0F5FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: notif.isRead
                ? Colors.black12
                : const Color(0xFF1E3A8A).withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: notif.isRead ? null : onRead,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: _color.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: Icon(_icon, color: _color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(notif.title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: notif.isRead
                                      ? Colors.black87
                                      : const Color(0xFF1E3A8A))),
                        ),
                        if (!notif.isRead)
                          Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: Color(0xFF1E3A8A),
                                  shape: BoxShape.circle)),
                      ]),
                      const SizedBox(height: 4),
                      Text(notif.body,
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(_ago(notif.createdAt),
                          style: const TextStyle(
                              color: Colors.black38, fontSize: 11)),
                    ]),
              ),
            ]),
            if (onApprove != null || onReject != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  if (onApprove != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Одобрить'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding:
                            const EdgeInsets.symmetric(vertical: 8)),
                        onPressed: onApprove,
                      ),
                    ),
                  if (onApprove != null && onReject != null)
                    const SizedBox(width: 8),
                  if (onReject != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Отклонить'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding:
                            const EdgeInsets.symmetric(vertical: 8)),
                        onPressed: onReject,
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1)  return 'только что';
    if (d.inMinutes < 60) return '${d.inMinutes} мин. назад';
    if (d.inHours < 24)   return '${d.inHours} ч. назад';
    if (d.inDays < 7)     return '${d.inDays} дн. назад';
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }
}