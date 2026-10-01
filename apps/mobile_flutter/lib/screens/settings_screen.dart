import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../services/geofencing_service.dart';
import '../services/permissions_service.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
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
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _timezone = 'Asia/Kolkata';
  bool _geofencingActive = false;
  BackgroundReadiness? _readiness;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = widget.auth.session?.user.id;
    if (userId == null) return;
    try {
      final settings = await widget.api.fetchAppSettings();
      final readiness = await PermissionsService.check();
      if (!mounted) return;
      setState(() {
        _timezone = settings.companyTimezone;
        _readiness = readiness;
        _geofencingActive = widget.geofencing.isRunning && readiness.isReady;
      });
    } catch (_) {
      // Background detection is optional; the rest of the screen still works.
    }
  }

  Future<void> _signOut() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Sign out?',
      message: 'Automatic attendance detection will stop until you sign in again.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;
    await widget.geofencing.stop();
    await widget.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.auth.profile;

    return Refreshable(
        onRefresh: _load,
        child: ListView(
        padding: AppPadding.page,
        children: [
          const PageHeader(title: 'Settings'),
          _identity(profile),
          const SizedBox(height: Insets.xl),
          GroupedList(
            title: 'Account',
            children: [
              AppRow(
                title: 'Employee ID',
                trailing: Text(
                  profile?.employeeId.isNotEmpty == true
                      ? profile!.employeeId
                      : '—',
                  style: AppText.numeral.copyWith(fontSize: 14),
                ),
              ),
              AppRow(
                title: 'Email',
                trailing: Flexible(
                  child: Text(
                    profile?.email ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySm.copyWith(color: AppColors.ink2),
                  ),
                ),
              ),
              AppRow(
                title: 'Department',
                trailing: Text(
                  profile?.department ?? '—',
                  style: AppText.bodySm.copyWith(color: AppColors.ink2),
                ),
              ),
              AppRow(
                title: 'Timezone',
                trailing: Text(
                  _timezone,
                  style: AppText.bodySm.copyWith(color: AppColors.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.xl),
          AppearanceCard(controller: widget.theme),
          const SizedBox(height: Insets.xl),
          _detection(),
          const SizedBox(height: Insets.xxl),
          OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Widget _identity(UserProfile? profile) {
    final name = profile?.name ?? '';
    return Row(
      children: [
        InitialsAvatar(name: name, size: 56, inverted: true),
        const SizedBox(width: Insets.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Employee' : name,
                style: AppText.title.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 2),
              Text(
                profile?.role == 'admin' ? 'Administrator' : 'Employee',
                style: AppText.bodySm,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detection() {
    return SectionCard(
      title: 'Background detection',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 3),
        decoration: BoxDecoration(
          color: _geofencingActive ? AppColors.ink : AppColors.sunk,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color: _geofencingActive ? AppColors.ink : AppColors.hairline,
          ),
        ),
        child: Text(
          _geofencingActive ? 'ON' : 'OFF',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: _geofencingActive ? AppColors.onInk : AppColors.muted,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _readiness?.message ??
                'Record your attendance from Today while this is checked.',
            style: AppText.bodySm,
          ),
          if (_readiness != null && !_readiness!.isReady) ...[
            const SizedBox(height: Insets.md),
            OutlinedButton(
              onPressed: () async {
                await PermissionsService.openSettings();
                await _load();
              },
              child: const Text('Open settings'),
            ),
          ],
        ],
      ),
    );
  }

}
