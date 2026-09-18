import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/admin_api.dart';
import '../../state/auth_controller.dart';
import 'attendance_screen.dart';
import 'audit_screen.dart';
import 'calendar_screen.dart';
import 'corrections_screen.dart';
import 'dashboard_screen.dart';
import 'employees_screen.dart';
import 'exports_screen.dart';
import 'geofences_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

class AdminSection {
  const AdminSection(this.label, this.icon, this.builder);

  final String label;
  final IconData icon;
  final Widget Function(AdminApi api, AuthController auth) builder;
}

final List<AdminSection> adminSections = [
  AdminSection('Dashboard', Icons.dashboard_outlined,
      (api, auth) => DashboardScreen(api: api)),
  AdminSection('Attendance', Icons.event_note_outlined,
      (api, auth) => AttendanceScreen(api: api)),
  AdminSection('Reports', Icons.bar_chart_outlined,
      (api, auth) => ReportsScreen(api: api)),
  AdminSection('Employees', Icons.people_outline,
      (api, auth) => EmployeesScreen(api: api)),
  AdminSection('Geofences', Icons.map_outlined,
      (api, auth) => GeofencesScreen(api: api)),
  AdminSection('Holidays & WFH', Icons.calendar_month_outlined,
      (api, auth) => CalendarScreen(api: api)),
  AdminSection('Corrections', Icons.build_outlined,
      (api, auth) => CorrectionsScreen(api: api)),
  AdminSection('Audit log', Icons.verified_user_outlined,
      (api, auth) => AuditScreen(api: api)),
  AdminSection('Exports', Icons.file_download_outlined,
      (api, auth) => ExportsScreen(api: api)),
  AdminSection('Settings', Icons.settings_outlined,
      (api, auth) => SettingsScreen(api: api)),
];

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.api, required this.auth});

  final AdminApi api;
  final AuthController auth;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final section = adminSections[_index];
    final profile = widget.auth.profile;

    return Scaffold(
      appBar: AppBar(title: Text(section.label)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Attendance Admin',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            profile?.name ?? '',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < adminSections.length; i++)
                      ListTile(
                        leading: Icon(adminSections[i].icon),
                        title: Text(adminSections[i].label),
                        selected: i == _index,
                        selectedColor: AppColors.primary,
                        onTap: () {
                          setState(() => _index = i);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.danger),
                title: const Text('Sign out', style: TextStyle(color: AppColors.danger)),
                onTap: () async {
                  await widget.auth.signOut();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          for (final item in adminSections) item.builder(widget.api, widget.auth),
        ],
      ),
    );
  }
}
