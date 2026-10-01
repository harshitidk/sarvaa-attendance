import 'package:flutter_test/flutter_test.dart';
import 'package:geoattend/models/models.dart';
import 'package:geoattend/utils/attendance_logic.dart';

void main() {
  setUpAll(initializeTimezones);

  group('distanceMeters', () {
    test('is zero for identical points', () {
      expect(distanceMeters(28.6304, 77.2177, 28.6304, 77.2177), 0);
    });

    test('matches a known short distance (~150m)', () {
      final distance = distanceMeters(28.6304, 77.2177, 28.6317, 77.2177);
      expect(distance, closeTo(145, 15));
    });

    test('is symmetric', () {
      final a = distanceMeters(12.9352, 77.6245, 28.6304, 77.2177);
      final b = distanceMeters(28.6304, 77.2177, 12.9352, 77.6245);
      expect(a, closeTo(b, 0.001));
    });
  });

  group('isInsideGeofence', () {
    test('true inside the radius', () {
      expect(
        isInsideGeofence(
          latitude: 28.6304,
          longitude: 77.2177,
          fenceLatitude: 28.6304,
          fenceLongitude: 77.2177,
          radiusMeters: 150,
        ),
        isTrue,
      );
    });

    test('false outside the radius', () {
      expect(
        isInsideGeofence(
          latitude: 28.6317,
          longitude: 77.2177,
          fenceLatitude: 28.6304,
          fenceLongitude: 77.2177,
          radiusMeters: 100,
        ),
        isFalse,
      );
    });
  });

  group('businessDate', () {
    test('uses the company timezone, not UTC', () {
      final instant = DateTime.utc(2026, 1, 1, 20, 0);
      expect(businessDate(instant, 'Asia/Kolkata'), '2026-01-02');
      expect(businessDate(instant, 'UTC'), '2026-01-01');
    });

    test('falls back to the default timezone for unknown names', () {
      final instant = DateTime.utc(2026, 6, 10, 12, 0);
      expect(businessDate(instant, 'Not/AZone'), '2026-06-10');
    });
  });

  group('formatDuration', () {
    test('renders hours and padded minutes', () {
      expect(formatDuration(8 * 3600), '8h 00m');
      expect(formatDuration(8 * 3600 + 30 * 60), '8h 30m');
    });

    test('renders an em dash for null or non-positive values', () {
      expect(formatDuration(null), '—');
      expect(formatDuration(0), '—');
      expect(formatDuration(-5), '—');
    });
  });

  group('durationSeconds', () {
    test('computes a positive difference', () {
      final start = DateTime.utc(2026, 6, 10, 9, 0);
      final end = DateTime.utc(2026, 6, 10, 17, 30);
      expect(durationSeconds(start, end), 8 * 3600 + 1800);
    });

    test('clamps negative differences to zero', () {
      final start = DateTime.utc(2026, 6, 10, 17, 0);
      final end = DateTime.utc(2026, 6, 10, 9, 0);
      expect(durationSeconds(start, end), 0);
    });
  });

  group('formatTime', () {
    test('renders 12-hour AM/PM in the company timezone', () {
      final instant = DateTime.utc(2026, 6, 10, 3, 35); // 09:05 IST
      expect(formatTime(instant, 'Asia/Kolkata'), '9:05 AM');
    });

    test('renders an em dash for null', () {
      expect(formatTime(null, 'Asia/Kolkata'), '—');
    });
  });

  group('statusLabel', () {
    test('maps known statuses and falls back', () {
      expect(statusLabel('CHECKED_OUT'), 'Checked out');
      expect(statusLabel('WFH'), 'Work from home');
      expect(statusLabel(null), 'Not checked in');
    });
  });

  group('work summary edit window', () {
    final now = DateTime.utc(2026, 6, 10, 12, 0);

    test('nothing to edit before a summary exists', () {
      expect(canEditSummary(null, now), isFalse);
      expect(summaryEditRemaining(null, now), Duration.zero);
    });

    test('open inside the window, closed after the grace', () {
      expect(canEditSummary(now.subtract(const Duration(minutes: 5)), now), isTrue);
      expect(canEditSummary(now.subtract(const Duration(minutes: 39)), now), isTrue);
      expect(canEditSummary(now.subtract(const Duration(minutes: 41)), now), isFalse);
    });

    test('remaining time counts down from the hard lock', () {
      final remaining =
          summaryEditRemaining(now.subtract(const Duration(minutes: 5)), now);
      expect(remaining, const Duration(minutes: 35));
      expect(
        summaryEditRemaining(now.subtract(const Duration(minutes: 50)), now),
        Duration.zero,
      );
    });
  });

  group('quarterBounds', () {
    test('maps months to calendar quarters', () {
      expect(quarterBounds(DateTime(2026, 2, 15)).label, 'Q1 2026');
      expect(quarterBounds(DateTime(2026, 2, 15)).from, '2026-01-01');
      expect(quarterBounds(DateTime(2026, 2, 15)).to, '2026-03-31');
      expect(quarterBounds(DateTime(2026, 11, 5)).label, 'Q4 2026');
      expect(quarterBounds(DateTime(2026, 11, 5)).from, '2026-10-01');
      expect(quarterBounds(DateTime(2026, 11, 5)).to, '2026-12-31');
    });
  });

  group('QuarterSummary', () {
    Attendance record(String status, {int? seconds}) => Attendance(
          id: 'a',
          userId: 'u',
          date: '2026-06-10',
          status: status,
          source: 'automatic',
          totalDurationSeconds: seconds,
        );

    test('counts each status and sums work hours', () {
      final summary = QuarterSummary.fromRecords([
        record('PRESENT', seconds: 8 * 3600),
        record('CHECKED_OUT', seconds: 7 * 3600 + 1800),
        record('WFH', seconds: 6 * 3600),
        record('LEAVE'),
        record('LEAVE'),
        record('ABSENT'),
        record('HOLIDAY'),
      ]);
      expect(summary.present, 2);
      expect(summary.wfh, 1);
      expect(summary.leaves, 2);
      expect(summary.absent, 1);
      expect(summary.holidays, 1);
      expect(summary.workHours, 21);
    });

    test('an empty quarter is all zeroes', () {
      final summary = QuarterSummary.fromRecords(const []);
      expect(summary.leaves, 0);
      expect(summary.workHours, 0);
    });
  });

  group('LeaveType', () {
    test('round-trips its stored values', () {
      expect(LeaveType.fromValue('sick'), LeaveType.sick);
      expect(LeaveType.fromValue('paid'), LeaveType.paid);
      expect(LeaveType.fromValue('unpaid'), LeaveType.unpaid);
      expect(LeaveType.fromValue('nonsense'), LeaveType.sick);
      expect(LeaveType.fromValue(null), LeaveType.sick);
    });
  });
}
