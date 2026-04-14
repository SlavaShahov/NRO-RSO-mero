import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/event.dart';
import '../providers/events_provider.dart';
import '../providers/auth_provider.dart';
import '../screens/notifications_screen.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EventsProvider>().loadEvents();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Открываем карточку мероприятия и после возврата обновляем список
  /// чтобы статус регистрации сразу отразился в ленте
  Future<void> _openEvent(BuildContext context, EventItem event) async {
    await Navigator.pushNamed(context, '/event', arguments: event);
    // После возврата из карточки — ничего не делаем:
    // EventsProvider.updateEventRegistrationStatus уже обновил статус
    // прямо в момент регистрации, без перезагрузки всего списка
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EventsProvider>();
    final auth     = context.watch<AuthProvider>();
    final user     = auth.user;
    final events   = provider.events;

    final greeting = user != null && user.firstName.isNotEmpty
        ? 'Привет, ${user.firstName}!'
        : 'Мероприятия';

    return Scaffold(
      appBar: AppBar(
        title: Text(greeting),
        actions: [
          const NotificationBell(),
          if (user?.isManager ?? false)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => Navigator.pushNamed(context, '/scanner'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: provider.refreshEvents,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: provider.refreshEvents,
        child: provider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : provider.error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off,
                        size: 48, color: Colors.black26),
                    const SizedBox(height: 12),
                    Text(provider.error!,
                        style: const TextStyle(color: Colors.black54),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                        onPressed: provider.refreshEvents,
                        child: const Text('Повторить')),
                  ]))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Поиск мероприятий...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                        ),
                        onChanged: provider.setSearchQuery,
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          _Chip(text: 'Все',
                              active: provider.selectedType.isEmpty,
                              onTap: () => provider.setTypeFilter('')),
                          _Chip(text: 'Спорт',
                              active: provider.selectedType == 'sport',
                              onTap: () => provider.setTypeFilter('sport')),
                          _Chip(text: 'Культура',
                              active: provider.selectedType == 'culture',
                              onTap: () => provider.setTypeFilter('culture')),
                          _Chip(text: 'Обучение',
                              active: provider.selectedType == 'education',
                              onTap: () => provider.setTypeFilter('education')),
                          _Chip(text: 'Штаб',
                              active: provider.selectedType == 'headquarters',
                              onTap: () => provider.setTypeFilter('headquarters')),
                          _Chip(text: 'Трудовое',
                              active: provider.selectedType == 'labor',
                              onTap: () => provider.setTypeFilter('labor')),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      if (events.isEmpty)
                        const Center(
                          child: Text('Нет мероприятий',
                              style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ...events.map((e) => _EventCard(
                            event: e,
                            onTap: () => _openEvent(context, e))),
                    ],
                  ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.active, required this.onTap});
  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1E3A8A) : const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                color: active ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});
  final EventItem event;
  final VoidCallback onTap;

  bool get _isPast {
    try {
      final dateParts = event.eventDate.split('-');
      final timeParts = event.startTime.split(':');
      if (dateParts.length < 3 || timeParts.length < 2) return false;
      final dt = DateTime(
        int.parse(dateParts[0]), int.parse(dateParts[1]),
        int.parse(dateParts[2]), int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
      return DateTime.now().isAfter(dt);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final past = _isPast;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: past ? Colors.grey.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: past ? Colors.grey.shade200 : Colors.black12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Дата
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: past
                  ? Colors.grey.shade200
                  : const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Text(event.dayStr,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: past
                          ? Colors.grey.shade500
                          : const Color(0xFF1E3A8A))),
              Text(event.monthStr, style: const TextStyle(fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 14),
          // Контент
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(event.title,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: past ? Colors.grey.shade600 : Colors.black)),
              const SizedBox(height: 4),
              Text(event.location,
                  style: TextStyle(
                      color: past
                          ? Colors.grey.shade400
                          : Colors.black54,
                      fontSize: 13)),
              const SizedBox(height: 6),
              if (past)
                Text('Завершилось',
                    style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                        fontStyle: FontStyle.italic))
              else if (event.hasRegistration)
                Text(event.isAttended ? '✓ Посетил' : '✓ Зарегистрирован',
                    style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600))
              else
                Text('${event.participantsCount} участников',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }
}