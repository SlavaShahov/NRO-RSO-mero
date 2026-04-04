import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/event.dart';
import '../providers/events_provider.dart';
import '../providers/auth_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EventsProvider>();
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final events = provider.events;

    final greeting = user != null && user.firstName.isNotEmpty
        ? 'Привет, ${user.firstName}!'
        : 'Мероприятия';

    return Scaffold(
      appBar: AppBar(
        title: Text(greeting),
        actions: [
          if (user?.isManager ?? false)
            IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: () => Navigator.pushNamed(context, '/scanner')),
          IconButton(icon: const Icon(Icons.refresh), onPressed: provider.refreshEvents),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: provider.refreshEvents,
        child: provider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : provider.error != null
            ? Center(child: Text(provider.error!))
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: provider.setSearchQuery,
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(text: 'Все', active: provider.selectedType.isEmpty, onTap: () => provider.setTypeFilter('')),
                  _FilterChip(text: 'Спорт', active: provider.selectedType == 'sport', onTap: () => provider.setTypeFilter('sport')),
                  _FilterChip(text: 'Культура', active: provider.selectedType == 'culture', onTap: () => provider.setTypeFilter('culture')),
                  _FilterChip(text: 'Обучение', active: provider.selectedType == 'education', onTap: () => provider.setTypeFilter('education')),
                  _FilterChip(text: 'Штаб', active: provider.selectedType == 'headquarters', onTap: () => provider.setTypeFilter('headquarters')),
                  _FilterChip(text: 'Трудовое', active: provider.selectedType == 'labor', onTap: () => provider.setTypeFilter('labor')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (events.isEmpty)
              const Center(child: Text('Нет мероприятий', style: TextStyle(color: Colors.grey)))
            else
              ...events.map((e) => _EventCard(event: e)),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({required this.text, required this.active, required this.onTap});

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
        child: Text(text, style: TextStyle(color: active ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventItem event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/event', arguments: event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 60,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Text(event.dayStr, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                  Text(event.monthStr, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(event.location, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                  const SizedBox(height: 6),
                  if (event.hasRegistration)
                    Text(event.isAttended ? '✓ Посетил' : '✓ Зарегистрирован', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600))
                  else
                    Text('${event.participantsCount} участников', style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}