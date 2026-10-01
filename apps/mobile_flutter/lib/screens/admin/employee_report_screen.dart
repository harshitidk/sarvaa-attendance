import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../models/models.dart';
import '../../services/admin_api.dart';
import '../../utils/attendance_logic.dart';
import '../../widgets/common.dart';

/// Full attendance picture for one employee over a date range, opened from the
/// Reports list.
class EmployeeReportScreen extends StatefulWidget {
  const EmployeeReportScreen({
    super.key,
    required this.api,
    required this.userId,
    required this.name,
    required this.code,
    required this.from,
    required this.to,
    required this.timezone,
  });

  final AdminApi api;
  final String userId;
  final String name;
  final String code;
  final DateTime from;
  final DateTime to;
  final String timezone;

  @override
  State<EmployeeReportScreen> createState() => _EmployeeReportScreenState();
}

class _EmployeeReportScreenState extends State<EmployeeReportScreen> {
  List<AttendanceRow> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchEmployeeAttendance(
        widget.userId,
        isoDate(widget.from),
        isoDate(widget.to),
      );
      if (!mounted) return;
      setState(() {
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

  int _count(Set<String> statuses) =>
      _rows.where((r) => statuses.contains(r.status)).length;

  @override
  Widget build(BuildContext context) {
    final office = officeTime(_rows.map(_asAttendance));
    final avgCheckIn = averageCheckInTime(_rows.map(_asAttendance), widget.timezone);
    final visits = _rows.fold<int>(0, (sum, r) => sum + r.visitCount);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name.isEmpty ? widget.code : widget.name),
        shape: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      body: ScreenState(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: Refreshable(
          onRefresh: _load,
          child: ListView(
            padding: AppPadding.page,
            children: [
              ScreenCaption(
                '${formatBusinessDate(isoDate(widget.from), 'd MMM y')} – '
                '${formatBusinessDate(isoDate(widget.to), 'd MMM y')}'
                '${widget.code.isEmpty ? '' : ' · ${widget.code}'}',
              ),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Time in office',
                      value: formatDuration(office.workSeconds),
                      emphasis: true,
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: StatTile(
                      label: 'Avg / attended day',
                      value: office.attendedDays == 0
                          ? '—'
                          : formatDuration(office.workSeconds ~/ office.attendedDays),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.md),
              Row(
                children: [
                  Expanded(
                    child: StatTile(label: 'Avg check-in', value: avgCheckIn ?? '—'),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: StatTile(label: 'Office visits', value: '$visits'),
                  ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              SectionCard(
                title: 'Days',
                child: Row(
                  children: [
                    Expanded(
                      child: CountCell(
                        label: 'Present',
                        value: _count({'PRESENT', 'CHECKED_OUT', 'MANUAL_OVERRIDE'}),
                        emphasis: true,
                      ),
                    ),
                    Expanded(child: CountCell(label: 'Home', value: _count({'WFH'}))),
                    Expanded(child: CountCell(label: 'Leave', value: _count({'LEAVE'}))),
                    Expanded(child: CountCell(label: 'Holiday', value: _count({'HOLIDAY'}))),
                    Expanded(child: CountCell(label: 'Absent', value: _count({'ABSENT'}))),
                  ],
                ),
              ),
              const SizedBox(height: Insets.lg),
              if (_rows.isEmpty)
                const SectionCard(
                  title: 'Records',
                  child: EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'No records',
                    message: 'Nothing was recorded for this employee in the range.',
                  ),
                )
              else
                GroupedList(
                  title: '${_rows.length} record${_rows.length == 1 ? '' : 's'}',
                  children: [
                    for (final row in _rows)
                      AppRow(
                        title: formatBusinessDate(row.date, 'EEE, d MMM y'),
                        subtitle: '${formatTime(row.checkInAt, widget.timezone)}'
                            '  –  ${formatTime(row.checkOutAt, widget.timezone)}'
                            '${row.visitCount > 1 ? '  ·  ${row.visitCount} visits' : ''}',
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            StatusBadge(status: row.status, compact: true),
                            const SizedBox(height: 4),
                            Text(
                              formatDuration(row.totalDurationSeconds),
                              style: AppText.bodySm.copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The stats helpers are typed for the employee model; adapt the admin row.
  Attendance _asAttendance(AttendanceRow row) => Attendance(
        id: row.id,
        userId: row.userId,
        date: row.date,
        status: row.status,
        source: row.source,
        checkInAt: row.checkInAt,
        checkOutAt: row.checkOutAt,
        totalDurationSeconds: row.totalDurationSeconds,
        workSummary: row.workSummary,
        sessions: row.sessions,
      );
}
