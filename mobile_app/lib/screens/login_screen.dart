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
  final _email    = TextEditingController();
  final _password = TextEditingController();
  bool _busy   = false;
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
    final pass  = _password.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Введите email и пароль');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.auth.login(email, pass);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Ошибка сети. Проверь подключение к серверу.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openForgotPassword() {
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(api: widget.auth.api)));
  }

  static const _blue  = Color(0xFF1E3A8A);
  static const _green = Color(0xFF4CAF50);

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
                width: 120, height: 120,
                decoration: const BoxDecoration(
                    color: _green, shape: BoxShape.circle),
                child: const Icon(Icons.groups_2, color: Colors.white, size: 70),
              ),
            ),
            const SizedBox(height: 32),
            const Center(child: Text('Добро пожаловать',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700))),
            const SizedBox(height: 8),
            const Center(child: Text(
                'Управление мероприятиями\nстуденческих отрядов РСО',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54))),
            const SizedBox(height: 40),

            const Text('Email', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  hintText: 'example@yandex.ru',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 20),

            const Text('Пароль', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: _hidden,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                    icon: Icon(_hidden ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _hidden = !_hidden)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _openForgotPassword,
                child: const Text('Забыли пароль?',
                    style: TextStyle(color: _green)),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),

            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _busy ? null : _login,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: _busy
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Войти',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null
                  : () => Navigator.pushNamed(context, '/register'),
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
              child: const Text('Зарегистрироваться',
                  style: TextStyle(color: _green, fontSize: 17)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Экран «Забыл пароль» ──────────────────────────────────────────────────────

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // Шаг 1: ввод email → шаг 2: ввод кода + нового пароля
  int _step = 1;

  final _emailC   = TextEditingController();
  final _codeC    = TextEditingController();
  final _newPwC   = TextEditingController();
  final _confPwC  = TextEditingController();

  bool _busy     = false;
  bool _hidePw   = true;
  String? _error;
  String? _info;
  int _resendCooldown = 0; // секунды до повторной отправки

  @override
  void dispose() {
    _emailC.dispose(); _codeC.dispose();
    _newPwC.dispose(); _confPwC.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailC.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _error = 'Введите email'); return;
    }
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      await widget.api.forgotPassword(email);
      if (!mounted) return;
      setState(() {
        _step = 2;
        _info = 'Код отправлен на $email';
        _resendCooldown = 60;
      });
      _startCooldown();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    if (_resendCooldown > 0) return;
    final email = _emailC.text.trim().toLowerCase();
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      await widget.api.forgotPassword(email);
      if (!mounted) return;
      setState(() {
        _info = 'Код повторно отправлен';
        _resendCooldown = 60;
      });
      _startCooldown();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCooldown() {
    Future.doWhile(() async {
      if (!mounted || _resendCooldown <= 0) return false;
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendCooldown--);
      return _resendCooldown > 0;
    });
  }

  Future<void> _resetPassword() async {
    final code  = _codeC.text.trim();
    final newPw = _newPwC.text;
    final conf  = _confPwC.text;
    if (code.length != 6) {
      setState(() => _error = 'Код должен быть 6 цифр'); return;
    }
    if (newPw.length < 8) {
      setState(() => _error = 'Пароль: минимум 8 символов'); return;
    }
    if (newPw != conf) {
      setState(() => _error = 'Пароли не совпадают'); return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.api.resetPassword(
        email:       _emailC.text.trim().toLowerCase(),
        code:        code,
        newPassword: newPw,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пароль успешно изменён')));
      Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Восстановление пароля')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            if (_step == 1) ...[
              const Text('Введите email, указанный при регистрации.',
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 20),
              TextField(
                controller: _emailC,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
            ] else ...[
              Text('Код отправлен на ${_emailC.text.trim()}',
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 20),
              TextField(
                controller: _codeC,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                    labelText: '6-значный код',
                    prefixIcon: const Icon(Icons.verified_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPwC,
                obscureText: _hidePw,
                decoration: InputDecoration(
                    labelText: 'Новый пароль (мин. 8 символов)',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                        icon: Icon(_hidePw
                            ? Icons.visibility_off : Icons.visibility),
                        onPressed: () =>
                            setState(() => _hidePw = !_hidePw)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confPwC,
                obscureText: _hidePw,
                decoration: InputDecoration(
                    labelText: 'Повторите пароль',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
            ],

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red)),
              ),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_info!,
                    style: const TextStyle(color: Colors.green)),
              ),

            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null
                    : (_step == 1 ? _sendCode : _resetPassword),
                child: _busy
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_step == 1
                    ? 'Отправить код' : 'Изменить пароль',
                    style: const TextStyle(fontSize: 16)),
              ),
            ),

            if (_step == 2) ...[
              const SizedBox(height: 12),
              Center(
                child: _resendCooldown > 0
                    ? Text('Повторная отправка через $_resendCooldown с.',
                    style: const TextStyle(color: Colors.black45))
                    : TextButton(
                    onPressed: _busy ? null : _resendCode,
                    child: const Text('Отправить код повторно',
                        style: TextStyle(color: Color(0xFF4CAF50)))),
              ),
            ],
          ],
        ),
      ),
    );
  }
}