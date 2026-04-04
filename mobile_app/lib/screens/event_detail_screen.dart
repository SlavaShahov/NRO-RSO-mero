import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/event.dart';
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
  String? _error;
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown(EventItem event) {
    _timer?.cancel();
    final dateParts = event.eventDate.split('-');
    if (dateParts.length < 3) return;
    final timeParts = event.startTime.split(':');
    if (timeParts.length < 2) return;

    final eventDT = DateTime(
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(dateParts[2]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );

    void tick() {
      final diff = eventDT.difference(DateTime.now());
      if (mounted) {
        setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
      }
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _register(EventItem event) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final api = context.read<AuthProvider>().api;
      final result = await api.registerToEvent(event.id);
      final qr = result['qr_code'] as String?;

      setState(() => _qrCode = qr);

      if (mounted) {
        context.read<EventsProvider>().updateEventRegistrationStatus(event.id, 'registered');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вы успешно зарегистрированы!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on ApiException catch (e) {
      String msg = e.message.toLowerCase();
      if (msg.contains("already registered") || e.statusCode == 409) {
        msg = "Вы уже зарегистрированы на это мероприятие";
        if (mounted) {
          context.read<EventsProvider>().updateEventRegistrationStatus(event.id, 'registered');
        }
      } else if (msg.contains("unavailable")) {
        msg = "Регистрация на это мероприятие закрыта";
      }
      setState(() => _error = msg);
    } catch (_) {
      setState(() => _error = 'Ошибка регистрации. Попробуйте позже.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = ModalRoute.of(context)?.settings.arguments;
    if (event == null || event is! EventItem) {
      return const Scaffold(body: Center(child: Text('Мероприятие не найдено')));
    }

    if (_timer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startCountdown(event));
    }

    final days = _remaining.inDays;
    final hours = _remaining.inHours.remainder(24);
    final minutes = _remaining.inMinutes.remainder(60);

    final alreadyRegistered = event.hasRegistration || _qrCode != null;

    return Scaffold(
      appBar: AppBar(title: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
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

          if (alreadyRegistered)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(30)),
              child: const Text("Вы зарегистрированы",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),

          const SizedBox(height: 16),
          Text(event.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),

          _info(Icons.calendar_today, "${event.eventDate}, ${event.startTime}"),
          _info(Icons.location_on, event.location),
          _info(Icons.category, "${event.levelLabel} • ${event.typeLabel}"),

          const SizedBox(height: 20),

          if (_remaining > Duration.zero)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  const Text('До начала мероприятия', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Counter(value: days.toString().padLeft(2, '0'), unit: 'ДН'),
                      const Text(' : ', style: TextStyle(fontSize: 24)),
                      _Counter(value: hours.toString().padLeft(2, '0'), unit: 'ЧАС'),
                      const Text(' : ', style: TextStyle(fontSize: 24)),
                      _Counter(value: minutes.toString().padLeft(2, '0'), unit: 'МИН'),
                    ],
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              children: [
                const Text('Ваш персональный QR-код', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                if (_qrCode != null)
                  QrImageView(data: _qrCode!, size: 240, backgroundColor: Colors.white)
                else if (alreadyRegistered)
                  const Icon(Icons.check_circle, size: 80, color: Colors.green)
                else
                  const Text('Зарегистрируйтесь, чтобы получить QR-код',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),

                if (!alreadyRegistered && event.isRegistrationRequired)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ElevatedButton(
                      onPressed: _busy ? null : () => _register(event),
                      child: _busy
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Зарегистрироваться'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 20, color: Colors.black54),
      const SizedBox(width: 10),
      Expanded(child: Text(text)),
    ]),
  );
}

class _Counter extends StatelessWidget {
  final String value;
  final String unit;
  const _Counter({required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(unit, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ]),
    );
  }
}