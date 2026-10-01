import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../utils/attendance_logic.dart';
import 'common.dart';

/// A month of attendance as a compact grid.
///
/// One implementation, shared by Today and History, so the two views cannot
/// drift apart. Tapping a day with a record hands it back via [onSelect].
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.records,
    required this.timezone,
    this.onSelect,
    this.compact = false,
  });

  /// Any date inside the month to draw.
  final DateTime month;
  final List<Attendance> records;
  final String timezone;
  final ValueChanged<Attendance>? onSelect;

  /// Slightly tighter cells, for the Today screen's preview.
  final bool compact;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final byDate = {for (final record in records) record.date: record};
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final startOffset = (first.weekday - DateTime.monday) % 7;
    final today = businessDate(DateTime.now().toUtc(), timezone);
    final cells = <int?>[
      ...List<int?>.filled(startOffset, null),
      ...List<int?>.generate(daysInMonth, (index) => index + 1),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final day in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: AppText.eyebrow.copyWith(
                        fontSize: 10.5,
                        color: AppColors.faint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: compact ? 1.3 : 1,
            children: cells.map((day) {
              if (day == null) return const SizedBox.shrink();
              final key = '${month.year}-'
                  '${month.month.toString().padLeft(2, '0')}-'
                  '${day.toString().padLeft(2, '0')}';
              final record = byDate[key];
              return CalendarDayCell(
                day: day,
                record: record,
                isToday: key == today,
                compact: compact,
                onTap: record == null || onSelect == null
                    ? null
                    : () => onSelect!(record),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// One square in the month grid. A recorded day shows a status dot; the live
/// "present" day inverts to ink.
class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    super.key,
    required this.day,
    required this.record,
    required this.isToday,
    required this.onTap,
    this.compact = false,
  });

  final int day;
  final Attendance? record;
  final bool isToday;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tone = toneFor(record?.status);
    final filled = record != null && tone.emphasis;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        decoration: BoxDecoration(
          color: filled ? AppColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: isToday ? AppColors.ink : Colors.transparent,
            width: isToday ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: AppText.numeral.copyWith(
                fontSize: compact ? 12 : 13,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                color: filled
                    ? AppColors.onInk
                    : record == null
                        ? AppColors.faint
                        : AppColors.ink,
              ),
            ),
            SizedBox(height: compact ? 1 : 3),
            SizedBox(
              height: compact ? 5 : 6,
              child: record == null || filled
                  ? null
                  : StatusDot(status: record!.status, size: compact ? 4 : 5),
            ),
          ],
        ),
      ),
    );
  }
}
