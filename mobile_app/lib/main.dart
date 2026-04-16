import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/events_provider.dart';
import 'providers/attendance_provider.dart';
import 'providers/notifications_provider.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/event_detail_screen.dart';
import 'screens/events_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/squad_screen.dart';
import 'services/api_client.dart';

void main() {
  runApp(const RsoApp());
}

// Android-эмулятор: 10.0.2.2 = хост-машина
// Реальный телефон: замени на IP своего ПК (например '192.168.1.5')
// Cloudflare Tunnel: замени на https://xxx.trycloudflare.com
const String _apiHost = 'xzojfv-5-44-168-60.ru.tuna.am';
//const int    _apiPort = 8088;

class RsoApp extends StatelessWidget {
  const RsoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiClient(baseUrl: 'http://$_apiHost');

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(api: api)..tryRestoreSession(),
        ),
        ChangeNotifierProxyProvider<AuthProvider, EventsProvider>(
          create: (_) => EventsProvider(api: api),
          update: (_, auth, events) {
            events!.updateToken(auth.api.accessToken);
            return events;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, AttendanceProvider>(
          create: (_) => AttendanceProvider(api: api),
          update: (_, auth, att) {
            att!.updateToken(auth.api.accessToken);
            return att;
          },
        ),
        // NotificationsProvider — запускает polling при создании
        ChangeNotifierProvider(
          create: (_) {
            final p = NotificationsProvider(api: api);
            // Инициализируем после первого кадра
            WidgetsBinding.instance
                .addPostFrameCallback((_) => p.startPolling());
            return p;
          },
        ),
      ],
      child: MaterialApp(
        title: 'РСО Мероприятия',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1E3A8A)),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F7FB),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        routes: {
          '/event':         (_) => const EventDetailScreen(),
          '/scanner':       (_) => const ScannerScreen(),
          '/register':      (ctx) => RegistrationScreen(
              api: ctx.read<AuthProvider>().api),
          '/admin':         (_) => const AdminDashboardScreen(),
          '/notifications': (_) => const NotificationsScreen(),
        },
        home: const _AppRoot(),
      ),
    );
  }
}

class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isAuthorized) {
      return LoginScreen(auth: auth);
    }
    return const _MainShell();
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();
  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final auth      = context.watch<AuthProvider>();
    final user      = auth.user;
    final api       = auth.api;
    final showAdmin = user != null && user.isManager;

    final tabs = <Widget>[
      const EventsScreen(),
      SquadScreen(api: api),
      if (showAdmin) const AdminDashboardScreen(),
      ProfileScreen(api: api),
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon:         Icon(Icons.view_agenda_outlined),
        selectedIcon: Icon(Icons.view_agenda),
        label: 'Лента',
      ),
      NavigationDestination(
        icon:         const Icon(Icons.groups_outlined),
        selectedIcon: const Icon(Icons.groups),
        // Штабникам надпись «Штаб», остальным «Отряд»
        label: user?.isHQStaff == true ? 'Штаб' : 'Отряд',
      ),
      if (showAdmin)
        const NavigationDestination(
          icon:         Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Управление',
        ),
      const NavigationDestination(
        icon:         Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Профиль',
      ),
    ];

    final safeTab = _tab.clamp(0, tabs.length - 1);

    return Scaffold(
      body: IndexedStack(index: safeTab, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeTab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: destinations,
      ),
    );
  }
}