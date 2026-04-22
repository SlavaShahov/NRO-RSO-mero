import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/event.dart';
import '../models/user.dart';
import '../providers/events_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';

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
        final isClosed = e.message.contains('закрыта') ||
            e.message.contains('менее') || e.message.contains('3 раб');
        if (isClosed) {
          setState(() => _error = e.message);
        } else {
          if (mounted) {
            context.read<EventsProvider>()
                .updateEventRegistrationStatus(event.id, 'registered');
          }
          setState(() {
            _error = 'Вы уже зарегистрированы на это мероприятие';
            _qrLoaded = false;
          });
          _loadExistingQr(event.id);
        }
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = 'Ошибка регистрации. Попробуйте позже.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Проверяем прошло ли мероприятие: сравниваем дату+время с текущим моментом
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
    } catch (_) {
      return false;
    }
  }

  /// Закрыта ли регистрация (3 рабочих дня до мероприятия, до 23:59:59)
  bool _isRegDeadlinePassed(EventItem event) {
    try {
      final parts = event.eventDate.split('-');
      if (parts.length < 3) return false;
      var d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      int sub = 0;
      while (sub < 3) {
        d = d.subtract(const Duration(days: 1));
        if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) sub++;
      }
      final deadline = DateTime(d.year, d.month, d.day, 23, 59, 59);
      return DateTime.now().isAfter(deadline);
    } catch (_) {
      return false;
    }
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

    // Показываем кнопку регистрации только если:
    // 1. Ещё не зарегистрирован
    // 2. Требуется регистрация
    // 3. Мероприятие ещё не прошло
    // 4. Дедлайн регистрации не прошёл
    final isRegClosed = _isRegDeadlinePassed(event);
    final canRegister = !alreadyRegistered &&
        event.isRegistrationRequired &&
        !isPast &&
        !isRegClosed;

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
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Icon(Icons.event, size: 80, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 12),

          // Статус регистрации
          if (alreadyRegistered)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(30)),
              child: const Text('Вы зарегистрированы ✓',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            )
          else if (isRegClosed && !isPast)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300)),
              child: Row(children: [
                Icon(Icons.lock_clock_outlined,
                    color: Colors.orange.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Регистрация закрыта — срок прошёл',
                    style: TextStyle(color: Colors.orange.shade700, fontSize: 13))),
              ]),
            )
          else if (isPast)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(30)),
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
                style: const TextStyle(
                    color: Colors.black54, fontSize: 14, height: 1.5)),
          ],

          const SizedBox(height: 20),

          // Таймер / статус
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
              child: const Center(
                child: Text('Мероприятие уже прошло',
                    style: TextStyle(color: Colors.black45,
                        fontWeight: FontWeight.w500)),
              ),
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
                  QrImageView(data: _qrCode!, size: 240,
                      backgroundColor: Colors.white),
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
                  // Мероприятие прошло, не зарегистрирован
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
                        style: TextStyle(
                            color: Colors.orange.shade800, fontSize: 13)),
                  ),
                ),

              // Кнопка — только если можно зарегистрироваться
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
  Widget build(BuildContext context) {
    return Container(
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
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 2),
    child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
  );
}