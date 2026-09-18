import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'services/admin_api.dart';
import 'services/api.dart';
import 'services/geofencing_service.dart';
import 'state/auth_controller.dart';

class GeoAttendApp extends StatelessWidget {
  const GeoAttendApp({
    super.key,
    required this.api,
    required this.adminApi,
    required this.auth,
    required this.geofencing,
  });

  final Api api;
  final AdminApi adminApi;
  final AuthController auth;
  final GeofencingService geofencing;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geofenced Attendance',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          if (auth.loading) return const _Splash();
          if (!auth.isSignedIn) return LoginScreen(auth: auth);
          if (auth.profile?.role == 'admin') {
            return AdminShell(api: adminApi, auth: auth);
          }
          return MainShell(api: api, auth: auth, geofencing: geofencing);
        },
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.api,
    required this.auth,
    required this.geofencing,
  });

  final Api api;
  final AuthController auth;
  final GeofencingService geofencing;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _syncGeofences();
  }

  Future<void> _syncGeofences() async {
    try {
      final fences = await widget.api.fetchAssignedGeofences();
      await widget.geofencing.sync(fences);
      if (mounted) setState(() {});
    } catch (_) {
      // Background detection is optional; manual actions still work.
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(api: widget.api, auth: widget.auth, geofencing: widget.geofencing),
      HistoryScreen(api: widget.api, auth: widget.auth),
      SettingsScreen(api: widget.api, auth: widget.auth, geofencing: widget.geofencing),
    ];

    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: screens)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class ConfigMissingApp extends StatelessWidget {
  const ConfigMissingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Supabase is not configured.\n\n'
              'Run with:\n'
              'flutter run --dart-define=SUPABASE_URL=... '
              '--dart-define=SUPABASE_ANON_KEY=...',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
