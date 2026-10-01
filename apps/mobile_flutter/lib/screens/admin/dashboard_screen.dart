import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../utils/attendance_logic.dart';
import '../../widgets/common.dart';

/// Green marks someone who is on site. The rest of the app is deliberately
/// monochrome, so this single accent reads as "here" at a glance.
const Color _presentGreen = Color(0xFF16A34A);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<AttendanceRow> _rows = const [];
  List<EmployeeRow> _employees = const [];
  String _timezone = 'Asia/Kolkata';
  bool _loading = true;
  String? _error;

  static const _office = {'PRESENT', 'CHECKED_OUT', 'MANUAL_OVERRIDE'};

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
      final settings = await widget.api.fetchSettings();
      final date = businessDate(DateTime.now().toUtc(), settings.companyTimezone);
      final results = await Future.wait([
        widget.api.fetchAttendanceForDate(date),
        widget.api.fetchEmployees(),
      ]);
      if (!mounted) return;
      setState(() {
        _timezone = settings.companyTimezone;
        _rows = results[0] as List<AttendanceRow>;
        _employees = results[1] as List<EmployeeRow>;
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

  /// Everyone whose attendance is tracked: all employees, plus any admin who
  /// opted in.
  List<EmployeeRow> get _active => _employees
      .where((e) => e.attendanceEnabled && e.status == 'active')
      .toList();

  AttendanceRow? _recordFor(String userId) {
    for (final row in _rows) {
      if (row.userId == userId) return row;
    }
    return null;
  }

  bool _isPresent(AttendanceRow? row) =>
      row != null && _office.contains(row.status) && row.checkInAt != null;

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final present = active.where((e) => _isPresent(_recordFor(e.id))).toList();
    final notPresent = active.where((e) => !_isPresent(_recordFor(e.id))).toList();

    return ScreenState(
      loading: _loading,
      error: _error,
      onRetry: _load,
      child: Refreshable(
        onRefresh: _load,
        child: ListView(
          padding: AppPadding.page,
          children: [
            ScreenCaption(DateFormat('EEEE, d MMMM y').format(DateTime.now())),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'In office',
                    value: '${present.length} / ${active.length}',
                    emphasis: true,
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: StatTile(
                    label: 'Not in yet',
                    value: '${notPresent.length}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.xl),
            if (active.isEmpty)
              const SectionCard(
                title: 'Team',
                child: EmptyState(
                  icon: Icons.people_outline,
                  title: 'No active employees',
                  message: 'Add employees to see who is in the office today.',
                ),
              )
            else ...[
              SectionCard(
                title: 'In office · ${present.length}',
                trailing: present.isEmpty
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _PresentDot(),
                          const SizedBox(width: 6),
                          Text('On site', style: AppText.bodySm.copyWith(fontSize: 12)),
                        ],
                      ),
                child: present.isEmpty
                    ? const EmptyState(
                        icon: Icons.meeting_room_outlined,
                        title: 'Nobody has checked in yet',
                        message: 'Check-ins appear here the moment they happen.',
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < present.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: AppColors.hairline),
                            _PresentRow(
                              name: present[i].name,
                              code: present[i].employeeId,
                              checkInAt: _recordFor(present[i].id)?.checkInAt,
                              timezone: _timezone,
                              visitCount: _recordFor(present[i].id)?.visitCount ?? 0,
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: Insets.lg),
              SectionCard(
                title: 'Not in yet · ${notPresent.length}',
                child: notPresent.isEmpty
                    ? const EmptyState(
                        icon: Icons.done_all_rounded,
                        title: 'Everyone is in',
                        message: 'All active employees have checked in today.',
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < notPresent.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: AppColors.hairline),
                            AppRow(
                              title: notPresent[i].name,
                              subtitle: notPresent[i].employeeId,
                              trailing: _notPresentTrailing(
                                _recordFor(notPresent[i].id),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _notPresentTrailing(AttendanceRow? row) {
    if (row == null) {
      return Text('Not checked in', style: AppText.bodySm.copyWith(fontSize: 12));
    }
    if (row.status == 'WFH' || row.status == 'LEAVE' || row.status == 'HOLIDAY') {
      return StatusBadge(status: row.status, compact: true);
    }
    if (row.status == 'ABSENT') {
      return StatusBadge(status: row.status, compact: true);
    }
    return Text('Not checked in', style: AppText.bodySm.copyWith(fontSize: 12));
  }
}

class _PresentRow extends StatelessWidget {
  const _PresentRow({
    required this.name,
    required this.code,
    required this.checkInAt,
    required this.timezone,
    required this.visitCount,
  });

  final String name;
  final String code;
  final DateTime? checkInAt;
  final String timezone;
  final int visitCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.md),
      child: Row(
        children: [
          const _PresentDot(),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppText.subhead.copyWith(color: _presentGreen),
                ),
                const SizedBox(height: 2),
                Text(
                  code.isEmpty
                      ? 'Checked in'
                      : '$code${visitCount > 1 ? ' · $visitCount visits' : ''}',
                  style: AppText.bodySm.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            'In ${formatTime(checkInAt, timezone)}',
            style: AppText.numeral.copyWith(fontSize: 13.5, color: _presentGreen),
          ),
        ],
      ),
    );
  }
}

class _PresentDot extends StatelessWidget {
  const _PresentDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      width: 10,
      decoration: const BoxDecoration(
        color: _presentGreen,
        shape: BoxShape.circle,
      ),
    );
  }
}
