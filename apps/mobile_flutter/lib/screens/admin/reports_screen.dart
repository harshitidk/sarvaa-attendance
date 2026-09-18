import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/admin_api.dart';
import '../../widgets/common.dart';

class _Totals {
  int present = 0;
  int wfh = 0;
  int leave = 0;
  int holiday = 0;
  int absent = 0;
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.api});

  final AdminApi api;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  late DateTime _to = DateTime.now();
  List<AttendanceRow> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchAttendanceRange(_iso(_from), _iso(_to));
      if (!mounted) return;
      setState(() {
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
    await _load();
  }

  Map<String, ({String name, String code, _Totals totals})> _grouped() {
    final map = <String, ({String name, String code, _Totals totals})>{};
    for (final row in _rows) {
      final entry = map.putIfAbsent(
        row.userId,
        () => (name: row.employeeName, code: row.employeeCode, totals: _Totals()),
      );
      switch (row.status) {
        case 'PRESENT':
        case 'CHECKED_OUT':
        case 'MANUAL_OVERRIDE':
          entry.totals.present++;
        case 'WFH':
          entry.totals.wfh++;
        case 'LEAVE':
          entry.totals.leave++;
        case 'HOLIDAY':
          entry.totals.holiday++;
        case 'ABSENT':
          entry.totals.absent++;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped();
    final entries = grouped.entries.toList()
      ..sort((a, b) => a.value.name.compareTo(b.value.name));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isFrom: true),
                  child: Text('From ${_iso(_from)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isFrom: false),
                  child: Text('To ${_iso(_to)}'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : entries.isEmpty
                      ? const Center(
                          child: Text(
                            'No attendance records in this range.',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final entry in entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SectionCard(
                                  title: entry.value.name.isEmpty
                                      ? entry.value.code
                                      : entry.value.name,
                                  child: Wrap(
                                    spacing: 16,
                                    runSpacing: 8,
                                    children: [
                                      _count('Present', entry.value.totals.present,
                                          AppColors.positive),
                                      _count('WFH', entry.value.totals.wfh, AppColors.info),
                                      _count('Leave', entry.value.totals.leave,
                                          AppColors.neutral),
                                      _count('Holiday', entry.value.totals.holiday,
                                          AppColors.neutral),
                                      _count('Absent', entry.value.totals.absent,
                                          AppColors.warning),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
        ),
      ],
    );
  }

  Widget _count(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        Text('$value',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
