import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../utils/attendance_logic.dart';
import '../../widgets/common.dart';

class ExportsScreen extends StatefulWidget {
  const ExportsScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<ExportsScreen> createState() => _ExportsScreenState();
}

class _ExportsScreenState extends State<ExportsScreen> {
  late DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  late DateTime _to = DateTime.now();
  String _timezone = 'Asia/Kolkata';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTimezone();
  }

  /// Exported times must match what the company sees in the app, not a
  /// hard-coded zone.
  Future<void> _loadTimezone() async {
    try {
      final settings = await widget.api.fetchSettings();
      if (mounted) setState(() => _timezone = settings.companyTimezone);
    } catch (_) {
      // Falls back to the default; the export still works.
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
  }

  String _escape(String value) {
    final cleaned = value.replaceAll('\n', ' ').replaceAll('"', '""');
    return cleaned.contains(',') ? '"$cleaned"' : cleaned;
  }

  String _csv(List<AttendanceRow> rows) {
    final buffer = StringBuffer()
      ..writeln('date,employee_id,name,department,status,check_in,check_out,'
          'duration_seconds,work_summary,source');
    for (final row in rows) {
      buffer.writeln([
        row.date,
        _escape(row.employeeCode),
        _escape(row.employeeName),
        _escape(row.department ?? ''),
        row.status,
        _escape(formatTime(row.checkInAt, _timezone)),
        _escape(formatTime(row.checkOutAt, _timezone)),
        row.totalDurationSeconds ?? '',
        _escape(row.workSummary ?? ''),
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
      final rows = await widget.api.fetchAttendanceRange(isoDate(_from), isoDate(_to));
      if (rows.isEmpty) {
        setState(() {
          _error = 'No records in that range. Widen the dates and try again.';
          _busy = false;
        });
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          subject: 'Attendance ${isoDate(_from)} to ${isoDate(_to)}',
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
    final days = _to.difference(_from).inDays + 1;

    return ListView(
      padding: AppPadding.page,
      children: [
        const ScreenCaption('Download attendance as CSV and share it anywhere.'),
        const Eyebrow('Date range'),
        const SizedBox(height: Insets.sm),
        DateRangeBar(from: _from, to: _to, onPick: _pick),
        const SizedBox(height: Insets.lg),
        SectionCard(
          title: 'What you will get',
          child: Column(
            children: [
              DetailRow('Period', '$days day${days == 1 ? '' : 's'}', dense: true),
              DetailRow('Times in', _timezone, dense: true),
              const DetailRow('Format', 'CSV, 10 columns', dense: true),
            ],
          ),
        ),
        const SizedBox(height: Insets.xl),
        BusyButton(
          label: 'Export CSV',
          icon: Icons.ios_share_rounded,
          busy: _busy,
          onPressed: _export,
        ),
        if (_error != null) ...[
          const SizedBox(height: Insets.lg),
          Notice(_error!, tone: NoticeTone.alert),
        ],
      ],
    );
  }
}
