import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/app_config.dart';

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

/// Human-readable duration, e.g. `8h 30m`.
String formatDuration(int? totalSeconds) {
  if (totalSeconds == null || totalSeconds <= 0) return '—';
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
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
