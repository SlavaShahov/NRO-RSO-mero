import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/events_provider.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth   = context.watch<AuthProvider>();
    final events = context.watch<EventsProvider>();
    final user   = auth.user;

    // Считаем статистику из реальных событий
    final total      = events.events.length;
    final registered = events.events
        .where((e) => e.userRegistrationStatus == 'registered')
        .length;
    final attended = events.events
        .where((e) => e.userRegistrationStatus == 'attended')
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Сканировать QR',
            onPressed: () => Navigator.pushNamed(context, '/scanner'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: () => events.refreshEvents(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Карточка пользователя
          if (user != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A8A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor:
                  Colors.white.withOpacity(0.2),
                  child: Text(
                    user.firstName.isNotEmpty
                        ? user.firstName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(user.fullName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                          Text(
                            user.positionName.isNotEmpty
                                ? user.positionName
                                : user.roleCode,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13),
                          ),
                          if (user.unitName.isNotEmpty)
                            Text(user.unitName,
                                style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12)),
                        ])),
              ]),
            ),
          const SizedBox(height: 14),

          // KPI по мероприятиям
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Kpi(value: '$total', title: 'Всего событий'),
                _Kpi(
                    value: '$registered',
                    title: 'Зарег. вами'),
                _Kpi(
                    value: '$attended',
                    title: 'Посещено'),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Быстрые действия
          const Text('Быстрые действия',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 10),

          _ActionCard(
            icon: Icons.qr_code_scanner,
            title: 'Сканировать QR-код',
            subtitle: 'Отметить посещение участника',
            color: const Color(0xFF1E3A8A),
            onTap: () =>
                Navigator.pushNamed(context, '/scanner'),
          ),
          const SizedBox(height: 8),
          _ActionCard(
            icon: Icons.refresh,
            title: 'Обновить ленту',
            subtitle: 'Загрузить актуальный список мероприятий',
            color: Colors.green,
            onTap: () => events.refreshEvents(),
          ),
          const SizedBox(height: 16),

          // Список ближайших мероприятий
          const Text('Ближайшие мероприятия',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 8),

          if (events.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (events.events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Нет доступных мероприятий',
                  style: TextStyle(color: Colors.black54)),
            )
          else
            ...events.events.take(5).map((e) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    children: [
                      Text(e.dayStr,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E3A8A),
                              fontSize: 16)),
                      Text(e.monthStr,
                          style: const TextStyle(
                              fontSize: 9,
                              color: Colors.black54)),
                    ]),
              ),
              title: Text(e.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(e.location,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
              trailing: e.hasRegistration
                  ? Icon(Icons.check_circle,
                  color: Colors.green.shade400,
                  size: 20)
                  : null,
              onTap: () => Navigator.pushNamed(
                  context, '/event',
                  arguments: e),
            )),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.value, required this.title});
  final String value;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value,
          style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A8A))),
      Text(title,
          style: const TextStyle(
              fontSize: 11, color: Colors.black54)),
    ]);
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13)),
                  ])),
          const Icon(Icons.chevron_right,
              color: Colors.black38),
        ]),
      ),
    );
  }
}