import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/avatar_service.dart';

/// Умный экран: штабникам — все отряды штаба, бойцам — свой отряд
class SquadScreen extends StatelessWidget {
  const SquadScreen({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) return const SizedBox.shrink();
    if (user.isHQStaff) return _HQView(api: api);
    return _UnitView(api: api);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Вид штабника — список всех отрядов штаба
// ─────────────────────────────────────────────────────────────────────────────

class _HQView extends StatefulWidget {
  const _HQView({required this.api});
  final ApiClient api;
  @override
  State<_HQView> createState() => _HQViewState();
}

class _HQViewState extends State<_HQView> {
  List<UnitItem>    _units   = [];
  List<UserProfile> _members = [];
  UnitItem?         _selected;
  bool _loadingUnits   = true;
  bool _loadingMembers = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUnits());
  }

  Future<void> _loadUnits() async {
    setState(() { _loadingUnits = true; _error = null; });
    try {
      final units = await widget.api.myHQUnits();
      if (mounted) setState(() { _units = units; _loadingUnits = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loadingUnits = false; });
    }
  }

  Future<void> _selectUnit(UnitItem unit) async {
    setState(() { _selected = unit; _loadingMembers = true; _members = []; });
    try {
      final m = await widget.api.unitMembers(unit.id);
      if (mounted) setState(() { _members = m; _loadingMembers = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  void _openMember(UserProfile m) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MemberSheet(member: m),
    );
  }

  static const _blue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(
        title: Text(user?.hqName.isNotEmpty == true ? user!.hqName : 'Штаб'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUnits),
        ],
      ),
      body: _loadingUnits
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Row(children: [
        // Левая панель — список отрядов
        Container(
          width: 160,
          color: Colors.white,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              color: _blue,
              child: const Text('Отряды',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _units.length,
                separatorBuilder: (_, __) =>
                const Divider(height: 1),
                itemBuilder: (_, i) {
                  final u = _units[i];
                  final active = _selected?.id == u.id;
                  return ListTile(
                    selected: active,
                    selectedColor: Colors.white,
                    selectedTileColor: _blue,
                    dense: true,
                    title: Text(u.name,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.normal)),
                    onTap: () => _selectUnit(u),
                  );
                },
              ),
            ),
          ]),
        ),
        const VerticalDivider(width: 1),
        // Правая панель — участники
        Expanded(
          child: _selected == null
              ? const Center(
              child: Text('Выберите отряд',
                  style: TextStyle(color: Colors.black38)))
              : _loadingMembers
              ? const Center(
              child: CircularProgressIndicator())
              : _members.isEmpty
              ? const Center(
              child: Text('Нет участников',
                  style: TextStyle(
                      color: Colors.black38)))
              : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _members.length,
            itemBuilder: (_, i) => _MemberTile(
                member: _members[i],
                onTap: () =>
                    _openMember(_members[i])),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Вид бойца — свой отряд
// ─────────────────────────────────────────────────────────────────────────────

class _UnitView extends StatefulWidget {
  const _UnitView({required this.api});
  final ApiClient api;
  @override
  State<_UnitView> createState() => _UnitViewState();
}

class _UnitViewState extends State<_UnitView> {
  List<UserProfile> _members = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    if (user?.unitId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final m = await widget.api.unitMembers(user!.unitId!);
      if (mounted) setState(() => _members = m);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openMember(UserProfile m) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MemberSheet(member: m),
    );
  }

  static const _blue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    if (user?.unitId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Отряд')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.groups_outlined, size: 64, color: Colors.black26),
              SizedBox(height: 16),
              Text('Вы не состоите в отряде',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('Обратитесь к командиру вашего отряда',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(user!.unitName.isNotEmpty ? user.unitName : 'Отряд'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!,
            style: const TextStyle(color: Colors.black54)),
        TextButton(
            onPressed: _load, child: const Text('Повторить')),
      ]))
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: _blue,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.groups_2,
                    color: Colors.white, size: 36),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(user.unitName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                          Text(user.hqName,
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13)),
                          Text('${_members.length} участников',
                              style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12)),
                        ])),
              ]),
            ),
            const SizedBox(height: 16),
            if (_members.isEmpty)
              const Center(
                  child: Text('В отряде нет участников',
                      style: TextStyle(color: Colors.black45)))
            else
              ..._members.map((m) => _MemberTile(
                  member: m, onTap: () => _openMember(m))),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Тайл участника с аватаром
// ─────────────────────────────────────────────────────────────────────────────

class _MemberTile extends StatefulWidget {
  const _MemberTile({required this.member, required this.onTap});
  final UserProfile member;
  final VoidCallback onTap;
  @override
  State<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends State<_MemberTile> {
  Uint8List? _avatar;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    AvatarService().getBytes(widget.member.id).then((b) {
      if (mounted) setState(() { _avatar = b; _loaded = true; });
    });
  }

  Color get _roleColor {
    switch (widget.member.roleCode) {
      case 'unit_commander':    return Colors.amber.shade700;
      case 'unit_commissioner': return Colors.blue.shade700;
      case 'unit_master':       return Colors.green.shade700;
      default:                  return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black12)),
      child: ListTile(
        onTap: widget.onTap,
        leading: _AvatarWidget(
          userId: m.id, firstName: m.firstName,
          bytes: _avatar, loaded: _loaded, radius: 22,
        ),
        title: Text(m.fullName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(m.positionName,
            style: TextStyle(color: _roleColor, fontSize: 13)),
        trailing: const Icon(Icons.chevron_right, color: Colors.black26),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Карточка участника (bottom sheet)
// ─────────────────────────────────────────────────────────────────────────────

class _MemberSheet extends StatefulWidget {
  const _MemberSheet({required this.member});
  final UserProfile member;
  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  Uint8List? _avatar;

  @override
  void initState() {
    super.initState();
    AvatarService().getBytes(widget.member.id).then((b) {
      if (mounted) setState(() => _avatar = b);
    });
  }

  static const _blue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 48,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        _AvatarWidget(
          userId: m.id, firstName: m.firstName,
          bytes: _avatar, loaded: true, radius: 48, fontSize: 38,
        ),
        const SizedBox(height: 12),
        Text(m.fullName,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700)),
        if (m.middleName.isNotEmpty)
          Text(m.middleName,
              style: const TextStyle(color: Colors.black54, fontSize: 14)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(20)),
          child: Text(m.positionName,
              style: const TextStyle(color: _blue, fontSize: 13)),
        ),
        const SizedBox(height: 16),
        if (m.unitName.isNotEmpty)  _row(Icons.groups_outlined, m.unitName),
        if (m.hqName.isNotEmpty)    _row(Icons.school_outlined, m.hqName),
        _row(Icons.badge_outlined, m.roleLabel),
        if (m.phone.isNotEmpty) _row(Icons.phone_outlined, m.phone),
        const Divider(height: 20),
        Row(children: [
          Icon(
              m.memberCardLocation == 'in_hq'
                  ? Icons.home_work_outlined
                  : Icons.card_membership_outlined,
              size: 18, color: _blue),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                m.memberCardNumber.isNotEmpty
                    ? 'Билет № ${m.memberCardNumber}'
                    : 'Номер билета не указан',
                style: TextStyle(
                    fontSize: 14,
                    color: m.memberCardNumber.isEmpty
                        ? Colors.black38 : Colors.black87,
                    fontStyle: m.memberCardNumber.isEmpty
                        ? FontStyle.italic : FontStyle.normal)),
            const SizedBox(height: 2),
            Text(
                m.memberCardLocation == 'in_hq'
                    ? '📍 Находится в РШ'
                    : '📋 На руках',
                style: TextStyle(
                    fontSize: 12,
                    color: m.memberCardLocation == 'in_hq'
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                    fontWeight: FontWeight.w500)),
          ])),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 18, color: _blue),
      const SizedBox(width: 10),
      Expanded(
          child: Text(text, style: const TextStyle(fontSize: 14))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Универсальный виджет аватара
// ─────────────────────────────────────────────────────────────────────────────

class _AvatarWidget extends StatelessWidget {
  const _AvatarWidget({
    required this.userId,
    required this.firstName,
    required this.bytes,
    required this.loaded,
    this.radius  = 22,
    this.fontSize = 16,
  });
  final int      userId;
  final String   firstName;
  final Uint8List? bytes;
  final bool     loaded;
  final double   radius;
  final double   fontSize;

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return CircleAvatar(
          radius: radius, backgroundImage: MemoryImage(bytes!));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFEAF2FF),
      child: Text(
        firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
        style: TextStyle(
            color: const Color(0xFF1E3A8A),
            fontWeight: FontWeight.bold,
            fontSize: fontSize * 0.45),
      ),
    );
  }
}