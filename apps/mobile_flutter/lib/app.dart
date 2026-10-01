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
import 'services/permissions_service.dart';
import 'state/auth_controller.dart';
import 'state/theme_controller.dart';

class GeoAttendApp extends StatelessWidget {
  const GeoAttendApp({
    super.key,
    required this.api,
    required this.adminApi,
    required this.auth,
    required this.geofencing,
    required this.theme,
  });

  final Api api;
  final AdminApi adminApi;
  final AuthController auth;
  final GeofencingService geofencing;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    // The palette is global, so a change has to rebuild from above
    // MaterialApp for the new ThemeData to be picked up.
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        title: 'Sarvaa Analytics',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            if (auth.loading) return const BrandSplash();
            if (!auth.isSignedIn) return LoginScreen(auth: auth);
            if (auth.profile?.role == 'admin') {
              return AdminShell(
                api: adminApi,
                employeeApi: api,
                auth: auth,
                theme: theme,
                geofencing: geofencing,
              );
            }
            return MainShell(
              api: api,
              auth: auth,
              geofencing: geofencing,
              theme: theme,
            );
          },
        ),
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
    required this.theme,
  });

  final Api api;
  final AuthController auth;
  final GeofencingService geofencing;
  final ThemeController theme;

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
    // Ask once per launch. A refusal is fine — attendance still works by hand,
    // and the Today screen explains what is missing.
    await PermissionsService.ensureNotifications();

    try {
      var readiness = await PermissionsService.check();
      if (!readiness.isReady) {
        // Prompt as soon as the app opens: foreground first, then background
        // ("Allow all the time") where the OS permits it in one flow.
        readiness = await PermissionsService.request();
      }
      if (!readiness.isReady) {
        // Starting the service without "always" permission would report it as
        // running while the OS delivers nothing. Better to leave it off so the
        // UI tells the truth.
        return;
      }
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
      HomeScreen(
        api: widget.api,
        auth: widget.auth,
        geofencing: widget.geofencing,
        onOpenHistory: () => setState(() => _index = 1),
      ),
      HistoryScreen(api: widget.api, auth: widget.auth),
      SettingsScreen(
        api: widget.api,
        auth: widget.auth,
        geofencing: widget.geofencing,
        theme: widget.theme,
      ),
    ];

    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: _index, children: screens)),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today_rounded, color: AppColors.ink),
              label: 'Today',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded, color: AppColors.ink),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded, color: AppColors.ink),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown while the session is being restored.
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(Icons.location_on, color: AppColors.onInk, size: 24),
            ),
            const SizedBox(height: Insets.xxl),
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.line),
            ),
          ],
        ),
      ),
    );
  }
}

class ConfigMissingApp extends StatelessWidget {
  const ConfigMissingApp({super.key, this.theme});

  final ThemeController? theme;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Insets.xxl),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Not configured', style: AppText.title),
                  const SizedBox(height: Insets.sm),
                  Text(
                    'The app needs its Supabase credentials at build time.',
                    style: AppText.body,
                  ),
                  const SizedBox(height: Insets.xxl),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Insets.lg),
                    decoration: BoxDecoration(
                      color: AppColors.sunk,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Text(
                      'flutter run \\\n'
                      '  --dart-define=SUPABASE_URL=... \\\n'
                      '  --dart-define=SUPABASE_ANON_KEY=...',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.6,
                        color: AppColors.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
