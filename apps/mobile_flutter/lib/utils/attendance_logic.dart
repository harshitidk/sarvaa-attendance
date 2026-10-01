import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/app_config.dart';
import '../models/models.dart';

const double _earthRadiusMeters = 6371000;

/// Initialises the bundled timezone database. Call once at startup.
void initializeTimezones() => tzdata.initializeTimeZones();

tz.Location _location(String timezone) {
  try {
    return tz.getLocation(timezone);
  } catch (_) {
    return tz.getLocation(AppConfig.defaultTimezone);
  }
}

/// Great-circle distance in meters between two coordinates.
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  double toRad(double d) => d * math.pi / 180;
  final dLat = toRad(lat2 - lat1);
  final dLon = toRad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(toRad(lat1)) * math.cos(toRad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(a.toDouble())));
}

/// True when a coordinate lies inside a circular geofence.
bool isInsideGeofence({
  required double latitude,
  required double longitude,
  required double fenceLatitude,
  required double fenceLongitude,
  required num radiusMeters,
}) {
  final distance = distanceMeters(latitude, longitude, fenceLatitude, fenceLongitude);
  return distance <= radiusMeters;
}

/// The result of deciding whether a location reading allows a check-in.
class CheckInDecision {
  const CheckInDecision._({this.fence, this.distance, this.error});

  final Geofence? fence;
  final double? distance;
  final String? error;

  bool get allowed => fence != null && error == null;

  static const noWorkplace =
      'No workplace is assigned to your account yet. Ask an admin to set one up.';
  static const mocked =
      'A mock location was detected. Turn off fake-GPS apps to check in.';
}

/// Maps a location reading to the nearest assigned geofence and decides whether
/// the employee may check in. Pure and side-effect free, so every branch is
/// unit-testable without a device.
CheckInDecision evaluateCheckIn({
  required double latitude,
  required double longitude,
  required List<Geofence> geofences,
  bool isMocked = false,
}) {
  if (isMocked) return const CheckInDecision._(error: CheckInDecision.mocked);
  if (geofences.isEmpty) {
    return const CheckInDecision._(error: CheckInDecision.noWorkplace);
  }

  var best = geofences.first;
  var bestDistance = double.infinity;
  for (final fence in geofences) {
    final distance =
        distanceMeters(latitude, longitude, fence.latitude, fence.longitude);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = fence;
    }
  }

  if (bestDistance > best.radiusMeters) {
    return CheckInDecision._(
      fence: best,
      distance: bestDistance,
      error: 'You are about ${bestDistance.round()} m from ${best.name}. '
          'Move inside the workplace to check in.',
    );
  }
  return CheckInDecision._(fence: best, distance: bestDistance);
}

/// Local business date (YYYY-MM-DD) for an instant in the company timezone.
String businessDate(DateTime instant, String timezone) {
  final local = tz.TZDateTime.from(instant, _location(timezone));
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Renders an instant as 12-hour time (e.g. `9:05 AM`) in the company timezone.
String formatTime(DateTime? instant, String timezone) {
  if (instant == null) return '—';
  final local = tz.TZDateTime.from(instant, _location(timezone));
  return DateFormat('h:mm a').format(local);
}

/// `YYYY-MM-DD` for a local date, the form every table and RPC expects.
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Strips Dart's `Exception: ` prefix so thrown messages read as plain text.
String describeError(Object error) {
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

/// Formats a `YYYY-MM-DD` business date with [pattern].
///
/// Returns the raw value rather than throwing when the string is blank or
/// malformed — these dates come from the database and are rendered inside
/// `build`, where a FormatException would take the screen down.
String formatBusinessDate(String isoDate, String pattern) {
  final parsed = DateTime.tryParse(isoDate);
  return parsed == null ? isoDate : DateFormat(pattern).format(parsed);
}

/// Human-readable duration, e.g. `8h 30m`.
String formatDuration(int? totalSeconds) {
  if (totalSeconds == null || totalSeconds <= 0) return '—';
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

/// Average check-in clock time across [records], in the company timezone.
///
/// Returns null when nothing has a check-in. The mean is taken on the
/// minute-of-day, which is what "average arrival time" means in practice.
String? averageCheckInTime(Iterable<Attendance> records, String timezone) {
  var total = 0;
  var count = 0;
  for (final record in records) {
    final at = record.checkInAt;
    if (at == null) continue;
    total += localMinuteOfDay(at, timezone);
    count++;
  }
  if (count == 0) return null;
  return formatMinuteOfDay((total / count).round());
}

/// Minutes past local midnight for an instant, in the company timezone.
int localMinuteOfDay(DateTime instant, String timezone) {
  final local = tz.TZDateTime.from(instant, _location(timezone));
  return local.hour * 60 + local.minute;
}

/// Renders minutes past midnight as 12-hour time (e.g. `9:05 AM`).
String formatMinuteOfDay(int minutes) {
  final hour24 = ((minutes ~/ 60) % 24 + 24) % 24;
  final minute = ((minutes % 60) + 60) % 60;
  final period = hour24 < 12 ? 'AM' : 'PM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $period';
}

/// Time actually spent in office and the number of days attended, derived
/// from the daily totals (which are the sum of that day's visits).
({int workSeconds, int attendedDays}) officeTime(Iterable<Attendance> records) {
  var seconds = 0;
  var days = 0;
  for (final record in records) {
    if (record.checkInAt == null) continue;
    if (const {'PRESENT', 'CHECKED_OUT', 'MANUAL_OVERRIDE'}.contains(record.status)) {
      days++;
      seconds += record.totalDurationSeconds ?? 0;
    }
  }
  return (workSeconds: seconds, attendedDays: days);
}

int durationSeconds(DateTime checkIn, DateTime checkOut) {
  final diff = checkOut.difference(checkIn).inSeconds;
  return diff < 0 ? 0 : diff;
}

const Map<String, String> statusLabels = {
  'PRESENT': 'Present',
  'CHECKED_OUT': 'Checked out',
  'WFH': 'Work from home',
  'HOLIDAY': 'Holiday',
  'LEAVE': 'Leave',
  'ABSENT': 'Absent',
  'MANUAL_OVERRIDE': 'Manual override',
};

String statusLabel(String? status) => statusLabels[status] ?? 'Not checked in';

// -------------------------------------------------------------- work summary

/// How long the employee is told they may revise a summary after writing it.
const Duration summaryEditWindow = Duration(minutes: 30);

/// The hard cutoff, a small grace past [summaryEditWindow]. Mirrors the
/// server-side check in `employee_check_out`.
const Duration summaryEditGrace = Duration(minutes: 40);

bool canEditSummary(DateTime? workSummaryAt, DateTime now) {
  if (workSummaryAt == null) return false;
  return now.toUtc().difference(workSummaryAt.toUtc()) < summaryEditGrace;
}

Duration summaryEditRemaining(DateTime? workSummaryAt, DateTime now) {
  if (workSummaryAt == null) return Duration.zero;
  final left = summaryEditGrace - now.toUtc().difference(workSummaryAt.toUtc());
  return left.isNegative ? Duration.zero : left;
}

// ------------------------------------------------------------ quarter counts

/// The calendar quarter containing [now], as inclusive ISO date bounds.
({String from, String to, String label}) quarterBounds(DateTime now) {
  final quarter = ((now.month - 1) ~/ 3) + 1;
  final startMonth = (quarter - 1) * 3 + 1;
  final start = DateTime(now.year, startMonth, 1);
  final end = DateTime(now.year, startMonth + 3, 0);
  return (from: isoDate(start), to: isoDate(end), label: 'Q$quarter ${now.year}');
}

/// What one quarter held, derived from the attendance rows inside it.
class QuarterSummary {
  const QuarterSummary({
    required this.leaves,
    required this.present,
    required this.wfh,
    required this.absent,
    required this.holidays,
    required this.workSeconds,
  });

  final int leaves;
  final int present;
  final int wfh;
  final int absent;
  final int holidays;
  final int workSeconds;

  int get workHours => workSeconds ~/ 3600;

  factory QuarterSummary.fromRecords(List<Attendance> records) {
    var leaves = 0;
    var present = 0;
    var wfh = 0;
    var absent = 0;
    var holidays = 0;
    var seconds = 0;
    for (final record in records) {
      switch (record.status) {
        case 'LEAVE':
          leaves++;
        case 'WFH':
          wfh++;
        case 'ABSENT':
          absent++;
        case 'HOLIDAY':
          holidays++;
        case 'PRESENT':
        case 'CHECKED_OUT':
        case 'MANUAL_OVERRIDE':
          present++;
      }
      seconds += record.totalDurationSeconds ?? 0;
    }
    return QuarterSummary(
      leaves: leaves,
      present: present,
      wfh: wfh,
      absent: absent,
      holidays: holidays,
      workSeconds: seconds,
    );
  }
}
