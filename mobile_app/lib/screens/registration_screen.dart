import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/avatar_service.dart';

enum _RegType { fighter, hqStaff }

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, required this.api});
  final ApiClient api;
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _lastName       = TextEditingController();
  final _firstName      = TextEditingController();
  final _middleName     = TextEditingController();
  final _email          = TextEditingController();
  final _phone          = TextEditingController();
  final _memberCard     = TextEditingController();
  final _password       = TextEditingController();
  final _passwordRepeat = TextEditingController();

  _RegType _regType         = _RegType.fighter;
  String   _cardLocation    = 'with_user'; // with_user | in_hq
  File?    _avatarFile;
  Uint8List? _avatarBytes;

  bool     _busy  = false;
  String?  _error;
  bool     _hidePw  = true;
  bool     _hidePw2 = true;

  List<HQItem>         _hqs         = [];
  List<UnitItem>       _units       = [];
  List<PositionItem>   _positions   = [];
  List<HQPositionItem> _hqPositions = [];
  bool _loadingHqs = true, _loadingUnits = false, _loadingPositions = true;

  HQItem?         _selectedHQ;
  UnitItem?       _selectedUnit;
  PositionItem?   _selectedPosition;
  HQPositionItem? _selectedHQPosition;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    for (final c in [_lastName, _firstName, _middleName,
      _email, _phone, _memberCard, _password, _passwordRepeat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final results = await Future.wait([
        widget.api.listHQs(),
        widget.api.listPositions(),
        widget.api.listHQPositions(),
      ]);
      if (mounted) {
        final positions  = results[1] as List<PositionItem>;
        final hqPositions = results[2] as List<HQPositionItem>;
        setState(() {
          _hqs          = results[0] as List<HQItem>;
          _positions    = positions;
          _hqPositions  = hqPositions;
          _loadingHqs   = false; _loadingPositions = false;
          _selectedPosition = positions.firstWhere(
                (p) => p.code == 'fighter',
            orElse: () => positions.isNotEmpty ? positions.first
                : PositionItem(id: -1, code: '', name: ''),
          );
          if (hqPositions.isNotEmpty) _selectedHQPosition = hqPositions.first;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loadingHqs = false; _loadingPositions = false; });
    }
  }

  Future<void> _onHQSelected(HQItem? hq) async {
    setState(() {
      _selectedHQ = hq; _selectedUnit = null;
      _units = []; _loadingUnits = hq != null;
    });
    if (hq == null) return;
    try {
      final units = await widget.api.listUnits(hq.id);
      if (mounted) setState(() { _units = units; _loadingUnits = false; });
    } catch (_) { if (mounted) setState(() => _loadingUnits = false); }
  }

  // ── Аватар ────────────────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Сделать фото'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Выбрать из галереи'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await picker.pickImage(
        source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (picked == null) return;
    final file  = File(picked.path);
    final bytes = await file.readAsBytes();
    if (mounted) setState(() { _avatarFile = file; _avatarBytes = bytes; });
  }

  // ── Валидация ─────────────────────────────────────────────────────────────

  String? _vName(String v, String f) {
    final s = v.trim();
    if (s.isEmpty) return 'Введите $f';
    if (!RegExp(r'^[А-ЯЁA-Z]').hasMatch(s)) return '$f — с заглавной буквы';
    if (!RegExp(r'^[А-ЯЁа-яёA-Za-z\-\s]+$').hasMatch(s)) return '$f — только буквы';
    return null;
  }

  String? _vEmail(String v) {
    if (v.trim().isEmpty) return 'Введите email';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
      return 'Некорректный email';
    return null;
  }

  String? _vPhone(String v) {
    if (v.trim().isEmpty) return null;
    final c = v.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    if (!RegExp(r'^[78]\d{10}$').hasMatch(c)) return 'Формат: 79001234567';
    return null;
  }

  String? _vPassword(String v) {
    if (v.isEmpty) return 'Введите пароль';
    if (v.length < 8) return 'Мин. 8 символов';
    if (!RegExp(r'[A-ZА-ЯЁ]').hasMatch(v)) return 'Нужна заглавная буква';
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Нужна цифра';
    return null;
  }

  Future<void> _submit() async {
    final errors = <String>[];
    for (final e in [
      _vName(_lastName.text, 'Фамилия'),
      _vName(_firstName.text, 'Имя'),
      if (_middleName.text.trim().isNotEmpty) _vName(_middleName.text, 'Отчество'),
      _vEmail(_email.text),
      _vPhone(_phone.text),
      _vPassword(_password.text),
    ]) { if (e != null) errors.add(e); }
    if (_password.text != _passwordRepeat.text) errors.add('Пароли не совпадают');
    if (_selectedHQ == null) errors.add('Выберите штаб');
    if (_regType == _RegType.fighter && _selectedUnit == null)
      errors.add('Выберите отряд');
    if (_regType == _RegType.hqStaff && _selectedHQPosition == null)
      errors.add('Выберите должность ШСО');

    if (errors.isNotEmpty) { setState(() => _error = errors.join('\n')); return; }

    setState(() { _busy = true; _error = null; });
    try {
      final auth = context.read<AuthProvider>();
      await auth.register(
        email:               _email.text.trim(),
        password:            _password.text,
        firstName:           _firstName.text.trim(),
        lastName:            _lastName.text.trim(),
        middleName:          _middleName.text.trim(),
        phone:               _phone.text.trim(),
        // Членский билет: номер только если он на руках
        memberCardNumber:    _cardLocation == 'with_user'
            ? _memberCard.text.trim() : '',
        memberCardLocation:  _cardLocation,
        unitId:              _regType == _RegType.fighter ? _selectedUnit?.id : null,
        unitPositionId:      _regType == _RegType.fighter ? _selectedPosition?.id : null,
        hqId:                _selectedHQ?.id,
        hqPositionId:        _regType == _RegType.hqStaff ? _selectedHQPosition?.id : null,
      );

      // Сохраняем аватар если выбран
      final user = auth.user;
      if (_avatarFile != null && user != null) {
        await AvatarService().saveFromFile(user.id, _avatarFile!);
      }

      if (!mounted) return;
      // ← Входим сразу, без ожидания одобрения для штабников
      Navigator.pop(context);
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
          // Выбор типа
          _section('Тип регистрации'),
          _typeSelector(),

          if (_regType == _RegType.hqStaff)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Text(
                'Вы войдёте в систему сразу. Заявка на должность ШСО будет отправлена администратору — до одобрения функции штабника недоступны.',
                style: TextStyle(fontSize: 13),
              ),
            ),

          // Аватар
          _section('Фото профиля'),
          _avatarPicker(),

          // Личные данные
          _section('Личные данные'),
          _nameField('Фамилия *', _lastName, 'Смирнов'),
          _nameField('Имя *',     _firstName, 'Александр'),
          _nameField('Отчество',  _middleName, 'Необязательно'),

          // Контакты
          _section('Контакты и безопасность'),
          _emailField(),
          _phoneField(),
          _pwField('Пароль *',          _password,  _hidePw,  () => setState(() => _hidePw  = !_hidePw)),
          _pwField('Подтверждение *',   _passwordRepeat, _hidePw2, () => setState(() => _hidePw2 = !_hidePw2)),

          // ── Членский билет: СНАЧАЛА местонахождение, потом номер ──────────
          _section('Членский билет'),
          // 1. Сначала выбираем где билет
          const Text('Где находится билет?', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          _locationPicker(),
          const SizedBox(height: 12),
          // 2. Потом номер — только если на руках
          const Text('Номер членского билета', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            controller: _memberCard,
            // Заблокировано если билет в РШ
            enabled: _cardLocation == 'with_user',
            decoration: InputDecoration(
              hintText: _cardLocation == 'in_hq'
                  ? 'Недоступно — билет в РШ'
                  : 'Введите номер (необязательно)',
              prefixIcon: Icon(
                Icons.card_membership_outlined,
                color: _cardLocation == 'in_hq' ? Colors.black26 : null,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10))),
              filled: _cardLocation == 'in_hq',
              fillColor: _cardLocation == 'in_hq' ? Colors.grey.shade100 : null,
            ),
          ),
          if (_cardLocation == 'in_hq')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Номер можно будет добавить позже в профиле, когда заберёте билет',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ),

          // Структура
          _section(_regType == _RegType.hqStaff ? 'Штаб' : 'Принадлежность к структуре'),

          const Text('Штаб (учебное заведение)', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          if (_loadingHqs)
            const Center(child: CircularProgressIndicator())
          else
            _drop<HQItem>(
              value: _selectedHQ,
              hint: 'Выберите штаб',
              items: _hqs.map((h) => DropdownMenuItem(
                  value: h, child: Text(h.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _busy ? null : _onHQSelected,
            ),
          const SizedBox(height: 12),

          if (_regType == _RegType.fighter) ...[
            const Text('Линейный отряд', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            if (_loadingUnits)
              const Center(child: CircularProgressIndicator())
            else
              _drop<UnitItem>(
                value: _selectedUnit,
                hint: _selectedHQ == null ? 'Сначала выберите штаб'
                    : _units.isEmpty ? 'Нет отрядов' : 'Выберите отряд',
                items: _units.map((u) => DropdownMenuItem(
                    value: u, child: Text(u.name, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (_busy || _selectedHQ == null || _units.isEmpty) ? null
                    : (u) => setState(() => _selectedUnit = u),
              ),
            const SizedBox(height: 12),
            if (!_loadingPositions) ...[
              const Text('Должность в отряде', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 6),
              _drop<PositionItem>(
                value: _selectedPosition,
                hint: 'Должность',
                items: _positions.map((p) => DropdownMenuItem(
                    value: p, child: Text(p.name))).toList(),
                onChanged: _busy ? null : (p) => setState(() => _selectedPosition = p),
              ),
            ],
          ] else ...[
            const Text('Должность ШСО', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            _drop<HQPositionItem>(
              value: _selectedHQPosition,
              hint: 'Выберите должность',
              items: _hqPositions.map((p) => DropdownMenuItem(
                  value: p, child: Text(p.name))).toList(),
              onChanged: _busy ? null : (p) => setState(() => _selectedHQPosition = p),
            ),
          ],

          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(_error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ),

          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _blue, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _busy
                  ? const SizedBox(height: 22, width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                  _regType == _RegType.hqStaff
                      ? 'Зарегистрироваться' : 'Зарегистрироваться',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Уже есть аккаунт? Войти', style: TextStyle(color: _blue)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Виджеты ───────────────────────────────────────────────────────────────

  Widget _typeSelector() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Expanded(child: _typeBtn('Боец / Участник', _RegType.fighter)),
      const SizedBox(width: 8),
      Expanded(child: _typeBtn('Работник штаба (ШСО)', _RegType.hqStaff)),
    ]),
  );

  Widget _typeBtn(String label, _RegType t) {
    final active = _regType == t;
    return GestureDetector(
      onTap: () => setState(() => _regType = t),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? _blue : const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: active ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600, fontSize: 13))),
      ),
    );
  }

  Widget _avatarPicker() => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Center(
      child: GestureDetector(
        onTap: _pickAvatar,
        child: Stack(clipBehavior: Clip.none, children: [
          CircleAvatar(
            radius: 52,
            backgroundColor: const Color(0xFFEAF2FF),
            backgroundImage: _avatarBytes != null
                ? MemoryImage(_avatarBytes!) : null,
            child: _avatarBytes == null
                ? const Icon(Icons.person_outline, size: 52, color: Color(0xFF1E3A8A))
                : null,
          ),
          Positioned(
            right: 0, bottom: 0,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                  color: _blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
            ),
          ),
        ]),
      ),
    ),
  );

  Widget _locationPicker() => Row(children: [
    _locBtn('📋 На руках', 'with_user'),
    const SizedBox(width: 8),
    _locBtn('🏢 В РШ',    'in_hq'),
  ]);

  Widget _locBtn(String label, String val) {
    final active = _cardLocation == val;
    return GestureDetector(
      onTap: () => setState(() {
        _cardLocation = val;
        // Если выбрали «В РШ» — очищаем поле номера
        if (val == 'in_hq') _memberCard.clear();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: active ? _blue : const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(
            color: active ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(t, style: const TextStyle(
        fontSize: 17, fontWeight: FontWeight.w700, color: _blue)),
  );

  Widget _nameField(String label, TextEditingController ctrl, String hint) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 5),
          TextField(
            controller: ctrl,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [_CapFirst()],
            decoration: InputDecoration(
              hintText: hint,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
          ),
        ]),
      );

  Widget _emailField() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Email *', style: TextStyle(fontSize: 14)),
      const SizedBox(height: 5),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        textCapitalization: TextCapitalization.none,
        decoration: const InputDecoration(
          hintText: 'example@mail.ru',
          prefixIcon: Icon(Icons.email_outlined),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
      ),
    ]),
  );

  Widget _phoneField() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Телефон', style: TextStyle(fontSize: 14)),
      const SizedBox(height: 5),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\+\(\)]'))],
        decoration: const InputDecoration(
          hintText: '+7 (___) ___-__-__ (необязательно)',
          prefixIcon: Icon(Icons.phone_outlined),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
      ),
    ]),
  );

  Widget _pwField(String label, TextEditingController ctrl,
      bool hidden, VoidCallback toggle) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 14)),
      const SizedBox(height: 5),
      TextField(
        controller: ctrl,
        obscureText: hidden,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10))),
          suffixIcon: IconButton(
            icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: toggle,
          ),
        ),
      ),
    ]),
  );

  Widget _drop<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?)? onChanged,
  }) => DropdownButtonFormField<T>(
    value: value, isExpanded: true,
    hint: Text(hint, style: const TextStyle(color: Colors.black45)),
    decoration: const InputDecoration(
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
    ),
    items: items, onChanged: onChanged,
  );
}

class _CapFirst extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue nv) {
    if (nv.text.isEmpty) return nv;
    final words = nv.text.split(' ');
    final result = words.map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
    return nv.copyWith(text: result, selection: nv.selection);
  }
}