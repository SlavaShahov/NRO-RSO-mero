import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _portfolio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().refreshProfile();
      _loadPortfolio();
    });
  }

  Future<void> _loadPortfolio() async {
    try {
      final p = await context.read<AuthProvider>().api.portfolio();
      if (mounted) setState(() => _portfolio = p);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final upcoming = _portfolio?['upcoming'] ?? 0;
    final attended = _portfolio?['attended'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => auth.logout())],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(radius: 48, child: Text(user.firstName.isNotEmpty ? user.firstName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 40))),
                const SizedBox(height: 12),
                Text(user.fullName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                Text('${user.unitName}, ${user.positionName}', style: const TextStyle(color: Color(0xFF1E3A8A), fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _StatCard(value: attended.toString(), label: 'Посещено'),
              const SizedBox(width: 8),
              _StatCard(value: upcoming.toString(), label: 'Предстоит'),
              const SizedBox(width: 8),
              _StatCard(value: (attended + upcoming).toString(), label: 'Всего'),
            ],
          ),
          const SizedBox(height: 30),
          const Text('Контакты', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Email: ${user.email}'),
          if (user.hqName.isNotEmpty) Text('Штаб: ${user.hqName}'),
          if (user.unitName.isNotEmpty) Text('Отряд: ${user.unitName}'),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}