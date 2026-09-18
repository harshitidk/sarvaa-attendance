import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../utils/attendance_logic.dart';
import '../../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<AttendanceRow> _rows = const [];
  String _timezone = 'Asia/Kolkata';
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
      final settings = await widget.api.fetchSettings();
      final date = businessDate(DateTime.now().toUtc(), settings.companyTimezone);
      final rows = await widget.api.fetchAttendanceForDate(date);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    int count(String status) => _rows.where((row) => row.status == status).length;
    final present = count('PRESENT') + count('CHECKED_OUT') + count('MANUAL_OVERRIDE');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _stat('Present', present, AppColors.positive),
              _stat('WFH', count('WFH'), AppColors.info),
              _stat('Holiday', count('HOLIDAY'), AppColors.neutral),
              _stat('Absent', count('ABSENT'), AppColors.warning),
              _stat('Records', _rows.length, AppColors.foreground),
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Today (${businessDate(DateTime.now().toUtc(), _timezone)})',
            child: _rows.isEmpty
                ? const Text('No attendance records yet.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13))
                : Column(
                    children: _rows
                        .map((row) => _row(row))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text('$value',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _row(AttendanceRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.employeeName.isEmpty ? row.userId : row.employeeName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${formatTime(row.checkInAt, _timezone)} → ${formatTime(row.checkOutAt, _timezone)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          StatusBadge(status: row.status),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
