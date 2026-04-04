import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';

class RegistrationScreen extends StatelessWidget {
  const RegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<AuthProvider>().api;
    return _RegistrationContent(api: api);
  }
}

class _RegistrationContent extends StatefulWidget {
  final ApiClient api;
  const _RegistrationContent({super.key, required this.api});

  @override
  State<_RegistrationContent> createState() => _RegistrationContentState();
}

class _RegistrationContentState extends State<_RegistrationContent> {
  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordRepeat = TextEditingController();

  bool _busy = false;
  String? _error;

  List<HQItem> _hqs = [];
  List<UnitItem> _units = [];
  List<PositionItem> _positions = [];
  bool _loadingHqs = true;
  bool _loadingUnits = false;
  bool _loadingPositions = true;

  HQItem? _selectedHQ;
  UnitItem? _selectedUnit;
  PositionItem? _selectedPosition;

  bool _hidePw = true;
  bool _hidePw2 = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _lastName.dispose();
    _firstName.dispose();
    _middleName.dispose();
    _email.dispose();
    _password.dispose();
    _passwordRepeat.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final results = await Future.wait([
        widget.api.listHQs(),
        widget.api.listPositions(),
      ]);
      final hqs = results[0] as List<HQItem>;
      final positions = results[1] as List<PositionItem>;

      if (mounted) {
        setState(() {
          _hqs = hqs;
          _positions = positions;
          _loadingHqs = false;
          _loadingPositions = false;
          _selectedPosition = positions.firstWhere(
                (p) => p.code == 'fighter',
            orElse: () => positions.isNotEmpty ? positions.first : PositionItem(id: 0, code: '', name: ''),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingHqs = false;
          _loadingPositions = false;
          _error = 'Не удалось загрузить справочники';
        });
      }
    }
  }

  Future<void> _onHQSelected(HQItem? hq) async {
    setState(() {
      _selectedHQ = hq;
      _selectedUnit = null;
      _units = [];
      if (hq != null) _loadingUnits = true;
    });
    if (hq == null) return;
    try {
      final units = await widget.api.listUnits(hq.id);
      if (mounted) setState(() => _units = units);
    } finally {
      if (mounted) setState(() => _loadingUnits = false);
    }
  }

  String _capitalize(String s) {
    s = s.trim();
    if (s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  Future<void> _submit() async {
    final errors = <String>[];
    if (_lastName.text.trim().isEmpty) errors.add('Введите фамилию');
    if (_firstName.text.trim().isEmpty) errors.add('Введите имя');
    if (_email.text.trim().isEmpty) errors.add('Введите email');
    if (_password.text.isEmpty) errors.add('Введите пароль');
    if (_password.text.length < 6) errors.add('Пароль минимум 6 символов');
    if (_password.text != _passwordRepeat.text) errors.add('Пароли не совпадают');

    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }

    // Капитализация ФИО
    _lastName.text = _capitalize(_lastName.text);
    _firstName.text = _capitalize(_firstName.text);
    _middleName.text = _capitalize(_middleName.text);

    setState(() { _busy = true; _error = null; });

    try {
      final auth = context.read<AuthProvider>();
      await auth.register(
        email: _email.text.trim(),
        password: _password.text,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        middleName: _middleName.text.trim(),
        unitId: _selectedUnit?.id,
        unitPositionId: _selectedPosition?.id,
      );
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _blue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Регистрация')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Личные данные'),
          _field('Фамилия *', _lastName),
          _field('Имя *', _firstName),
          _field('Отчество', _middleName, hint: 'Необязательно'),

          _section('Контакты и безопасность'),
          _field('Email *', _email, inputType: TextInputType.emailAddress),
          _passwordField('Пароль *', _password, _hidePw, () => setState(() => _hidePw = !_hidePw)),
          _passwordField('Подтвердите пароль *', _passwordRepeat, _hidePw2, () => setState(() => _hidePw2 = !_hidePw2)),

          _section('Принадлежность к структуре'),

          const Text('Штаб (учебное заведение)', style: TextStyle(fontSize: 14, color: Colors.black87)),
          const SizedBox(height: 6),
          if (_loadingHqs)
            const Center(child: CircularProgressIndicator())
          else
            _dropdown<HQItem>(
              value: _selectedHQ,
              hint: 'Выберите штаб',
              items: _hqs,
              labelFn: (h) => h.name,
              onChanged: _busy ? null : _onHQSelected,
            ),

          const SizedBox(height: 12),
          const Text('Линейный отряд', style: TextStyle(fontSize: 14, color: Colors.black87)),
          const SizedBox(height: 6),
          if (_loadingUnits)
            const Center(child: CircularProgressIndicator())
          else
            _dropdown<UnitItem>(
              value: _selectedUnit,
              hint: _selectedHQ == null ? 'Сначала выберите штаб' : (_units.isEmpty ? 'Нет отрядов' : 'Выберите отряд'),
              items: _units,
              labelFn: (u) => u.name,
              onChanged: (_busy || _selectedHQ == null || _units.isEmpty) ? null : (u) => setState(() => _selectedUnit = u),
            ),

          const SizedBox(height: 12),
          const Text('Должность', style: TextStyle(fontSize: 14, color: Colors.black87)),
          const SizedBox(height: 6),
          if (_loadingPositions)
            const Center(child: CircularProgressIndicator())
          else
            _dropdown<PositionItem>(
              value: _selectedPosition,
              hint: 'Выберите должность',
              items: _positions,
              labelFn: (p) => p.name,
              onChanged: _busy ? null : (p) => setState(() => _selectedPosition = p),
            ),

          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),

          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _busy
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Зарегистрироваться', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Уже есть аккаунт? Войти', style: TextStyle(color: _blue)),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _blue)),
  );

  Widget _field(String label, TextEditingController ctrl, {String? hint, TextInputType? inputType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 5),
          TextField(
            controller: ctrl,
            keyboardType: inputType,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField(String label, TextEditingController ctrl, bool hidden, VoidCallback toggle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 5),
          TextField(
            controller: ctrl,
            obscureText: hidden,
            decoration: InputDecoration(
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
              suffixIcon: IconButton(icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: toggle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required List<T> items,
    required String Function(T) labelFn,
    required void Function(T?)? onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      hint: Text(hint, style: const TextStyle(color: Colors.black45)),
      decoration: const InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)))),
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(labelFn(item)))).toList(),
      onChanged: onChanged,
    );
  }
}