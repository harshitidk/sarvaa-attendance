import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../utils/attendance_logic.dart';

class ExportsScreen extends StatefulWidget {
  const ExportsScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<ExportsScreen> createState() => _ExportsScreenState();
}

class _ExportsScreenState extends State<ExportsScreen> {
  late DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  late DateTime _to = DateTime.now();
  bool _busy = false;
  String? _error;

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _pick({required bool isFrom}) async {
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
  }

  String _csv(List<AttendanceRow> rows) {
    final buffer = StringBuffer()
      ..writeln('date,employee_id,name,department,status,check_in,check_out,duration_seconds,work_summary,source');
    for (final row in rows) {
      buffer.writeln([
        row.date,
        row.employeeCode,
        row.employeeName,
        row.department ?? '',
        row.status,
        formatTime(row.checkInAt, 'Asia/Kolkata'),
        formatTime(row.checkOutAt, 'Asia/Kolkata'),
        row.totalDurationSeconds ?? '',
        (row.workSummary ?? '').replaceAll('\n', ' ').replaceAll(',', ';'),
        row.source,
      ].join(','));
    }
    return buffer.toString();
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchAttendanceRange(_iso(_from), _iso(_to));
      if (rows.isEmpty) {
        setState(() {
          _error = 'No records in that range.';
          _busy = false;
        });
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          subject: 'Attendance ${_iso(_from)} to ${_iso(_to)}',
          text: _csv(rows),
        ),
      );
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Export attendance as CSV. Choose a range, then share the file.',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => _pick(isFrom: true),
          child: Text('From ${_iso(_from)}'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => _pick(isFrom: false),
          child: Text('To ${_iso(_to)}'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _export,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryForeground,
                  ),
                )
              : const Text('Export CSV'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
      ],
    );
  }
}
