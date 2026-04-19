import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/avatar_service.dart';
import '../screens/notifications_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.api});
  final ApiClient api;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loadingPortfolio = false;
  Map<String, dynamic>? _portfolio;
  List<MyRegistration> _registrations = [];
  bool _loadingRegs = false;
  Uint8List? _avatarBytes;
  int? _avatarUserId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().refreshProfile().then((_) {
        _loadAvatar();
        _loadData();
      });
    });
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _loadAvatar() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    if (_avatarUserId == user.id && _avatarBytes != null) return;
    var bytes = await AvatarService().getBytes(user.id);
    if (bytes == null) {
      try {
        final b64 = await widget.api.getMyAvatar();
        if (b64.isNotEmpty) {
          bytes = base64Decode(b64);
          await AvatarService().saveBytes(user.id, bytes!);
        }
      } catch (_) {}
    }
    if (mounted) setState(() { _avatarBytes = bytes; _avatarUserId = user.id; });
  }

  Future<void> _loadData() async {
    setState(() { _loadingPortfolio = true; _loadingRegs = true; });
    try {
      final results = await Future.wait([
        widget.api.portfolio(),
        widget.api.myRegistrations(),
      ]);
      if (mounted) setState(() {
        _portfolio     = results[0] as Map<String, dynamic>;
        _registrations = results[1] as List<MyRegistration>;
      });
    } catch (_) {}
    finally {
      if (mounted) setState(() { _loadingPortfolio = false; _loadingRegs = false; });
    }
  }

  // ── Аватар ────────────────────────────────────────────────────────────────

  Future<void> _changeAvatar() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    // Используем особый sentinel-тип для различения «удалить» и «закрыть тапом»
    const deleteAction = 'delete';
    const cameraAction = 'camera';
    const galleryAction = 'gallery';

    final action = await showModalBottomSheet<String>(
      context: context,
      // isDismissible: true — по умолчанию, но возвращает null при тапе по фону
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
                color: Colors.black12, borderRadius: BorderRadius.circular(2)),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Сделать фото'),
            onTap: () => Navigator.pop(context, cameraAction),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Выбрать из галереи'),
            onTap: () => Navigator.pop(context, galleryAction),
          ),
          if (_avatarBytes != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Удалить фото', style: TextStyle(color: Colors.red)),
              // Возвращаем явный sentinel — не null
              onTap: () => Navigator.pop(context, deleteAction),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );

    // null = закрыт тапом по фону — НЕ удаляем фото
    if (action == null) return;

    if (action == deleteAction) {
      await AvatarService().delete(user.id);
      if (mounted) setState(() => _avatarBytes = null);
      return;
    }

    final source = action == cameraAction ? ImageSource.camera : ImageSource.gallery;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await AvatarService().saveFromFile(user.id, File(picked.path));
    if (mounted) setState(() { _avatarBytes = bytes; _avatarUserId = user.id; });
    try { await widget.api.uploadAvatar(bytes); } catch (_) {}
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(context: context,
        builder: (_) => AlertDialog(
          title: const Text('Выйти из аккаунта?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Выйти', style: TextStyle(color: Colors.red))),
          ],
        ));
    if (ok == true && mounted) await context.read<AuthProvider>().logout();
  }

  void _openEdit() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditProfileSheet(
        user: user,
        api: widget.api,
        onSave: (last, first, mid, phone, cardNum, cardLoc) async {
          await context.read<AuthProvider>().updateProfile(
              lastName: last, firstName: first, middleName: mid, phone: phone,
              memberCardNumber: cardNum, memberCardLocation: cardLoc);
        },
      ),
    );
  }

  void _showQR(MyRegistration reg) {
    showDialog(context: context, builder: (dialogCtx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(reg.eventTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text('${reg.dayStr} ${reg.monthStr}, ${reg.startTimeShort}',
              style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          QrImageView(data: reg.qrCode, size: 220, backgroundColor: Colors.white),
          const SizedBox(height: 8),
          const Text('Предъяви этот код на входе',
              style: TextStyle(color: Colors.black45, fontSize: 12)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity,
              child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Закрыть'))),
        ]),
      ),
    ));
  }

  static const _blue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (user == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final upcoming     = _registrations.where((r) => r.isUpcoming).toList();
    final attended      = _registrations.where((r) => r.isAttended).toList();
    final totalAttended = _portfolio?['attended'] as int? ?? attended.length;
    final totalUpcoming = _portfolio?['upcoming'] as int? ?? upcoming.length;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await context.read<AuthProvider>().refreshProfile();
          await _loadData();
          await _loadAvatar();
        },
        child: CustomScrollView(slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: _blue,
            actions: [
              const NotificationBell(),
              IconButton(icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Редактировать', onPressed: _openEdit),
              IconButton(icon: const Icon(Icons.logout),
                  tooltip: 'Выйти', onPressed: _logout),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: _blue,
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  const SizedBox(height: 80),
                  GestureDetector(
                    onTap: _changeAvatar,
                    child: Stack(clipBehavior: Clip.none, children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        backgroundImage: _avatarBytes != null
                            ? MemoryImage(_avatarBytes!) : null,
                        child: _avatarBytes == null
                            ? Text(
                                user.firstName.isNotEmpty
                                    ? user.firstName[0].toUpperCase() : '?',
                                style: const TextStyle(fontSize: 38,
                                    color: Colors.white, fontWeight: FontWeight.bold))
                            : null,
                      ),
                      Positioned(right: -2, bottom: -2,
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle,
                              border: Border.all(color: _blue, width: 2)),
                          child: const Icon(Icons.camera_alt, color: _blue, size: 14),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Text(user.fullName, style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      user.unitName.isNotEmpty
                          ? '${user.unitName}, ${user.positionName}'
                          : user.positionName.isNotEmpty ? user.positionName : 'Боец',
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                // Баннер ожидания одобрения ШСО
                if (user.isPendingApproval)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(children: [
                      Icon(Icons.hourglass_top, color: Colors.orange.shade700, size: 28),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Заявка на рассмотрении',
                            style: TextStyle(fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('Ваша заявка на должность ШСО отправлена администратору. '
                            'До одобрения функции штабника недоступны.',
                            style: TextStyle(color: Colors.orange.shade700, fontSize: 12)),
                      ])),
                    ]),
                  ),

                // Статистика
                // ← ИСПРАВЛЕНО: unitName вместо hqName, подпись «Отряд» вместо «Штаб»
                Row(children: [
                  Expanded(child: _StatCard(value: '$totalAttended', label: 'Мероприятия')),
                  const SizedBox(width: 8),
                  Expanded(child: _StatCard(value: '$totalUpcoming', label: 'Предстоит')),
                  const SizedBox(width: 8),
                  Expanded(child: _StatCard(
                      value: user.unitName.isNotEmpty ? user.unitName : '—',
                      label: 'Отряд')),   // ← «Отряд» вместо «Штаб»
                ]),
                const SizedBox(height: 14),

                // Данные аккаунта
                _InfoCard(title: 'Данные аккаунта', onEdit: _openEdit, children: [
                  _InfoRow(Icons.email_outlined, user.email),
                  if (user.phone.isNotEmpty) _InfoRow(Icons.phone_outlined, user.phone),
                  if (user.hqName.isNotEmpty) _InfoRow(Icons.school_outlined, user.hqName),
                  _InfoRow(Icons.badge_outlined,
                      user.positionName.isNotEmpty ? user.positionName : 'Боец'),
                ]),
                const SizedBox(height: 10),

                // Членский билет
                _InfoCard(title: 'Членский билет', onEdit: _openEdit, children: [
                  _InfoRow(
                    user.memberCardLocation == 'in_hq'
                        ? Icons.home_work_outlined : Icons.person_outlined,
                    user.memberCardLocation == 'in_hq'
                        ? 'Находится в РШ' : 'Находится на руках',
                    highlight: user.memberCardLocation == 'in_hq',
                  ),
                  if (user.memberCardNumber.isNotEmpty)
                    _InfoRow(Icons.card_membership_outlined, '№ ${user.memberCardNumber}')
                  else
                    _InfoRow(Icons.card_membership_outlined, 'Номер не указан', muted: true),
                ]),
                const SizedBox(height: 8),
              ]),
            ),
          ),

          SliverPersistentHeader(
            pinned: true,
            delegate: _TabDelegate(TabBar(
              controller: _tabs,
              labelColor: _blue,
              unselectedLabelColor: Colors.black45,
              indicatorColor: _blue,
              dividerColor: Colors.transparent,
              tabs: [
                Tab(text: 'Предстоящие (${upcoming.length})'),
                Tab(text: 'Посещённые (${attended.length})'),
              ],
            )),
          ),

          SliverFillRemaining(
            child: TabBarView(controller: _tabs, children: [
              _RegList(regs: upcoming, loading: _loadingRegs,
                  emptyText: 'Нет предстоящих мероприятий', onQR: _showQR),
              _RegList(regs: attended, loading: _loadingRegs,
                  emptyText: 'Нет посещённых мероприятий', onQR: _showQR),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Виджеты ───────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children, this.onEdit});
  final String title; final List<Widget> children; final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (onEdit != null)
          TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit, size: 14),
              label: const Text('Изменить', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero)),
      ]),
      const SizedBox(height: 8),
      ...children,
    ]),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, {this.muted = false, this.highlight = false});
  final IconData icon; final String label; final bool muted, highlight;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 18,
          color: highlight ? Colors.orange.shade700 : const Color(0xFF1E3A8A)),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(fontSize: 14,
          color: muted ? Colors.black38 : Colors.black87,
          fontStyle: muted ? FontStyle.italic : FontStyle.normal))),
    ]),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A8A))),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Colors.black54)),
    ]),
  );
}

class _RegList extends StatelessWidget {
  const _RegList({required this.regs, required this.loading,
      required this.emptyText, required this.onQR});
  final List<MyRegistration> regs; final bool loading;
  final String emptyText; final void Function(MyRegistration) onQR;
  @override
  Widget build(BuildContext context) {
    if (loading && regs.isEmpty) return const Center(child: CircularProgressIndicator());
    if (regs.isEmpty) return Center(child: Text(emptyText,
        style: const TextStyle(color: Colors.black45)));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: regs.length,
      itemBuilder: (_, i) => _TicketCard(reg: regs[i], onQR: () => onQR(regs[i])),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.reg, required this.onQR});
  final MyRegistration reg; final VoidCallback onQR;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black12)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${reg.dayStr} ${reg.monthStr}, ${reg.startTimeShort}',
            style: const TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(reg.eventTitle,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (reg.location.isNotEmpty)
          Text(reg.location, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        if (reg.isAttended)
          Padding(padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6)),
              child: Text('Посетил', style: TextStyle(color: Colors.green.shade700,
                  fontSize: 12, fontWeight: FontWeight.w600)),
            )),
      ])),
      const SizedBox(width: 12),
      InkWell(onTap: onQR, borderRadius: BorderRadius.circular(8),
        child: Column(children: [
          Container(width: 72, height: 72,
            decoration: BoxDecoration(color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black12)),
            child: reg.qrCode.isNotEmpty
                ? ClipRRect(borderRadius: BorderRadius.circular(7),
                    child: QrImageView(data: reg.qrCode, size: 72,
                        backgroundColor: Colors.white))
                : const Icon(Icons.qr_code, color: Colors.black26, size: 32),
          ),
          const SizedBox(height: 4),
          Text('БИЛЕТ', style: TextStyle(color: Colors.blue.shade700,
              fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    ]),
  );
}

class _TabDelegate extends SliverPersistentHeaderDelegate {
  const _TabDelegate(this.tabBar);
  final TabBar tabBar;
  @override double get minExtent => tabBar.preferredSize.height;
  @override double get maxExtent => tabBar.preferredSize.height;
  @override Widget build(ctx, _, __) =>
      Container(color: const Color(0xFFF5F7FB), child: tabBar);
  @override bool shouldRebuild(_TabDelegate old) => old.tabBar != tabBar;
}

// ── Редактирование ────────────────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.user, required this.onSave, required this.api});
  final UserProfile user;
  final ApiClient api;
  final Future<void> Function(String, String, String, String, String, String) onSave;
  @override State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _last, _first, _mid, _phone, _card;
  late String _cardLocation;
  bool _busy = false; String? _error;
  List<PositionItem> _positions = [];
  PositionItem? _selectedPosition;

  @override
  void initState() {
    super.initState();
    _last  = TextEditingController(text: widget.user.lastName);
    _first = TextEditingController(text: widget.user.firstName);
    _mid   = TextEditingController(text: widget.user.middleName);
    _phone = TextEditingController(text: widget.user.phone);
    _card  = TextEditingController(text: widget.user.memberCardNumber);
    _cardLocation = widget.user.memberCardLocation.isNotEmpty
        ? widget.user.memberCardLocation : 'with_user';
    // Загружаем должности только для бойцов (не штабников)
    if (!widget.user.isHQStaff) _loadPositions();
  }

  Future<void> _loadPositions() async {
    try {
      final list = await widget.api.listPositions();
      final current = list.firstWhere(
          (p) => p.name == widget.user.positionName,
          orElse: () => list.isNotEmpty ? list.first : PositionItem(id: -1, code: '', name: ''));
      if (mounted) setState(() { _positions = list; _selectedPosition = current; });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_last, _first, _mid, _phone, _card]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_last.text.trim().isEmpty || _first.text.trim().isEmpty) {
      setState(() => _error = 'Фамилия и имя обязательны'); return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final cardNum = _cardLocation == 'with_user' ? _card.text.trim() : '';
      await widget.onSave(_last.text.trim(), _first.text.trim(),
          _mid.text.trim(), _phone.text.trim(), cardNum, _cardLocation);
      if (mounted) Navigator.pop(context);
    } catch (e) { setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  static const _blue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 48, height: 4, decoration: BoxDecoration(
          color: Colors.black12, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 16),
      const Text('Редактирование профиля',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      _f('Фамилия *', _last, TextCapitalization.words),
      _f('Имя *', _first, TextCapitalization.words),
      _f('Отчество', _mid, TextCapitalization.words),
      _f('Телефон', _phone, TextCapitalization.none, type: TextInputType.phone),
      // Смена должности — только для бойцов (не штабников)
      if (!widget.user.isHQStaff && _positions.isNotEmpty) ...[
        const Align(alignment: Alignment.centerLeft,
            child: Text('Должность в отряде', style: TextStyle(fontSize: 14))),
        const SizedBox(height: 6),
        DropdownButtonFormField<PositionItem>(
          value: _selectedPosition,
          decoration: const InputDecoration(
            border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10))),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: _positions.map((p) => DropdownMenuItem(
              value: p, child: Text(p.name))).toList(),
          onChanged: _busy ? null : (p) => setState(() => _selectedPosition = p),
        ),
        const SizedBox(height: 10),
      ],
      const Align(alignment: Alignment.centerLeft,
          child: Text('Где находится билет?', style: TextStyle(fontSize: 14))),
      const SizedBox(height: 8),
      Row(children: [
        _locBtn('На руках', 'with_user'),
        const SizedBox(width: 8),
        _locBtn('В РШ', 'in_hq'),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _card,
        enabled: _cardLocation == 'with_user',
        decoration: InputDecoration(
          labelText: 'Номер членского билета',
          hintText: _cardLocation == 'in_hq' ? 'Недоступно — билет в РШ' : 'Необязательно',
          prefixIcon: Icon(Icons.card_membership_outlined,
              color: _cardLocation == 'in_hq' ? Colors.black26 : null),
          border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          filled: _cardLocation == 'in_hq',
          fillColor: _cardLocation == 'in_hq' ? Colors.grey.shade100 : null,
        ),
      ),
      const SizedBox(height: 10),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
      SizedBox(width: double.infinity,
        child: ElevatedButton(onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Сохранить')),
      ),
    ]),
  );

  Widget _locBtn(String label, String val) {
    final active = _cardLocation == val;
    return GestureDetector(
      onTap: () => setState(() { _cardLocation = val; if (val == 'in_hq') _card.clear(); }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
            color: active ? _blue : const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(
            color: active ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _f(String label, TextEditingController ctrl,
      TextCapitalization cap, {TextInputType? type}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: ctrl, textCapitalization: cap, keyboardType: type,
      decoration: InputDecoration(labelText: label,
        border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12))),
  );
}