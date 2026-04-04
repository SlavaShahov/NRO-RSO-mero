import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isScanning = true;
  bool _isProcessing = false;
  String? _error;
  Map<String, dynamic>? _scanResult;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_isScanning || _isProcessing) return;

    final qrCode = capture.barcodes.first.rawValue;
    if (qrCode == null) return;

    setState(() {
      _isScanning = false;
      _isProcessing = true;
      _error = null;
    });

    try {
      final api = context.read<AuthProvider>().api;
      final result = await api.scanAttendance(qrCode);
      setState(() => _scanResult = result);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isScanning = true;
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Сканировать QR-код'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          if (_isScanning)
            MobileScanner(controller: _controller, onDetect: _onDetect),

          if (_isProcessing)
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          if (_error != null)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              ),
            ),

          if (_scanResult != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 380,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: Text("Посещение отмечено", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                      child: const Text("Готово"),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}