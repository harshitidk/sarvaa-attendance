import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../utils/attendance_logic.dart';
import '../../widgets/common.dart';
import 'employee_report_screen.dart';

enum _Preset { thisMonth, pastMonth, thisQuarter, pastQuarter, past6Months, custom }

extension on _Preset {
  String get label => switch (this) {
        _Preset.thisMonth => 'This month',
        _Preset.pastMonth => 'Past month',
        _Preset.thisQuarter => 'This quarter',
        _Preset.pastQuarter => 'Past quarter',
        _Preset.past6Months => 'Past 6 months',
        _Preset.custom => 'Custom',
      };
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Preset _preset = _Preset.thisMonth;
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _to = DateTime.now();
  List<AttendanceRow> _rows = const [];
  String _timezone = 'Asia/Kolkata';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyPreset(_Preset.thisMonth);
  }

  void _applyPreset(_Preset preset) {
    final now = DateTime.now();
    DateTime from;
    DateTime to = now;
    switch (preset) {
      case _Preset.thisMonth:
        from = DateTime(now.year, now.month, 1);
      case _Preset.pastMonth:
        from = DateTime(now.year, now.month - 1, 1);
        to = DateTime(now.year, now.month, 0);
      case _Preset.thisQuarter:
        from = DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1);
      case _Preset.pastQuarter:
        final qStart = ((now.month - 1) ~/ 3) * 3 + 1;
        from = DateTime(now.year, qStart - 3, 1);
        to = DateTime(now.year, qStart, 0);
      case _Preset.past6Months:
        from = DateTime(now.year, now.month - 5, 1);
      case _Preset.custom:
        return;
    }
    setState(() {
      _preset = preset;
      _from = from;
      _to = to;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await widget.api.fetchSettings();
      final rows = await widget.api.fetchAttendanceRange(isoDate(_from), isoDate(_to));
      if (!mounted) return;
      setState(() {
        _timezone = settings.companyTimezone;
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _pick(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _preset = _Preset.custom;
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
    await _load();
  }

  /// One entry per employee, derived from their rows in the range.
  List<_EmployeeReport> _grouped() {
    final map = <String, _EmployeeReport>{};
    for (final row in _rows) {
      final entry = map.putIfAbsent(
        row.userId,
        () => _EmployeeReport(id: row.userId, name: row.employeeName, code: row.employeeCode),
      );
      entry.add(row, _timezone);
    }
    final list = map.values.toList()
      ..sort((a, b) => b.workSeconds.compareTo(a.workSeconds));
    return list;
  }

  void _open(_EmployeeReport report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeReportScreen(
          api: widget.api,
          userId: report.id,
          name: report.name,
          code: report.code,
          from: _from,
          to: _to,
          timezone: _timezone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _grouped();

    return Column(
      children: [
        Padding(
          padding: AppPadding.bar,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final preset in _Preset.values)
                      if (preset != _Preset.custom)
                        Padding(
                          padding: const EdgeInsets.only(right: Insets.sm),
                          child: _FilterChip(
                            label: preset.label,
                            selected: _preset == preset,
                            onTap: () => _applyPreset(preset),
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.sm),
              DateRangeBar(from: _from, to: _to, onPick: _pick),
            ],
          ),
        ),
        Expanded(
          child: ScreenState(
            loading: _loading,
            error: _error,
            onRetry: _load,
            child: entries.isEmpty
                ? const EmptyState(
                    icon: Icons.bar_chart_outlined,
                    title: 'No records in this range',
                    message: 'Pick a wider range to see per-employee totals.',
                  )
                : Refreshable(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: AppPadding.pageBelowBar,
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
                      itemBuilder: (context, index) {
                        final report = entries[index];
                        return SectionCard(
                          title: report.name.isEmpty ? report.code : report.name,
                          trailing: Text(
                            '${report.attendedDays} day${report.attendedDays == 1 ? '' : 's'}',
                            style: AppText.bodySm.copyWith(fontSize: 12),
                          ),
                          child: InkWell(
                            onTap: () => _open(report),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TimeStat(
                                        label: 'Time in office',
                                        value: formatDuration(report.workSeconds),
                                      ),
                                    ),
                                    Expanded(
                                      child: _TimeStat(
                                        label: 'Avg / attended day',
                                        value: report.attendedDays == 0
                                            ? '—'
                                            : formatDuration(report.averageSeconds),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: Insets.lg),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TimeStat(
                                        label: 'Avg check-in',
                                        value: report.averageCheckIn ?? '—',
                                      ),
                                    ),
                                    Expanded(
                                      child: _TimeStat(
                                        label: 'Days present',
                                        value: '${report.presentDays}',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: Insets.md),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      'View profile',
                                      style: AppText.bodySm.copyWith(fontSize: 12.5),
                                    ),
                                    const Icon(Icons.chevron_right_rounded, size: 18),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Per-employee roll-up over the selected range.
class _EmployeeReport {
  _EmployeeReport({required this.id, required this.name, required this.code});

  final String id;
  final String name;
  final String code;

  int presentDays = 0;
  int wfh = 0;
  int leave = 0;
  int holiday = 0;
  int absent = 0;
  int workSeconds = 0;
  int attendedDays = 0;
  int visits = 0;
  int _checkInMinutes = 0;
  int _checkInCount = 0;

  int get averageSeconds => attendedDays == 0 ? 0 : workSeconds ~/ attendedDays;

  /// Average check-in clock time across the days attended.
  String? get averageCheckIn {
    if (_checkInCount == 0) return null;
    return formatMinuteOfDay((_checkInMinutes / _checkInCount).round());
  }

  void add(AttendanceRow row, String timezone) {
    final at = row.checkInAt;
    if (at != null) {
      _checkInMinutes += localMinuteOfDay(at, timezone);
      _checkInCount++;
    }
    switch (row.status) {
      case 'PRESENT':
      case 'CHECKED_OUT':
      case 'MANUAL_OVERRIDE':
        presentDays++;
        attendedDays++;
        workSeconds += row.totalDurationSeconds ?? 0;
        visits += row.visitCount;
      case 'WFH':
        wfh++;
      case 'LEAVE':
        leave++;
      case 'HOLIDAY':
        holiday++;
      case 'ABSENT':
        absent++;
    }
  }
}

class _TimeStat extends StatelessWidget {
  const _TimeStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: AppText.numeral.copyWith(fontSize: 20)),
        const SizedBox(height: 2),
        Text(label, style: AppText.bodySm.copyWith(fontSize: 12)),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppText.bodySm.copyWith(
            fontSize: 12.5,
            color: selected ? AppColors.onInk : AppColors.ink2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
