import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/event.dart';
import '../models/user.dart';
import '../providers/events_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/avatar_service.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key});
  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  String? _qrCode;
  bool _busy = false;
  bool _loadingQr = false;
  String? _error;
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _timerStarted = false;
  bool _qrLoaded = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  ApiClient get _api => context.read<AuthProvider>().api;

  Future<void> _loadExistingQr(int eventId) async {
    if (_qrLoaded || _loadingQr) return;
    setState(() => _loadingQr = true);
    try {
      final regs = await _api.myRegistrations();
      final reg = regs.where((r) => r.eventId == eventId).firstOrNull;
      if (reg != null && mounted) {
        setState(() { _qrCode = reg.qrCode; _qrLoaded = true; });
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loadingQr = false);
    }
  }

  void _startCountdown(EventItem event) {
    if (_timerStarted) return;
    _timerStarted = true;
    _timer?.cancel();
    final dateParts = event.eventDate.split('-');
    if (dateParts.length < 3) return;
    final timeParts = event.startTime.split(':');
    if (timeParts.length < 2) return;
    final eventDT = DateTime(
      int.parse(dateParts[0]), int.parse(dateParts[1]),
      int.parse(dateParts[2]), int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );
    void tick() {
      final diff = eventDT.difference(DateTime.now());
      if (mounted) setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
    }
    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _register(EventItem event) async {
    if (_busy) return;

    // Показываем диалог подтверждения с аватаром пользователя
    final confirmed = await _showConfirmDialog(event);
    if (confirmed != true) return;

    setState(() { _busy = true; _error = null; });
    try {
      final result = await _api.registerToEvent(event.id);
      final qr = result['qr_code'] as String?;
      setState(() { _qrCode = qr; _qrLoaded = true; });
      if (mounted) {
        context.read<EventsProvider>()
            .updateEventRegistrationStatus(event.id, 'registered');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Вы успешно зарегистрированы!'),
              backgroundColor: Colors.green),
        );
      }
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        if (mounted) {
          context.read<EventsProvider>()
              .updateEventRegistrationStatus(event.id, 'registered');
        }
        setState(() {
          _error = e.message.contains('закрыта')
              ? e.message
              : 'Вы уже зарегистрированы на это мероприятие';
          _qrLoaded = false;
        });
        _loadExistingQr(event.id);
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = 'Ошибка регистрации. Попробуйте позже.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Диалог подтверждения регистрации с аватаром пользователя
  Future<bool?> _showConfirmDialog(EventItem event) async {
    final user = context.read<AuthProvider>().user;
    Uint8List? avatarBytes;
    if (user != null) {
      avatarBytes = await AvatarService().getBytes(user.id);
    }

    if (!mounted) return null;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Аватар пользователя
            if (user != null) ...[
              avatarBytes != null
                  ? CircleAvatar(
                radius: 40,
                backgroundImage: MemoryImage(avatarBytes),
              )
                  : CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFFEAF2FF),
                child: Text(
                  user.firstName.isNotEmpty
                      ? user.firstName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontSize: 32, color: Color(0xFF1E3A8A),
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              Text(user.fullName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 17)),
              if (user.positionName.isNotEmpty)
                Text(user.positionName,
                    style: const TextStyle(
                        color: Color(0xFF1E3A8A), fontSize: 13)),
              if (user.unitName.isNotEmpty)
                Text(user.unitName,
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
            ],

            // Мероприятие
            const Text('Зарегистрироваться на',
                style: TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 4),
            Text(event.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.calendar_today, size: 14, color: Colors.black45),
              const SizedBox(width: 4),
              Text('${event.eventDate}, ${event.startTimeShort}',
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
            ]),
            if (event.location.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.location_on, size: 14, color: Colors.black45),
                const SizedBox(width: 4),
                Flexible(child: Text(event.location,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, fontSize: 13))),
              ]),
            ],
            const SizedBox(height: 20),

            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Зарегистрироваться'),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  bool _isEventPast(EventItem event) {
    try {
      final dateParts = event.eventDate.split('-');
      final timeParts = event.startTime.split(':');
      if (dateParts.length < 3 || timeParts.length < 2) return false;
      final eventDT = DateTime(
        int.parse(dateParts[0]), int.parse(dateParts[1]),
        int.parse(dateParts[2]), int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
      return DateTime.now().isAfter(eventDT);
    } catch (_) { return false; }
  }

  @override
  Widget build(BuildContext context) {
    final event = ModalRoute.of(context)?.settings.arguments;
    if (event == null || event is! EventItem) {
      return const Scaffold(body: Center(child: Text('Мероприятие не найдено')));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCountdown(event);
      if (event.hasRegistration && !_qrLoaded && !_loadingQr) {
        _loadExistingQr(event.id);
      }
    });

    final days    = _remaining.inDays;
    final hours   = _remaining.inHours.remainder(24);
    final minutes = _remaining.inMinutes.remainder(60);
    final seconds = _remaining.inSeconds.remainder(60);

    final alreadyRegistered = event.hasRegistration || _qrCode != null;
    final isPast            = _isEventPast(event);
    final canRegister       = !alreadyRegistered &&
        event.isRegistrationRequired && !isPast;

    return Scaffold(
      appBar: AppBar(
        title: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Баннер
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
            ),
            child: const Center(child: Icon(Icons.event, size: 80, color: Colors.white70)),
          ),
          const SizedBox(height: 12),

          if (alreadyRegistered)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                  color: Colors.green, borderRadius: BorderRadius.circular(30)),
              child: const Text('Вы зарегистрированы ✓',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            )
          else if (isPast)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade400, borderRadius: BorderRadius.circular(30)),
              child: const Text('Мероприятие завершено',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),

          const SizedBox(height: 16),
          Text(event.title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),

          _info(Icons.calendar_today, '${event.eventDate}, ${event.startTime}'),
          if (event.location.isNotEmpty) _info(Icons.location_on, event.location),
          _info(Icons.category, '${event.levelLabel} • ${event.typeLabel}'),
          _info(Icons.people, '${event.participantsCount} зарегистрировано'),

          if (event.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('О мероприятии',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(event.description,
                style: const TextStyle(color: Colors.black54, fontSize: 14, height: 1.5)),
          ],

          const SizedBox(height: 20),

          if (!isPast && _remaining > Duration.zero)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                const Text('До начала мероприятия',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _Counter(value: days.toString().padLeft(2, '0'),    unit: 'ДН'),
                  const _Sep(),
                  _Counter(value: hours.toString().padLeft(2, '0'),   unit: 'ЧАС'),
                  const _Sep(),
                  _Counter(value: minutes.toString().padLeft(2, '0'), unit: 'МИН'),
                  const _Sep(),
                  _Counter(value: seconds.toString().padLeft(2, '0'), unit: 'СЕК'),
                ]),
              ]),
            )
          else if (isPast)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12)),
              child: const Center(child: Text('Мероприятие уже прошло',
                  style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w500))),
            ),

          const SizedBox(height: 24),

          // QR-блок
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(children: [
              const Text('Ваш персональный QR-код',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 16),

              if (_loadingQr)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                )
              else if (_qrCode != null && _qrCode!.isNotEmpty)
                Column(children: [
                  QrImageView(data: _qrCode!, size: 240, backgroundColor: Colors.white),
                  const SizedBox(height: 8),
                  const Text('Предъяви этот код на входе',
                      style: TextStyle(color: Colors.black45, fontSize: 12)),
                ])
              else if (alreadyRegistered)
                  Column(children: [
                    const Icon(Icons.check_circle, size: 64, color: Colors.green),
                    const SizedBox(height: 8),
                    const Text('Вы зарегистрированы',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      icon: const Icon(Icons.qr_code),
                      label: const Text('Показать QR-код'),
                      onPressed: () => _loadExistingQr(event.id),
                    ),
                  ])
                else if (isPast)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Column(children: [
                        Icon(Icons.event_busy, size: 48, color: Colors.black26),
                        SizedBox(height: 8),
                        Text('Регистрация закрыта',
                            style: TextStyle(color: Colors.black45, fontSize: 14)),
                      ]),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Зарегистрируйтесь чтобы получить QR-код',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orange.shade800, fontSize: 13)),
                  ),
                ),

              if (canRegister) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _register(event),
                    child: _busy
                        ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                        : const Text('Зарегистрироваться'),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 4),
    child: Row(children: [
      Icon(icon, size: 18, color: Colors.black45),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
    ]),
  );
}

class _Counter extends StatelessWidget {
  const _Counter({required this.value, required this.unit});
  final String value, unit;
  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(8)),
    child: Column(children: [
      Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      Text(unit, style: const TextStyle(fontSize: 9, color: Colors.black54)),
    ]),
  );
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 2),
    child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
  );
}