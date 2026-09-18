import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../state/auth_controller.dart';
import '../utils/attendance_logic.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.api, required this.auth});

  final Api api;
  final AuthController auth;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  DateTime _cursor = DateTime(DateTime.now().year, DateTime.now().month);
  List<Attendance> _records = const [];
  Attendance? _selected;
  String _timezone = 'Asia/Kolkata';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = widget.auth.session?.user.id;
    if (userId == null) return;
    setState(() => _loading = true);
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
  }

  void _shift(int delta) {
    setState(() {
      _selected = null;
      _cursor = DateTime(_cursor.year, _cursor.month + delta);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final byDate = {for (final record in _records) record.date: record};
    final first = DateTime(_cursor.year, _cursor.month, 1);
    final daysInMonth = DateTime(_cursor.year, _cursor.month + 1, 0).day;
    final startOffset = (first.weekday - DateTime.monday) % 7;
    final today = businessDate(DateTime.now().toUtc(), _timezone);
    final cells = <int?>[
      ...List<int?>.filled(startOffset, null),
      ...List<int?>.generate(daysInMonth, (index) => index + 1),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
            Text(
              DateFormat('MMMM yyyy').format(_cursor),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          Row(
            children: _weekdays
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: cells.map((day) {
              if (day == null) return const SizedBox.shrink();
              final key =
                  '${_cursor.year}-${_cursor.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
              final record = byDate[key];
              final tone = toneFor(record?.status);
              final isToday = key == today;
              return GestureDetector(
                onTap: record == null ? null : () => setState(() => _selected = record),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: record == null ? null : tone.background,
                    borderRadius: BorderRadius.circular(8),
                    border: isToday ? Border.all(color: AppColors.primary) : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: record == null ? AppColors.foreground : tone.foreground,
                        ),
                      ),
                      if (record != null)
                        Text(
                          record.status.replaceAll('_', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(fontSize: 7, color: tone.foreground),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (_selected == null)
            const Text(
              'Tap a day to see check-in, check-out and duration.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            )
          else
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_selected!.date, style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 4),
                  StatusBadge(status: _selected!.status),
                  const SizedBox(height: 12),
                  _detail('Check-in', formatTime(_selected!.checkInAt, _timezone)),
                  _detail('Check-out', formatTime(_selected!.checkOutAt, _timezone)),
                  _detail('Duration', formatDuration(_selected!.totalDurationSeconds)),
                  _detail(
                    'Source',
                    _selected!.source == 'manual' ? 'Admin correction' : 'Automatic',
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }
}
