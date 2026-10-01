import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../services/geofencing_service.dart';
import '../services/permissions_service.dart';
import '../state/auth_controller.dart';
import '../utils/attendance_logic.dart';
import '../widgets/common.dart';
import '../widgets/month_calendar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.geofencing,
    this.onOpenHistory,
  });

  final Api api;
  final AuthController auth;
  final GeofencingService geofencing;

  /// Switches the shell to the History tab.
  final VoidCallback? onOpenHistory;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppSettings _settings = const AppSettings();
  List<Geofence> _geofences = const [];
  List<WfhRequest> _wfhRequests = const [];
  List<LeaveRequest> _leaveRequests = const [];
  List<Attendance> _monthRecords = const [];
  List<Attendance> _quarterRecords = const [];
  Attendance? _today;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Timer? _ticker;
  DateTime _now = DateTime.now();
  BackgroundReadiness? _readiness;

  late final ({String from, String to, String label}) _quarter =
      quarterBounds(DateTime.now());

  String get _timezone => _settings.companyTimezone;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshReadiness();
    // Keeps the live clock and the running duration honest without a
    // per-second rebuild.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = widget.auth.session?.user.id;
    if (userId == null) return;
    try {
      final settings = await widget.api.fetchAppSettings();
      final now = DateTime.now();
      final quarter = quarterBounds(now);
      final results = await Future.wait([
        widget.api.fetchAssignedGeofences(),
        widget.api.fetchTodayAttendance(userId, settings.companyTimezone),
        widget.api.fetchMyWfhRequests(userId, limit: 10),
        widget.api.fetchMyLeaveRequests(userId, limit: 10),
        widget.api.fetchMonthAttendance(userId, now.year, now.month),
        widget.api.fetchAttendanceRange(userId, quarter.from, quarter.to),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _geofences = results[0] as List<Geofence>;
        _today = results[1] as Attendance?;
        _wfhRequests = results[2] as List<WfhRequest>;
        _leaveRequests = results[3] as List<LeaveRequest>;
        _monthRecords = results[4] as List<Attendance>;
        _quarterRecords = results[5] as List<Attendance>;
        _error = null;
        _loading = false;
        _now = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _refreshReadiness() async {
    final readiness = await PermissionsService.check();
    if (mounted) setState(() => _readiness = readiness);
  }

  /// Asks for background location, then sends the user to settings if the OS
  /// will not grant "Allow all the time" from a dialog (Android 11+).
  Future<void> _fixPermissions() async {
    final before = _readiness;
    if (before == BackgroundReadiness.servicesDisabled) {
      await PermissionsService.openLocationSettings();
      await _refreshReadiness();
      return;
    }
    final after = await PermissionsService.request();
    if (!mounted) return;
    setState(() => _readiness = after);

    if (!after.isReady && after != BackgroundReadiness.denied) {
      await PermissionsService.openSettings();
      await _refreshReadiness();
      return;
    }
    if (after.isReady) {
      await widget.geofencing.sync(_geofences);
      if (mounted) setState(() {});
    }
  }

  Future<Position> _currentPosition() async {
    await PermissionsService.ensureForeground();
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on TimeoutException {
      throw Exception(
        'Could not get a location fix. Move to an open area or turn GPS on, '
        'then try again.',
      );
    }
  }

  Future<void> _checkIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final previous = _today;
    try {
      final position = await _currentPosition();
      final decision = evaluateCheckIn(
        latitude: position.latitude,
        longitude: position.longitude,
        geofences: _geofences,
        isMocked: position.isMocked,
      );
      if (!decision.allowed) {
        throw Exception(decision.error);
      }
      final fence = decision.fence!;
      final now = DateTime.now().toUtc();
      if (previous != null) {
        setState(() => _today = previous.copyWith(
              status: 'PRESENT',
              checkInAt: previous.checkInAt ?? now,
              clearCheckOut: true,
              totalDurationSeconds: 0,
            ));
      }
      await widget.api.recordLocationEvent(
        geofenceId: fence.id,
        eventType: 'ENTER',
        occurredAt: now,
        accuracyMeters: position.accuracy,
        latitude: position.latitude,
        longitude: position.longitude,
        source: 'Mobile geolocation',
        metadata: const {'platform': 'flutter', 'note': 'explicit check-in'},
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _today = previous;
          _error = describeError(error);
        });
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (mounted) showToast(context, 'Checked in');
  }

  Future<void> _submitCheckout({required bool isUpdate}) async {
    final current = _today;
    if (current == null || current.id.isEmpty) {
      setState(() => _error = 'Check in before checking out.');
      return;
    }
    final summary = await showCheckoutSheet(
      context,
      initialSummary: current.workSummary ?? '',
      isUpdate: isUpdate,
    );
    if (summary == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _today = _optimisticCheckout(current, summary);
    });
    final previous = current;
    try {
      await widget.api.employeeCheckOut(
        attendanceId: current.id,
        summary: summary,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _today = previous;
          _error = describeError(error);
        });
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (mounted) {
      showToast(context, isUpdate ? 'Summary updated' : 'Checked out');
    }
  }

  Attendance _optimisticCheckout(Attendance current, String summary) {
    final checkOutAt = current.checkOutAt ?? DateTime.now().toUtc();
    return current.copyWith(
      status: 'CHECKED_OUT',
      checkOutAt: checkOutAt,
      workSummary: summary,
      workSummaryAt: current.workSummary == null
          ? DateTime.now().toUtc()
          : current.workSummaryAt,
      totalDurationSeconds: current.checkInAt == null
          ? current.totalDurationSeconds
          : durationSeconds(current.checkInAt!, checkOutAt),
    );
  }

  Future<void> _requestWfh() async {
    final userId = widget.auth.session?.user.id;
    if (userId == null) return;
    final input = await showWfhRequestSheet(context);
    if (input == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.requestWfh(
        userId: userId,
        date: isoDate(input.date),
        reason: input.reason,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = _requestError(error));
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (mounted) showToast(context, 'Request sent for approval');
  }

  Future<void> _requestLeave() async {
    final userId = widget.auth.session?.user.id;
    if (userId == null) return;
    final input = await showLeaveRequestSheet(context);
    if (input == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.requestLeave(
        userId: userId,
        date: isoDate(input.date),
        leaveType: input.type,
        reason: input.reason,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = _requestError(error));
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (mounted) showToast(context, 'Leave request sent for approval');
  }

  /// The unique index and the date policy surface as raw Postgres errors.
  String _requestError(Object error) {
    final text = describeError(error);
    if (text.contains('one_open_per_day') || text.contains('duplicate key')) {
      return 'You already have a request awaiting approval for that day.';
    }
    if (text.contains('row-level security') || text.contains('violates')) {
      return 'That date cannot be requested. Pick today or a future day.';
    }
    return text;
  }

  Future<void> _cancelWfh(WfhRequest request) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Withdraw request?',
      message: 'Your work-from-home request for '
          '${formatBusinessDate(request.date, 'd MMMM')} will be withdrawn.',
      confirmLabel: 'Withdraw',
    );
    if (!confirmed) return;
    try {
      await widget.api.cancelWfhRequest(request.id);
      await _load();
      if (mounted) showToast(context, 'Request withdrawn');
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    }
  }

  Future<void> _cancelLeave(LeaveRequest request) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Withdraw request?',
      message: 'Your ${request.leaveType.label.toLowerCase()} request for '
          '${formatBusinessDate(request.date, 'd MMMM')} will be withdrawn.',
      confirmLabel: 'Withdraw',
    );
    if (!confirmed) return;
    try {
      await widget.api.cancelLeaveRequest(request.id);
      await _load();
      if (mounted) showToast(context, 'Request withdrawn');
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    }
  }

  void _openDay(Attendance record) {
    showDayDetailSheet(context, record, _timezone);
  }

  void _openQuarter() {
    final summary = QuarterSummary.fromRecords(_quarterRecords);
    showAppSheet<void>(
      context,
      builder: (context) => SheetShell(
        title: 'My quarter',
        subtitle: _quarter.label,
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Leaves taken',
                  value: '${summary.leaves}',
                  emphasis: true,
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: StatTile(label: 'Work hours', value: '${summary.workHours}'),
              ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              Expanded(child: CountCell(label: 'Present', value: summary.present)),
              Expanded(child: CountCell(label: 'Home', value: summary.wfh)),
              Expanded(child: CountCell(label: 'Absent', value: summary.absent)),
              Expanded(child: CountCell(label: 'Holiday', value: summary.holidays)),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ render

  bool get _canEditSummary => canEditSummary(_today?.workSummaryAt, _now);

  @override
  Widget build(BuildContext context) {
    final name = widget.auth.profile?.name.split(' ').first ?? '';

    // The greeting is known before the data is, so it stays put while the
    // rest loads instead of popping in underneath a spinner.
    if (_loading) {
      return ListView(
        padding: AppPadding.page,
        children: [
          PageHeader(
            title: name.isEmpty ? _greeting() : '${_greeting()}, $name',
            subtitle: DateFormat('EEEE, d MMMM').format(_now),
          ),
          const SkeletonBlock(height: 250, radius: Radii.xl),
          const SizedBox(height: Insets.md),
          const SkeletonBlock(height: 60, radius: Radii.lg),
          const SizedBox(height: Insets.lg),
          const SkeletonBlock(height: 260, radius: Radii.lg),
        ],
      );
    }

    final today = _today;
    return Refreshable(
      onRefresh: _load,
      child: ListView(
        padding: AppPadding.page,
        children: [
          PageHeader(
            title: name.isEmpty ? _greeting() : '${_greeting()}, $name',
            subtitle: DateFormat('EEEE, d MMMM').format(_now),
          ),
          TodayHero(
            status: today?.status,
            now: _now,
            timezone: _timezone,
            checkInAt: today?.checkInAt,
            checkOutAt: today?.checkOutAt,
            totalDurationSeconds: today?.totalDurationSeconds,
            visitCount: today?.visitCount ?? 0,
          ),
          const SizedBox(height: Insets.md),
          if (_error != null) ...[
            Notice(_error!, tone: NoticeTone.alert),
            const SizedBox(height: Insets.md),
          ],
          if (_readiness != null && !_readiness!.isReady) ...[
            _PermissionBanner(
              readiness: _readiness!,
              onFix: _busy ? null : _fixPermissions,
            ),
            const SizedBox(height: Insets.md),
          ],
          _primaryAction(),
          if (today?.workSummary != null) ...[
            const SizedBox(height: Insets.lg),
            _summaryCard(today!),
          ],
          const SizedBox(height: Insets.xxl),
          _calendarCard(),
          const SizedBox(height: Insets.xxl),
          _requestsCard(),
          const SizedBox(height: Insets.xxl),
          _quarterCard(),
        ],
      ),
    );
  }

  String _greeting() {
    final hour = _now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// The one thing to do next, sized so it cannot be missed.
  Widget _primaryAction() {
    final today = _today;
    if (today?.checkInAt == null) {
      return Column(
        children: [
          BusyButton(
            label: 'Check in',
            icon: Icons.login_rounded,
            busy: _busy,
            large: true,
            onPressed: _checkIn,
          ),
          const SizedBox(height: Insets.md),
          Text(
            'We confirm you are inside your workplace before recording anything.',
            textAlign: TextAlign.center,
            style: AppText.bodySm.copyWith(fontSize: 12.5),
          ),
        ],
      );
    }
    if (today?.checkOutAt == null) {
      return Column(
        children: [
          BusyButton(
            label: 'Check out',
            icon: Icons.logout_rounded,
            busy: _busy,
            large: true,
            onPressed: () => _submitCheckout(isUpdate: false),
          ),
          const SizedBox(height: Insets.md),
          Text(
            'A short work summary is required.',
            textAlign: TextAlign.center,
            style: AppText.bodySm.copyWith(fontSize: 12.5),
          ),
        ],
      );
    }
    if (_canEditSummary) {
      final remaining = summaryEditRemaining(today!.workSummaryAt, _now).inMinutes;
      return Column(
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _submitCheckout(isUpdate: true),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Update work summary'),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            remaining <= 1
                ? 'Editing closes in under a minute.'
                : 'Editable for $remaining more minutes.',
            textAlign: TextAlign.center,
            style: AppText.bodySm.copyWith(fontSize: 12.5),
          ),
        ],
      );
    }
    return const Notice(
      'Your work summary is locked. Ask an admin if it needs a correction.',
    );
  }

  Widget _summaryCard(Attendance today) {
    return SectionCard(
      title: 'Work summary',
      trailing: Icon(
        _canEditSummary ? Icons.edit_outlined : Icons.lock_outline_rounded,
        size: 17,
        color: AppColors.muted,
      ),
      child: Text(today.workSummary!, style: AppText.body),
    );
  }

  Widget _calendarCard() {
    return SectionCard(
      title: 'This month',
      trailing: widget.onOpenHistory == null
          ? null
          : TextButton(
              onPressed: widget.onOpenHistory,
              child: const Text('History'),
            ),
      child: MonthCalendar(
        month: _now,
        records: _monthRecords,
        timezone: _timezone,
        compact: true,
        onSelect: _openDay,
      ),
    );
  }

  /// Work-from-home and leave, in one place: ask for either, and see what is
  /// still waiting on a manager.
  Widget _requestsCard() {
    final pendingWfh = _wfhRequests.where((request) => request.isPending);
    final pendingLeave = _leaveRequests.where((request) => request.isPending);

    return SectionCard(
      title: 'Requests',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _requestWfh,
            icon: const Icon(Icons.house_outlined, size: 18),
            label: const Text('Request work from home'),
          ),
          const SizedBox(height: Insets.md),
          OutlinedButton.icon(
            onPressed: _busy ? null : _requestLeave,
            icon: const Icon(Icons.event_busy_outlined, size: 18),
            label: const Text('Request leave'),
          ),
          if (pendingWfh.isEmpty && pendingLeave.isEmpty) ...[
            const SizedBox(height: Insets.lg),
            Text(
              'Ask for a day from home or a day off. Your manager approves it, '
              'and it lands in your calendar.',
              style: AppText.bodySm,
            ),
          ] else ...[
            const SizedBox(height: Insets.lg),
            Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: Insets.md),
            for (final request in pendingWfh) ...[
              _PendingLine(
                icon: Icons.house_outlined,
                title: 'Work from home',
                date: request.date,
                onWithdraw: _busy ? null : () => _cancelWfh(request),
              ),
            ],
            for (final request in pendingLeave) ...[
              _PendingLine(
                icon: Icons.event_busy_outlined,
                title: request.leaveType.label,
                date: request.date,
                onWithdraw: _busy ? null : () => _cancelLeave(request),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _quarterCard() {
    final summary = QuarterSummary.fromRecords(_quarterRecords);
    return SectionCard(
      title: 'My quarter',
      trailing: TextButton(
        onPressed: _openQuarter,
        child: const Text('Details'),
      ),
      child: Row(
        children: [
          Expanded(
            child: StatTile(
              label: '${_quarter.label} leaves',
              value: '${summary.leaves}',
              emphasis: true,
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: StatTile(
              label: 'Work hours',
              value: '${summary.workHours}',
            ),
          ),
        ],
      ),
    );
  }
}

/// One request still waiting on a manager, with a way to take it back.
class _PendingLine extends StatelessWidget {
  const _PendingLine({
    required this.icon,
    required this.title,
    required this.date,
    required this.onWithdraw,
  });

  final IconData icon;
  final String title;
  final String date;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.ink),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.subhead.copyWith(fontSize: 14)),
                Text(
                  '${formatBusinessDate(date, 'EEE, d MMM')} · Awaiting approval',
                  style: AppText.bodySm.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onWithdraw, child: const Text('Withdraw')),
        ],
      ),
    );
  }
}

/// Surfaces the one thing standing between the employee and automatic
/// attendance, with the single action that fixes it.
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.readiness, required this.onFix});

  final BackgroundReadiness readiness;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: AppColors.sunk,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 17, color: AppColors.ink),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(readiness.title, style: AppText.subhead.copyWith(fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Text(readiness.message, style: AppText.bodySm.copyWith(fontSize: 12.5)),
          if (readiness.actionLabel != null) ...[
            const SizedBox(height: Insets.md),
            OutlinedButton(
              onPressed: onFix,
              child: Text(readiness.actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
