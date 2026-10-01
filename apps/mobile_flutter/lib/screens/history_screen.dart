import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../state/auth_controller.dart';
import '../widgets/common.dart';
import '../widgets/month_calendar.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.api, required this.auth});

  final Api api;
  final AuthController auth;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _cursor = DateTime(DateTime.now().year, DateTime.now().month);
  List<Attendance> _records = const [];
  String _timezone = 'Asia/Kolkata';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = widget.auth.session?.user.id;
    if (userId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await widget.api.fetchAppSettings();
      final records = await widget.api.fetchMonthAttendance(
        userId,
        _cursor.year,
        _cursor.month,
      );
      if (!mounted) return;
      setState(() {
        _timezone = settings.companyTimezone;
        _records = records;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  bool get _atCurrentMonth {
    final now = DateTime.now();
    return _cursor.year == now.year && _cursor.month == now.month;
  }

  void _shift(int delta) {
    if (delta > 0 && _atCurrentMonth) return;
    setState(() => _cursor = DateTime(_cursor.year, _cursor.month + delta));
    _load();
  }

  int _countOf(Set<String> statuses) =>
      _records.where((record) => statuses.contains(record.status)).length;

  void _openDay(Attendance record) {
    showDayDetailSheet(context, record, _timezone);
  }

  @override
  Widget build(BuildContext context) {
    return Refreshable(
        onRefresh: _load,
        child: ListView(
        padding: AppPadding.page,
        children: [
          const PageHeader(
            title: 'History',
            subtitle: 'Tap any day to see the detail.',
          ),
          _monthBar(),
          const SizedBox(height: Insets.lg),
          if (_loading)
            const _CalendarSkeleton()
          else if (_error != null)
            EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load history',
              message: _error,
              actionLabel: 'Try again',
              onAction: _load,
            )
          else ...[
            _summary(),
            const SizedBox(height: Insets.lg),
            _calendar(),
            const SizedBox(height: Insets.lg),
            _legend(),
          ],
        ],
      ),
    );
  }

  Widget _monthBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _shift(-1),
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous month',
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('MMMM yyyy').format(_cursor),
                style: AppText.subhead.copyWith(fontSize: 16),
              ),
            ),
          ),
          IconButton(
            onPressed: _atCurrentMonth ? null : () => _shift(1),
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next month',
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    final present = _countOf({'PRESENT', 'CHECKED_OUT', 'MANUAL_OVERRIDE'});
    final worked = _records.fold<int>(
      0,
      (total, record) => total + (record.totalDurationSeconds ?? 0),
    );
    return Row(
      children: [
        Expanded(
          child: StatTile(label: 'Present', value: '$present', emphasis: true),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: StatTile(label: 'Hours', value: _hours(worked)),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: StatTile(label: 'Absent', value: '${_countOf({'ABSENT'})}'),
        ),
      ],
    );
  }

  String _hours(int seconds) {
    if (seconds <= 0) return '—';
    return '${(seconds / 3600).floor()}h';
  }

  Widget _calendar() {
    return MonthCalendar(
      month: _cursor,
      records: _records,
      timezone: _timezone,
      onSelect: _openDay,
    );
  }

  /// Monochrome needs a key. Four marks cover everything users see here.
  Widget _legend() {
    const entries = {
      'PRESENT': 'Present',
      'WFH': 'Home',
      'HOLIDAY': 'Holiday',
      'ABSENT': 'Absent',
    };
    return Wrap(
      spacing: Insets.lg,
      runSpacing: Insets.sm,
      children: [
        for (final entry in entries.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusDot(status: entry.key, size: 7),
              const SizedBox(width: Insets.sm),
              Text(entry.value, style: AppText.bodySm.copyWith(fontSize: 12)),
            ],
          ),
      ],
    );
  }
}

class _CalendarSkeleton extends StatelessWidget {
  const _CalendarSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: Insets.md),
              const Expanded(child: SkeletonBlock(height: 74, radius: Radii.md)),
            ],
          ],
        ),
        const SizedBox(height: Insets.lg),
        const SkeletonBlock(height: 280, radius: Radii.lg),
      ],
    );
  }
}
