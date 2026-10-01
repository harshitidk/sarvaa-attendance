import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/admin_api.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../../utils/attendance_logic.dart';
import '../../widgets/common.dart';

const _weekdayLabels = {1: 'M', 2: 'T', 3: 'W', 4: 'T', 5: 'F', 6: 'S', 7: 'S'};

const _weekdayNames = {
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
  7: 'Sunday',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.theme,
  });

  final AdminApi api;
  final AuthController auth;
  final ThemeController theme;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _timezone = TextEditingController();
  final _grace = TextEditingController();
  final _retention = TextEditingController();

  String _workdayStart = '09:00';
  String _workdayEnd = '18:00';
  Set<int> _workingDays = {1, 2, 3, 4, 5, 6};
  bool _attendanceEnabled = false;
  bool _attendanceBusy = false;

  bool _loading = true;
  bool _saving = false;
  String? _message;
  String? _error;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timezone.dispose();
    _grace.dispose();
    _retention.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _error = null;
    });
    try {
      final AppSettings settings = await widget.api.fetchSettings();
      if (!mounted) return;
      _timezone.text = settings.companyTimezone;
      _grace.text = settings.exitGraceSeconds.toString();
      _retention.text = settings.eventRetentionDays.toString();
      _workdayStart = _normalizeTime(settings.workdayStart, '09:00');
      _workdayEnd = _normalizeTime(settings.workdayEnd, '18:00');
      _workingDays = settings.workingDays.toSet();
      _attendanceEnabled = widget.auth.profile?.attendanceEnabled ?? false;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = describeError(error);
        _loading = false;
      });
    }
  }

  /// Postgres returns `HH:MM:SS`; the picker needs `HH:MM`.
  String _normalizeTime(String value, String fallback) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return fallback;
    final hour = match.group(1)!.padLeft(2, '0');
    return '$hour:${match.group(2)}';
  }

  /// `14:30` -> `2:30 PM`, so the form reads the way the app does.
  String _display(String value) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final suffix = hour < 12 ? 'AM' : 'PM';
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return '$display:${minute.toString().padLeft(2, '0')} $suffix';
  }

  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      ),
    );
    if (picked == null) return;
    onPicked(
      '${picked.hour.toString().padLeft(2, '0')}:'
      '${picked.minute.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _toggleAttendance(bool value) async {
    final id = widget.auth.session?.user.id;
    if (id == null) return;
    setState(() {
      _attendanceBusy = true;
      _error = null;
    });
    try {
      await widget.api.updateEmployee(id, attendanceEnabled: value);
      await widget.auth.refreshProfile();
      if (mounted) setState(() => _attendanceEnabled = value);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _attendanceBusy = false);
    }
  }

  Future<void> _save() async {
    final timezone = _timezone.text.trim();
    final grace = int.tryParse(_grace.text.trim());
    final retention = int.tryParse(_retention.text.trim());

    if (timezone.isEmpty) {
      setState(
        () => _error = 'Company timezone is required (e.g. Asia/Kolkata).',
      );
      return;
    }
    if (grace == null || grace < 0) {
      setState(
        () => _error = 'Exit grace must be a number of seconds (0 or more).',
      );
      return;
    }
    if (retention == null || retention <= 0) {
      setState(
        () => _error = 'Event retention must be a positive number of days.',
      );
      return;
    }
    if (_workingDays.isEmpty) {
      setState(() => _error = 'Select at least one working day.');
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
      _error = null;
    });
    try {
      final saved = await widget.api.updateSettings(
        companyTimezone: timezone,
        workdayStart: _workdayStart,
        workdayEnd: _workdayEnd,
        exitGraceSeconds: grace,
        eventRetentionDays: retention,
        workingDays: _workingDays.toList()..sort(),
      );
      if (mounted) {
        setState(() {
          if (saved) {
            _message = 'Settings saved.';
          } else {
            _error =
                'Settings were not saved. Check that the database migrations '
                'are applied and your account has admin access.';
          }
        });
        if (saved) showToast(context, 'Settings saved');
      }
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenState(
      loading: _loading,
      error: _loadError,
      onRetry: _load,
      child: Refreshable(
        onRefresh: _load,
        child: ListView(
          padding: AppPadding.page,
          children: [
            const ScreenCaption(
              'These values drive the attendance engine for everyone.',
            ),
            SectionCard(
              title: 'My attendance',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Track my own check-ins and check-outs, like the team. '
                      'Optional — turn it off any time.',
                      style: AppText.body,
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Switch(
                    value: _attendanceEnabled,
                    onChanged: _attendanceBusy ? null : _toggleAttendance,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Insets.xl),
            const FieldLabel(
              'Company timezone',
              hint: 'IANA name, e.g. Asia/Kolkata.',
            ),
            TextField(
              controller: _timezone,
              enabled: !_saving,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'Asia/Kolkata'),
            ),
            const SizedBox(height: Insets.xxl),
            const Eyebrow('Working hours'),
            const SizedBox(height: Insets.sm),
            GroupedList(
              children: [
                _timeRow(
                  'Workday start',
                  _workdayStart,
                  (value) => setState(() => _workdayStart = value),
                ),
                _timeRow(
                  'Workday end',
                  _workdayEnd,
                  (value) => setState(() => _workdayEnd = value),
                ),
              ],
            ),
            const SizedBox(height: Insets.xxl),
            const FieldLabel(
              'Working days',
              hint: 'The recurring weekly pattern, used for reports.',
            ),
            _dayPicker(),
            const SizedBox(height: Insets.md),
            const Notice(
              'This is the weekly rhythm, not a calendar. To excuse one '
              'specific date, use Holidays & WFH — a company WFH day there '
              'means nobody has to check in, without changing this pattern.',
            ),
            const SizedBox(height: Insets.sm),
            Text(
              _workingDays.isEmpty
                  ? 'No working days selected'
                  : (_workingDays.toList()..sort())
                        .map((day) => _weekdayNames[day])
                        .join(', '),
              style: AppText.bodySm.copyWith(fontSize: 12),
            ),
            const SizedBox(height: Insets.xxl),
            const FieldLabel(
              'Exit grace',
              hint: 'Seconds. Re-entry within this window cancels a check-out.',
            ),
            TextField(
              controller: _grace,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(suffixText: 'seconds'),
            ),
            const SizedBox(height: Insets.xl),
            const FieldLabel(
              'Event retention',
              hint: 'How long raw location events are kept for audit.',
            ),
            TextField(
              controller: _retention,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(suffixText: 'days'),
            ),
            const SizedBox(height: Insets.xxl),
            BusyButton(label: 'Save settings', busy: _saving, onPressed: _save),
            if (_message != null) ...[
              const SizedBox(height: Insets.lg),
              Notice(_message!, tone: NoticeTone.success),
            ],
            if (_error != null) ...[
              const SizedBox(height: Insets.lg),
              Notice(_error!, tone: NoticeTone.alert),
            ],
          ],
        ),
      ),
    );
  }

  Widget _timeRow(String label, String value, ValueChanged<String> onPicked) {
    return AppRow(
      title: label,
      onTap: _saving ? null : () => _pickTime(value, onPicked),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_display(value), style: AppText.numeral.copyWith(fontSize: 15)),
          const SizedBox(width: Insets.sm),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.faint,
          ),
        ],
      ),
    );
  }

  Widget _dayPicker() {
    return Row(
      children: [
        for (final entry in _weekdayLabels.entries) ...[
          if (entry.key > 1) const SizedBox(width: Insets.sm),
          Expanded(
            child: DayToggle(
              label: entry.value,
              selected: _workingDays.contains(entry.key),
              onTap: _saving
                  ? null
                  : () => setState(() {
                      if (!_workingDays.remove(entry.key)) {
                        _workingDays.add(entry.key);
                      }
                    }),
            ),
          ),
        ],
      ],
    );
  }
}


