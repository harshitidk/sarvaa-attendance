import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/admin_api.dart';
import '../../services/api.dart';
import '../../services/geofencing_service.dart';
import '../../state/auth_controller.dart';
import '../../utils/attendance_logic.dart';
import '../../widgets/common.dart';
import '../home_screen.dart';

/// The admin's own attendance. Admins who opt in get the same check-in /
/// check-out experience as employees; the toggle lives in Settings and can be
/// turned off again at any time.
class MyAttendanceScreen extends StatefulWidget {
  const MyAttendanceScreen({
    super.key,
    required this.adminApi,
    required this.api,
    required this.auth,
    required this.geofencing,
  });

  final AdminApi adminApi;
  final Api api;
  final AuthController auth;
  final GeofencingService geofencing;

  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  bool? _enabled;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.auth.session?.user.id;
    if (id == null) {
      setState(() => _enabled = false);
      return;
    }
    try {
      final profile = await widget.api.fetchProfile(id);
      if (!mounted) return;
      setState(() => _enabled = profile?.attendanceEnabled ?? false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeError(error);
        _enabled = false;
      });
    }
  }

  Future<void> _setEnabled(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.setMyAttendanceEnabled(value);
      await widget.auth.refreshProfile();
      if (!mounted) return;
      setState(() => _enabled = value);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    if (enabled == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (enabled) {
      return HomeScreen(
        api: widget.api,
        auth: widget.auth,
        geofencing: widget.geofencing,
      );
    }

    return ListView(
      padding: AppPadding.page,
      children: [
        SectionCard(
          title: 'My attendance',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Attendance tracking is off for your admin account. Turn it on '
                'to check in and out like the team. You can turn it off again '
                'from Settings.',
                style: AppText.body,
              ),
              const SizedBox(height: Insets.lg),
              BusyButton(
                label: 'Enable attendance tracking',
                icon: Icons.login_rounded,
                busy: _busy,
                onPressed: () => _setEnabled(true),
              ),
              if (_error != null) ...[
                const SizedBox(height: Insets.lg),
                Notice(_error!, tone: NoticeTone.alert),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
