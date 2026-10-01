import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../utils/attendance_logic.dart';
import '../../widgets/common.dart';

const _correctableStatuses = [
  'PRESENT',
  'CHECKED_OUT',
  'WFH',
  'HOLIDAY',
  'LEAVE',
  'ABSENT',
  'MANUAL_OVERRIDE',
];

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  late DateTime _to = DateTime.now();
  final _search = TextEditingController();
  List<AttendanceRow> _rows = const [];
  String _timezone = 'Asia/Kolkata';
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
        _error = error.toString();
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
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
    await _load();
  }

  List<AttendanceRow> get _visible {
    if (_query.trim().isEmpty) return _rows;
    final needle = _query.trim().toLowerCase();
    return _rows
        .where((row) =>
            row.employeeName.toLowerCase().contains(needle) ||
            row.employeeCode.toLowerCase().contains(needle) ||
            (row.department ?? '').toLowerCase().contains(needle))
        .toList();
  }

  Future<void> _correct(AttendanceRow row) async {
    final applied = await showAppSheet<bool>(
      context,
      builder: (context) => _CorrectionSheet(api: widget.api, row: row),
    );
    if (applied == true) {
      await _load();
      if (mounted) showToast(context, 'Correction applied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;

    return Column(
      children: [
        Padding(
          padding: AppPadding.bar,
          child: Column(
            children: [
              DateRangeBar(from: _from, to: _to, onPick: _pick),
              const SizedBox(height: Insets.md),
              SearchField(
                controller: _search,
                hintText: 'Search name, ID or department',
                onChanged: (value) => setState(() => _query = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: ScreenState(
            loading: _loading,
            error: _error,
            onRetry: _load,
            child: rows.isEmpty
                ? EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: _query.isEmpty
                        ? 'No records in this range'
                        : 'No match for "$_query"',
                    message: _query.isEmpty
                        ? 'Widen the date range to see more.'
                        : 'Try a different name, employee ID or department.',
                  )
                : Refreshable(
                    onRefresh: _load,
                    child: ListView.separated(
                    padding: AppPadding.pageBelowBar,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Insets.sm),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return _AttendanceCard(
                        row: row,
                        timezone: _timezone,
                        onTap: () => _correct(row),
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

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({
    required this.row,
    required this.timezone,
    required this.onTap,
  });

  final AttendanceRow row;
  final String timezone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: const EdgeInsets.all(Insets.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.employeeName.isEmpty ? row.userId : row.employeeName,
                        style: AppText.subhead,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatBusinessDate(row.date, 'EEE, d MMM'),
                        style: AppText.bodySm.copyWith(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.md),
                StatusBadge(status: row.status, compact: true),
              ],
            ),
            const SizedBox(height: Insets.md),
            Row(
              children: [
                Text(
                  '${formatTime(row.checkInAt, timezone)}'
                  '  –  ${formatTime(row.checkOutAt, timezone)}',
                  style: AppText.numeral.copyWith(fontSize: 13.5),
                ),
                const Spacer(),
                Text(
                  formatDuration(row.totalDurationSeconds),
                  style: AppText.bodySm.copyWith(fontSize: 12.5),
                ),
              ],
            ),
            if (row.visitCount > 1) ...[
              const SizedBox(height: Insets.sm),
              Text(
                '${row.visitCount} visits · ${row.sessions.map((s) => '${formatTime(s.checkInAt, timezone)}–${formatTime(s.checkOutAt, timezone)}').join(', ')}',
                style: AppText.bodySm.copyWith(fontSize: 12),
              ),
            ],
            if (row.workSummary != null && row.workSummary!.trim().isNotEmpty) ...[
              const SizedBox(height: Insets.md),
              Text(
                row.workSummary!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySm.copyWith(fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Manual correction. The reason is mandatory — it is what the audit log keeps.
class _CorrectionSheet extends StatefulWidget {
  const _CorrectionSheet({required this.api, required this.row});

  final AdminApi api;
  final AttendanceRow row;

  @override
  State<_CorrectionSheet> createState() => _CorrectionSheetState();
}

class _CorrectionSheetState extends State<_CorrectionSheet> {
  final _reason = TextEditingController();
  late String _status = widget.row.status;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final reason = _reason.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'Give a reason — it is recorded in the audit log.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.applyManualCorrection(
        attendanceId: widget.row.id,
        status: _status,
        reason: reason,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: widget.row.employeeName.isEmpty
          ? 'Correct record'
          : 'Correct ${widget.row.employeeName}',
      subtitle: formatBusinessDate(widget.row.date, 'EEEE, d MMMM y'),
      primaryLabel: 'Apply correction',
      onPrimary: _save,
      busy: _busy,
      children: [
        const FieldLabel('Status'),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final status in _correctableStatuses)
              ChoiceChip(
                label: Text(statusLabel(status)),
                selected: _status == status,
                onSelected: _busy ? null : (_) => setState(() => _status = status),
              ),
          ],
        ),
        const SizedBox(height: Insets.xl),
        const FieldLabel('Reason', hint: 'Stored with the old and new values.'),
        TextField(
          controller: _reason,
          enabled: !_busy,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: const InputDecoration(
            hintText: 'Device GPS failed; confirmed with the team lead.',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Insets.md),
          Notice(_error!, tone: NoticeTone.alert),
        ],
      ],
    );
  }
}
