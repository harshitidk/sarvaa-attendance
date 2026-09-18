import 'package:flutter_test/flutter_test.dart';
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
}
