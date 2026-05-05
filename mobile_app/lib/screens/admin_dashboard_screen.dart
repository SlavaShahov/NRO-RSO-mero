import 'dart:convert';
import '../models/event.dart';
import '../models/user.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
          const SizedBox(height: 8),
          _ActionCard(
            icon:     Icons.people_outline,
            title:    'Пользователи',
            subtitle: 'Поиск и блокировка',
            color:    Colors.purple,
            onTap:    () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => UsersManagementScreen(api: auth.api))),
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
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (e.hasRegistration)
                  Icon(Icons.check_circle, color: Colors.green.shade400, size: 20),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Редактировать',
                  onPressed: () => _showEditEventDialog(context, auth.api, events, e),
                ),
                IconButton(
                  icon: Icon(Icons.cancel_outlined, size: 18, color: Colors.red.shade400),
                  tooltip: 'Отменить',
                  onPressed: () => _confirmCancel(context, auth.api, events, e),
                ),
              ]),
              onTap: () =>
                  Navigator.pushNamed(context, '/event', arguments: e),
            )),
        ],
      ),
    );
  }

  void _showEditEventDialog(BuildContext context, ApiClient api,
      EventsProvider events, EventItem event) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditEventSheet(
          api: api, event: event, onSaved: () => events.refreshEvents()),
    );
  }

  void _confirmCancel(BuildContext context, ApiClient api,
      EventsProvider events, EventItem event) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Отменить мероприятие?'),
      content: Text('«${event.title}» будет отмечено как отменённое.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Нет')),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              await api.cancelEvent(event.id);
              events.refreshEvents();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Мероприятие отменено'),
                      backgroundColor: Colors.orange));
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка: \$e')));
            }
          },
          child: const Text('Отменить', style: TextStyle(color: Colors.red)),
        ),
      ],
    ));
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
  String? _bannerBase64;

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
      final res = await widget.api.createEvent(
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
      if (_bannerBase64 != null) {
        final eid = res['event_id'] as int? ?? 0;
        if (eid > 0) try { await widget.api.uploadEventBanner(eid, _bannerBase64!); } catch (_) {}
      }
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

          GestureDetector(
            onTap: () async {
              final p = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
              if (p == null) return;
              setState(() async => _bannerBase64 = base64Encode(await p.readAsBytes()));
            },
            child: Container(
              height: 120, width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(12),
                image: _bannerBase64 != null
                    ? DecorationImage(
                    image: MemoryImage(base64Decode(_bannerBase64!)),
                    fit: BoxFit.cover)
                    : null,
              ),
              child: _bannerBase64 == null
                  ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_photo_alternate_outlined, size: 32, color: Color(0xFF1E3A8A)),
                SizedBox(height: 4),
                Text('Добавить баннер', style: TextStyle(color: Color(0xFF1E3A8A), fontSize: 12)),
              ])
                  : Align(alignment: Alignment.topRight,
                  child: Padding(padding: const EdgeInsets.all(6),
                      child: GestureDetector(
                          onTap: () => setState(() => _bannerBase64 = null),
                          child: Container(
                            decoration: BoxDecoration(color: Colors.black54,
                                borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          )))),
            ),
          ),
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
            value: _levelCode,        // ← исправлено: initialValue вместо value
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
            value: _typeCode,         // ← исправлено: initialValue вместо value
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
            value: _participationMode,
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

// ── Редактирование мероприятия ────────────────────────────────────────────────

class _EditEventSheet extends StatefulWidget {
  const _EditEventSheet({required this.api, required this.event, required this.onSaved});
  final ApiClient api;
  final EventItem event;
  final VoidCallback onSaved;
  @override State<_EditEventSheet> createState() => _EditEventSheetState();
}

class _EditEventSheetState extends State<_EditEventSheet> {
  late final _title    = TextEditingController(text: widget.event.title);
  late final _desc     = TextEditingController(text: widget.event.description);
  late final _location = TextEditingController(text: widget.event.location);
  late DateTime _date;
  late TimeOfDay _time;
  late String _levelCode;
  late String _typeCode;
  bool _busy = false;
  String? _error;
  String? _bannerBase64;

  static const _levels = {'regional':'Региональное','local':'Вузовское','unit':'Внутриотрядное'};
  static const _types  = {'sport':'Спортивное','culture':'Культурное','education':'Обучающее','headquarters':'Штабное','labor':'Трудовое'};

  @override
  void initState() {
    super.initState();
    final d = widget.event.eventDate.split('-');
    _date = d.length == 3 ? DateTime(int.parse(d[0]), int.parse(d[1]), int.parse(d[2]))
        : DateTime.now().add(const Duration(days: 7));
    final t = widget.event.startTime.split(':');
    _time = t.length >= 2 ? TimeOfDay(hour: int.parse(t[0]), minute: int.parse(t[1]))
        : const TimeOfDay(hour: 10, minute: 0);
    _levelCode = _levels.containsKey(widget.event.levelCode) ? widget.event.levelCode : 'regional';
    _typeCode  = _types.containsKey(widget.event.typeCode) ? widget.event.typeCode : 'sport';
    _bannerBase64 = widget.event.bannerBase64;
    if (_bannerBase64 == null || _bannerBase64!.isEmpty) _loadBanner();
  }

  Future<void> _loadBanner() async {
    try {
      final b = await widget.api.getEventBanner(widget.event.id);
      if (mounted && b.isNotEmpty) setState(() => _bannerBase64 = b);
    } catch (_) {}
  }

  @override
  void dispose() { _title.dispose(); _desc.dispose(); _location.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) { setState(() => _error = 'Введите название'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.api.updateEvent(
        id: widget.event.id,
        title: _title.text.trim(), description: _desc.text.trim(),
        location: _location.text.trim(),
        eventDate: '${_date.year}-${_date.month.toString().padLeft(2,'0')}-${_date.day.toString().padLeft(2,'0')}',
        startTime: '${_time.hour.toString().padLeft(2,'0')}:${_time.minute.toString().padLeft(2,'0')}',
        levelCode: _levelCode, typeCode: _typeCode,
      );
      if (_bannerBase64 != null && _bannerBase64 != widget.event.bannerBase64) {
        try { await widget.api.uploadEventBanner(widget.event.id, _bannerBase64!); } catch (_) {}
      }
      if (mounted) {
        widget.onSaved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Сохранено'), backgroundColor: Colors.green));
      }
    } on ApiException catch (e) { setState(() => _error = e.message); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16),
    child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 48, height: 4, decoration: BoxDecoration(
          color: Colors.black12, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 16),
      const Text('Редактировать мероприятие',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      // Баннер
      GestureDetector(
        onTap: () async {
          final p = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
          if (p == null) return;
          setState(() async => _bannerBase64 = base64Encode(await p.readAsBytes()));
        },
        child: Container(
          height: 120, width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(12),
            image: _bannerBase64 != null && _bannerBase64!.isNotEmpty
                ? DecorationImage(image: MemoryImage(base64Decode(_bannerBase64!)), fit: BoxFit.cover)
                : null,
          ),
          child: _bannerBase64 == null || _bannerBase64!.isEmpty
              ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_photo_alternate_outlined, size: 32, color: Color(0xFF1E3A8A)),
            SizedBox(height: 4),
            Text('Изменить баннер', style: TextStyle(color: Color(0xFF1E3A8A), fontSize: 12)),
          ])
              : Align(alignment: Alignment.topRight,
              child: Padding(padding: const EdgeInsets.all(6),
                  child: GestureDetector(
                      onTap: () => setState(() => _bannerBase64 = null),
                      child: Container(
                        decoration: BoxDecoration(color: Colors.black54,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      )))),
        ),
      ),
      _f('Название *', _title),
      _f('Описание', _desc, maxLines: 3),
      _f('Место проведения', _location),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text('${_date.day}.${_date.month}.${_date.year}'),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _date,
                firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => _date = d);
          },
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          icon: const Icon(Icons.access_time, size: 18),
          label: Text(_time.format(context)),
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: _time);
            if (t != null) setState(() => _time = t);
          },
        )),
      ]),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _levelCode,
        decoration: const InputDecoration(labelText: 'Уровень',
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)))),
        items: _levels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) => setState(() => _levelCode = v!),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _typeCode,
        decoration: const InputDecoration(labelText: 'Тип',
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)))),
        items: _types.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) => setState(() => _typeCode = v!),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(height: 20, width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Сохранить изменения'),
        ),
      ),
    ])),
  );

  Widget _f(String label, TextEditingController ctrl, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: ctrl, maxLines: maxLines,
        decoration: InputDecoration(labelText: label,
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12))),
  );
}

// ── Управление пользователями (F-19) ─────────────────────────────────────────

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key, required this.api});
  final ApiClient api;
  @override State<UsersManagementScreen> createState() => _UsersManagementState();
}

class _UsersManagementState extends State<UsersManagementScreen> {
  List<UserProfile> _users = [];
  bool _loading = false;
  bool _blockedOnly = false;
  final _search = TextEditingController();

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final u = await widget.api.listUsers(search: _search.text.trim(), blockedOnly: _blockedOnly);
      if (mounted) setState(() => _users = u);
    } catch (_) {}
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _block(UserProfile u) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(context: context,
        builder: (_) => AlertDialog(
          title: Text('Заблокировать ${u.fullName}?'),
          content: TextField(controller: ctrl, autofocus: true,
              decoration: const InputDecoration(hintText: 'Причина (необязательно)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(context, ctrl.text),
                child: const Text('Заблокировать', style: TextStyle(color: Colors.red))),
          ],
        ));
    if (reason == null) return;
    try {
      await widget.api.blockUser(u.id, reason: reason);
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${u.fullName} заблокирован'),
              backgroundColor: Colors.red.shade700));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _unblock(UserProfile u) async {
    try {
      await widget.api.unblockUser(u.id);
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${u.fullName} разблокирован'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Пользователи')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Поиск по имени или email',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear),
                  onPressed: () { _search.clear(); _load(); })
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            ),
            onSubmitted: (_) => _load(),
            onChanged: (_) => setState(() {}),
          )),
          const SizedBox(width: 8),
          FilterChip(label: const Text('Блок.'), selected: _blockedOnly,
              onSelected: (v) { setState(() => _blockedOnly = v); _load(); }),
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ]),
      ),
      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_users.isEmpty)
        const Expanded(child: Center(child: Text('Пользователи не найдены',
            style: TextStyle(color: Colors.black54))))
      else
        Expanded(child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _users.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final u = _users[i];
            final blocked = u.isPendingApproval;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: blocked ? Colors.red.shade100 : const Color(0xFFEAF2FF),
                child: Text(u.firstName.isNotEmpty ? u.firstName[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: blocked ? Colors.red.shade700 : const Color(0xFF1E3A8A),
                        fontWeight: FontWeight.bold)),
              ),
              title: Text(u.fullName,
                  style: TextStyle(fontWeight: FontWeight.w600,
                      color: blocked ? Colors.red.shade700 : null)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.email, style: const TextStyle(fontSize: 12)),
                if (u.positionName.isNotEmpty || u.unitName.isNotEmpty)
                  Text([if (u.positionName.isNotEmpty) u.positionName,
                    if (u.unitName.isNotEmpty) u.unitName].join(' • '),
                      style: const TextStyle(fontSize: 11, color: Colors.black45)),
                if (blocked) const Text('ЗАБЛОКИРОВАН',
                    style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
              ]),
              trailing: blocked
                  ? TextButton(onPressed: () => _unblock(u),
                  child: const Text('Разблок.', style: TextStyle(color: Colors.green, fontSize: 12)))
                  : TextButton(onPressed: () => _block(u),
                  child: Text('Блок.', style: TextStyle(color: Colors.red.shade700, fontSize: 12))),
            );
          },
        )),
    ]),
  );
}