import '../models/user.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/events_provider.dart';
import '../services/api_client.dart';
import '../screens/notifications_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth   = context.watch<AuthProvider>();
    final events = context.watch<EventsProvider>();
    final user   = auth.user;

    final total      = events.events.length;
    final registered = events.events
        .where((e) => e.userRegistrationStatus == 'registered')
        .length;
    final attended   = events.events
        .where((e) => e.userRegistrationStatus == 'attended')
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление'),
        actions: [
          const NotificationBell(),
          if (context.read<AuthProvider>().user?.canScan == true)
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
                  // ← Исправлено: withValues() вместо withOpacity()
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                      Text(
                          user.positionName.isNotEmpty
                              ? user.positionName
                              : user.roleLabel,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                      if (user.unitName.isNotEmpty)
                        Text(user.unitName,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 14),

          // KPI
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Kpi(value: '$total',      title: 'Всего'),
                _Kpi(value: '$registered', title: 'Зарег.'),
                _Kpi(value: '$attended',   title: 'Посещено'),
              ],
            ),
          ),
          const SizedBox(height: 14),

          const Text('Действия',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 10),

          _ActionCard(
            icon:     Icons.qr_code_scanner,
            title:    'Сканировать QR-код',
            subtitle: 'Отметить посещение участника',
            color:    const Color(0xFF1E3A8A),
            onTap:    () => Navigator.pushNamed(context, '/scanner'),
          ),
          const SizedBox(height: 8),
          _ActionCard(
            icon:     Icons.add_circle_outline,
            title:    'Создать мероприятие',
            subtitle: 'Добавить новое мероприятие',
            color:    Colors.green,
            onTap:    () => _showCreateEventDialog(context, auth.api, events),
          ),
          const SizedBox(height: 8),
          _ActionCard(
            icon:     Icons.refresh,
            title:    'Обновить ленту',
            subtitle: 'Загрузить актуальный список',
            color:    Colors.orange,
            onTap:    () => events.refreshEvents(),
          ),
          const SizedBox(height: 16),

          const Text('Ближайшие мероприятия',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
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
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(e.dayStr,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3A8A),
                                fontSize: 16)),
                        Text(e.monthStr,
                            style: const TextStyle(
                                fontSize: 9, color: Colors.black54)),
                      ],
                    ),
                  ),
                  title: Text(e.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(e.location,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  trailing: e.hasRegistration
                      ? Icon(Icons.check_circle,
                          color: Colors.green.shade400, size: 20)
                      : null,
                  onTap: () =>
                      Navigator.pushNamed(context, '/event', arguments: e),
                )),
        ],
      ),
    );
  }

  void _showCreateEventDialog(
      BuildContext context, ApiClient api, EventsProvider events) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CreateEventSheet(
        api: api,
        onCreated: () => events.refreshEvents(),
      ),
    );
  }
}

// ── Создание мероприятия ──────────────────────────────────────────────────────

class _CreateEventSheet extends StatefulWidget {
  const _CreateEventSheet({required this.api, required this.onCreated});
  final ApiClient api;
  final VoidCallback onCreated;

  @override
  State<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends State<_CreateEventSheet> {
  final _title    = TextEditingController();
  final _desc     = TextEditingController();
  final _location = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  String _levelCode        = 'regional';
  String _typeCode         = 'sport';
  String _participationMode = 'open';
  bool _busy   = false;
  String? _error;

  static const _levels = {
    'regional': 'Региональное',
    'local':    'Вузовское',
    'unit':     'Внутриотрядное',
  };
  static const _types = {
    'sport':        'Спортивное',
    'culture':      'Культурное',
    'education':    'Обучающее',
    'headquarters': 'Штабное',
    'labor':        'Трудовое',
  };
  static const _modes = {
    'open':              'Свободный вход',
    'participants_only': 'Только участники',
    'spectators_only':   'Только зрители',
    'both':              'Участники и зрители',
  };

  @override
  void dispose() {
    _title.dispose(); _desc.dispose(); _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (t != null) setState(() => _time = t);
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Введите название мероприятия'); return;
    }
    if (_date == null || _time == null) {
      setState(() => _error = 'Выберите дату и время'); return;
    }

    setState(() { _busy = true; _error = null; });
    try {
      // ← ИСПРАВЛЕНО: передаём Map вместо именованных параметров
      await widget.api.createEvent(
        title:       _title.text.trim(),
        description: _desc.text.trim(),
        location:    _location.text.trim(),
        eventDate:
            '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
        startTime:
            '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
        levelCode:   _levelCode,
        typeCode:    _typeCode,
      );
      if (mounted) {
        widget.onCreated();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Мероприятие создано!'),
              backgroundColor: Colors.green),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 48, height: 4,
              decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Создать мероприятие',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          _f('Название *', _title),
          _f('Описание', _desc, maxLines: 3),
          _f('Место проведения', _location),

          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(_date == null
                    ? 'Выбрать дату'
                    : '${_date!.day}.${_date!.month}.${_date!.year}'),
                onPressed: _pickDate,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.access_time, size: 18),
                label: Text(_time == null
                    ? 'Выбрать время'
                    : _time!.format(context)),
                onPressed: _pickTime,
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // Уровень
          DropdownButtonFormField<String>(
            initialValue: _levelCode,        // ← исправлено: initialValue вместо value
            decoration: const InputDecoration(
                labelText: 'Уровень',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)))),
            items: _levels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _levelCode = v!),
          ),
          const SizedBox(height: 10),

          // Тип
          DropdownButtonFormField<String>(
            initialValue: _typeCode,         // ← исправлено: initialValue вместо value
            decoration: const InputDecoration(
                labelText: 'Тип',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)))),
            items: _types.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _typeCode = v!),
          ),
          const SizedBox(height: 10),

          // Режим участия
          DropdownButtonFormField<String>(
            initialValue: _participationMode,
            decoration: const InputDecoration(
                labelText: 'Режим участия',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)))),
            items: _modes.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _participationMode = v!),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Создать мероприятие'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _f(String label, TextEditingController ctrl, {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10))),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      );
}

// ── Вспомогательные виджеты ───────────────────────────────────────────────────

class _Kpi extends StatelessWidget {
  const _Kpi({required this.value, required this.title});
  final String value, title;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A8A))),
        Text(title,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ]);
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
  Widget build(BuildContext context) => InkWell(
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
                  // ← Исправлено: withValues() вместо withOpacity()
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ]),
        ),
      );
}