import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_client.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _ctrl =
  MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _isScanning   = true;
  bool _isProcessing = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_isScanning || _isProcessing) return;
    final qrCode = capture.barcodes.firstOrNull?.rawValue;
    if (qrCode == null) return;

    setState(() {
      _isScanning = false; _isProcessing = true;
      _error = null; _result = null;
    });
    await _ctrl.stop();

    try {
      final api = context.read<AuthProvider>().api;
      final res = await api.scanAttendance(qrCode);
      if (mounted) setState(() => _result = res);
    } on ApiException catch (e) {
      String msg = e.message;
      if (e.statusCode == 409) msg = 'Посещение уже отмечено ранее';
      if (e.statusCode == 404) msg = 'QR-код не найден';
      if (e.statusCode == 403) msg = 'Нет прав для сканирования';
      if (mounted) {
        setState(() { _error = msg; _isScanning = true; });
        await _ctrl.start();
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _isScanning = true; });
        await _ctrl.start();
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _reset() {
    setState(() { _result = null; _error = null; _isScanning = true; });
    _ctrl.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Сканировать QR-код'),
        backgroundColor: Colors.black, foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.flash_on),
              onPressed: () => _ctrl.toggleTorch()),
        ],
      ),
      body: Stack(children: [
        if (_isScanning)
          MobileScanner(controller: _ctrl, onDetect: _onDetect),

        // Рамка прицела
        if (_isScanning && _result == null)
          Center(child: Container(
            width: 260, height: 260,
            decoration: BoxDecoration(
                border: Border.all(color: Colors.blueAccent, width: 3),
                borderRadius: BorderRadius.circular(16)),
          )),

        if (_isScanning && _result == null && !_isProcessing)
          const Positioned(bottom: 130, left: 0, right: 0,
              child: Center(child: Text('Наведи камеру на QR-код участника',
                  style: TextStyle(color: Colors.white70, fontSize: 14)))),

        if (_isProcessing)
          const Center(child: CircularProgressIndicator(color: Colors.white)),

        if (_error != null)
          Positioned(top: 80, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center),
              )),

        // Результат сканирования
        if (_result != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.78),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(children: [
                  // Ручка
                  Container(width: 48, height: 4, margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: Colors.black12,
                          borderRadius: BorderRadius.circular(2))),

                  _buildCard(_result!),
                  const SizedBox(height: 16),

                  Row(children: [
                    Expanded(child: ElevatedButton(
                        onPressed: _reset,
                        child: const Text('Сканировать ещё'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Готово'))),
                  ]),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildCard(Map<String, dynamic> result) {
    final user  = result['user']  as Map<String, dynamic>? ?? {};
    final event = result['event'] as Map<String, dynamic>? ?? {};

    final fullName     = (user['full_name']            ?? '') as String;
    final avatarB64    = (user['avatar_base64']         ?? '') as String;
    final unitName     = (user['unit_name']             ?? '') as String;
    final hqName       = (user['hq_name']               ?? '') as String;
    final positionName = (user['position_name']         ?? '') as String;
    final phone        = (user['phone']                 ?? '') as String;
    final cardNum      = (user['member_card_number']    ?? '') as String;
    final cardLoc      = (user['member_card_location']  ?? 'with_user') as String;
    final eventTitle   = (event['title']                ?? '') as String;
    final eventDate    = (event['event_date']           ?? '') as String;

    // Декодируем аватар из base64 если есть
    Uint8List? avatarBytes;
    if (avatarB64.isNotEmpty) {
      try { avatarBytes = base64Decode(avatarB64); } catch (_) {}
    }

    // Инициалы (Фамилия + Имя)
    final parts = fullName.split(' ').where((p) => p.isNotEmpty).toList();
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'
        : parts.isNotEmpty ? parts[0][0] : '?';

    const blue = Color(0xFF1E3A8A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Галочка + Аватар + ФИО ──────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Аватар
          avatarBytes != null
              ? CircleAvatar(radius: 38,
              backgroundImage: MemoryImage(avatarBytes))
              : CircleAvatar(
            radius: 38,
            backgroundColor: const Color(0xFFEAF2FF),
            child: Text(initials.toUpperCase(),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold,
                    color: blue)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 4),
                  Text('Посещение отмечено',
                      style: TextStyle(color: Colors.green,
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
                const SizedBox(height: 4),
                Text(fullName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 17)),
                if (positionName.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(positionName,
                        style: const TextStyle(
                            color: blue, fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
              ])),
        ]),

        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 10),

        // ── Отряд / штаб ─────────────────────────────────────────────────
        if (unitName.isNotEmpty) _row(Icons.groups_outlined, unitName),
        if (hqName.isNotEmpty)   _row(Icons.school_outlined, hqName),
        if (phone.isNotEmpty)    _row(Icons.phone_outlined, phone),

        // ── Членский билет ────────────────────────────────────────────────
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cardNum.isEmpty ? Colors.grey.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: cardNum.isEmpty ? Colors.black12 : Colors.green.shade200),
          ),
          child: Row(children: [
            Icon(cardLoc == 'in_hq'
                ? Icons.home_work_outlined
                : Icons.card_membership_outlined,
                size: 18,
                color: cardNum.isEmpty ? Colors.black38 : Colors.green.shade700),
            const SizedBox(width: 8),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cardNum.isNotEmpty
                  ? 'Членский билет № $cardNum'
                  : 'Номер билета не указан',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13,
                      color: cardNum.isEmpty ? Colors.black38 : Colors.black87)),
              Text(cardLoc == 'in_hq'
                  ? '📍 В региональном штабе'
                  : '📋 На руках у участника',
                  style: TextStyle(fontSize: 11,
                      color: cardLoc == 'in_hq'
                          ? Colors.orange.shade700
                          : Colors.green.shade700)),
            ])),
          ]),
        ),

        // ── Мероприятие ───────────────────────────────────────────────────
        if (eventTitle.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.event_outlined, size: 16, color: blue),
            const SizedBox(width: 8),
            Expanded(child: Text('$eventTitle  •  $eventDate',
                style: const TextStyle(fontSize: 12, color: Colors.black54))),
          ]),
        ],
      ]),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 16, color: const Color(0xFF1E3A8A)),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 13, color: Colors.black87))),
    ]),
  );
}