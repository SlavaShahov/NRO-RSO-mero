import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class SquadScreen extends StatelessWidget {
  const SquadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    // Заглушка списка бойцов отряда (в будущем — из API)
    final members = const [
      ("Александр Смирнов", "Командир", true),
      ("Мария Кузнецова", "Боец", true),
      ("Дмитрий Иванов", "Боец", false),
      ("Елена Соколова", "Комиссар", true),
      ("Илья Морозов", "Боец", false),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Отряд")),
      body: user == null
          ? const Center(child: Text("Не удалось загрузить данные"))
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("СО «${user.unitName}»", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text("Штаб: ${user.hqName}", style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          const Text("Состав отряда", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...members.map((m) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(m.$1),
              subtitle: Text(m.$2),
              trailing: Icon(Icons.circle, color: m.$3 ? Colors.green : Colors.grey, size: 14),
            ),
          )),
        ],
      ),
    );
  }
}