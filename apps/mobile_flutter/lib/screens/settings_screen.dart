import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../services/geofencing_service.dart';
import '../state/auth_controller.dart';
import '../utils/attendance_logic.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.geofencing,
  });

  final Api api;
  final AuthController auth;
  final GeofencingService geofencing;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<LocationEvent> _events = const [];
  String _timezone = 'Asia/Kolkata';
  bool _geofencingActive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = widget.auth.session?.user.id;
    if (userId == null) return;
    final settings = await widget.api.fetchAppSettings();
    final events = await widget.api.fetchRecentEvents(userId);
    if (!mounted) return;
    setState(() {
      _timezone = settings.companyTimezone;
      _events = events;
      _geofencingActive = widget.geofencing.isRunning;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.auth.profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'Account',
          child: Column(
            children: [
              _row('Name', profile?.name ?? '—'),
              _row('Employee ID', profile?.employeeId ?? '—'),
              _row('Email', profile?.email ?? '—'),
              _row('Department', profile?.department ?? '—'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Background detection',
          child: Text(
            _geofencingActive
                ? 'Automatic detection is active. Attendance is recorded on geofence transitions.'
                : 'Automatic detection is not running. Use the manual check-in/out buttons on Today.',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Recent location events',
          child: _events.isEmpty
              ? const Text(
                  'No events recorded yet.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                )
              : Column(
                  children: _events
                      .map(
                        (event) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                event.eventType,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${formatTime(event.occurredAt, _timezone)}'
                                '${event.accuracyMeters != null ? ' · ±${event.accuracyMeters!.round()}m' : ''}',
                                style: const TextStyle(color: AppColors.muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            await widget.geofencing.stop();
            await widget.auth.signOut();
          },
          icon: const Icon(Icons.logout, color: AppColors.danger),
          label: const Text('Sign out', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
