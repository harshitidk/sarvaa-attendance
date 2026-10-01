import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/admin_api.dart';
import '../../services/api.dart';
import '../../services/geofencing_service.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../../widgets/common.dart';
import 'attendance_screen.dart';
import 'audit_screen.dart';
import 'calendar_screen.dart';
import 'corrections_screen.dart';
import 'dashboard_screen.dart';
import 'employees_screen.dart';
import 'exports_screen.dart';
import 'geofences_screen.dart';
import 'my_attendance_screen.dart';
import 'reports_screen.dart';
import 'requests_screen.dart';
import 'settings_screen.dart';

class AdminSection {
  const AdminSection(this.group, this.label, this.icon, this.builder);

  /// Heading this section sits under in the drawer.
  final String group;
  final String label;
  final IconData icon;
  final Widget Function(
    AdminApi api,
    Api employeeApi,
    AuthController auth,
    ThemeController theme,
    GeofencingService geofencing,
  ) builder;
}

final List<AdminSection> adminSections = [
  AdminSection('Overview', 'Dashboard', Icons.dashboard_outlined,
      (api, employeeApi, auth, theme, geofencing) => DashboardScreen(api: api)),
  AdminSection('Overview', 'My attendance', Icons.login_rounded,
      (api, employeeApi, auth, theme, geofencing) => MyAttendanceScreen(
            adminApi: api,
            api: employeeApi,
            auth: auth,
            geofencing: geofencing,
          )),
  AdminSection('Overview', 'Attendance', Icons.event_note_outlined,
      (api, employeeApi, auth, theme, geofencing) => AttendanceScreen(api: api)),
  AdminSection('Overview', 'Reports', Icons.bar_chart_outlined,
      (api, employeeApi, auth, theme, geofencing) => ReportsScreen(api: api)),
  AdminSection('People', 'Employees', Icons.people_outline,
      (api, employeeApi, auth, theme, geofencing) => EmployeesScreen(api: api)),
  AdminSection('People', 'Requests', Icons.inbox_outlined,
      (api, employeeApi, auth, theme, geofencing) => RequestsScreen(api: api)),
  AdminSection('People', 'Holidays & WFH', Icons.calendar_month_outlined,
      (api, employeeApi, auth, theme, geofencing) => CalendarScreen(api: api)),
  AdminSection('Workplace', 'Geofences', Icons.map_outlined,
      (api, employeeApi, auth, theme, geofencing) => GeofencesScreen(api: api)),
  AdminSection('Workplace', 'Settings', Icons.tune_rounded,
      (api, employeeApi, auth, theme, geofencing) =>
          SettingsScreen(api: api, auth: auth, theme: theme)),
  AdminSection('Records', 'Corrections', Icons.build_outlined,
      (api, employeeApi, auth, theme, geofencing) => CorrectionsScreen(api: api)),
  AdminSection('Records', 'Audit log', Icons.verified_user_outlined,
      (api, employeeApi, auth, theme, geofencing) => AuditScreen(api: api)),
  AdminSection('Records', 'Exports', Icons.file_download_outlined,
      (api, employeeApi, auth, theme, geofencing) => ExportsScreen(api: api)),
];

class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.api,
    required this.employeeApi,
    required this.auth,
    required this.theme,
    required this.geofencing,
  });

  final AdminApi api;
  final Api employeeApi;
  final AuthController auth;
  final ThemeController theme;
  final GeofencingService geofencing;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  /// Sections that have been opened at least once. Only these are built, so
  /// signing in no longer fires ten queries at once; each keeps its state
  /// after the first visit.
  final Set<int> _visited = {0};

  void _select(int index) {
    setState(() {
      _visited.add(index);
      _index = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final section = adminSections[_index];

    return Scaffold(
      appBar: AppBar(
        title: Text(section.label),
        shape: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      drawer: AdminDrawer(
        index: _index,
        profile: widget.auth.profile?.name ?? '',
        email: widget.auth.profile?.email ?? '',
        onSelect: _select,
        onSignOut: () async {
          final confirmed = await confirmDestructive(
            context,
            title: 'Sign out?',
            message: 'You will need to sign in again to manage attendance.',
            confirmLabel: 'Sign out',
          );
          if (confirmed) await widget.auth.signOut();
        },
      ),
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < adminSections.length; i++)
            _visited.contains(i)
                ? adminSections[i].builder(
                    widget.api,
                    widget.employeeApi,
                    widget.auth,
                    widget.theme,
                    widget.geofencing,
                  )
                : const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// Grouped navigation for the admin sections.
class AdminDrawer extends StatelessWidget {
  const AdminDrawer({
    super.key,
    required this.index,
    required this.profile,
    required this.email,
    required this.onSelect,
    required this.onSignOut,
  });

  final int index;
  final String profile;
  final String email;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onSignOut;

  /// Section entries interleaved with their group headings.
  List<Widget> _items(BuildContext context) {
    final items = <Widget>[];
    String? lastGroup;
    for (var i = 0; i < adminSections.length; i++) {
      final section = adminSections[i];
      if (section.group != lastGroup) {
        lastGroup = section.group;
        items.add(
          Padding(
            padding: EdgeInsets.fromLTRB(
              Insets.xl,
              i == 0 ? Insets.sm : Insets.xl,
              Insets.xl,
              Insets.sm,
            ),
            child: Eyebrow(section.group),
          ),
        );
      }
      items.add(
        _DrawerItem(
          section: section,
          selected: i == index,
          onTap: () {
            onSelect(i);
            Navigator.of(context).pop();
          },
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 296,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.xl,
                Insets.xl,
                Insets.xl,
                Insets.lg,
              ),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      color: AppColors.onInk,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.isEmpty ? 'Administrator' : profile,
                          style: AppText.subhead,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          email,
                          style: AppText.bodySm.copyWith(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
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
                padding: const EdgeInsets.symmetric(vertical: Insets.md),
                children: _items(context),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await onSignOut();
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final AdminSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: Insets.md,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: [
              Icon(
                section.icon,
                size: 19,
                color: selected ? AppColors.onInk : AppColors.muted,
              ),
              const SizedBox(width: Insets.md),
              Text(
                section.label,
                style: AppText.subhead.copyWith(
                  fontSize: 14.5,
                  color: selected ? AppColors.onInk : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
