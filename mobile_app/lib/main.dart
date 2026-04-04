import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/events_provider.dart';
import 'providers/attendance_provider.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/event_detail_screen.dart';
import 'screens/events_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/squad_screen.dart';
import 'services/api_client.dart';

void main() => runApp(const RsoApp());

const String _apiHost = '10.0.2.2';
const int _apiPort = 8088;

class RsoApp extends StatelessWidget {
  const RsoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiClient(baseUrl: 'http://$_apiHost:$_apiPort');

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(api: api)..tryRestoreSession()),
        ChangeNotifierProxyProvider<AuthProvider, EventsProvider>(
          create: (_) => EventsProvider(api: api),
          update: (_, auth, events) => events!..updateToken(auth.accessToken),
        ),
        ChangeNotifierProxyProvider<AuthProvider, AttendanceProvider>(
          create: (_) => AttendanceProvider(api: api),
          update: (_, auth, att) => att!..updateToken(auth.accessToken),
        ),
      ],
      child: MaterialApp(
        title: 'РСО Мероприятия',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F7FB),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
        routes: {
          '/register': (_) => const RegistrationScreen(),
          '/event': (_) => const EventDetailScreen(),
          '/scanner': (_) => const ScannerScreen(),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isManager = auth.user?.isManager ?? false;

    final screens = <Widget>[
      const EventsScreen(),
      const SquadScreen(),
      const ProfileScreen(),
      if (isManager) const AdminDashboardScreen(),
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.view_agenda_outlined), selectedIcon: Icon(Icons.view_agenda), label: 'Лента'),
      const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Отряд'),
      const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Профиль'),
      if (isManager)
        const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), selectedIcon: Icon(Icons.admin_panel_settings), label: 'Управление'),
    ];

    if (_currentIndex >= screens.length) _currentIndex = 0;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: destinations,
      ),
    );
  }
}