import 'package:flutter/material.dart';

import '../providers/auth_provider.dart';
import '../services/api_client.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});
  final AuthProvider auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _hidden = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final pass = _password.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Введите email и пароль');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.login(email, pass);
      // _AppRoot автоматически перестроится через Provider — Navigator не нужен
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Ошибка сети. Проверь подключение к серверу.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _blue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                    Icons.groups_2, color: Colors.white, size: 70),
              ),
            ),
            const SizedBox(height: 32),
            const Center(child: Text('Добро пожаловать',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700))),
            const SizedBox(height: 8),
            const Center(
              child: Text('Управление мероприятиями\nстуденческих отрядов РСО',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black54)),
            ),
            const SizedBox(height: 40),

            const Text('Email или номер телефона',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(controller: _email,
                decoration: InputDecoration(hintText: 'Введите данные',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 20),

            const Text('Пароль', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: _hidden,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(icon: Icon(
                    _hidden ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _hidden = !_hidden)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            Align(alignment: Alignment.centerRight,
                child: TextButton(onPressed: () {},
                    child: const Text('Забыли пароль?',
                        style: TextStyle(color: Color(0xFF4CAF50))))),

            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
                child: Text(
                    _error!, style: const TextStyle(color: Colors.red))),

            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _busy ? null : _login,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: _busy ? const CircularProgressIndicator(
                    color: Colors.white) : const Text('Войти', style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : () =>
                  Navigator.pushNamed(context, '/register'),
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
              child: const Text('Зарегистрироваться',
                  style: TextStyle(color: Color(0xFF4CAF50), fontSize: 17)),
            ),
          ],
        ),
      ),
    );
  }
}