import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../utils/attendance_logic.dart';

/// Thin wrapper over the Supabase client for the attendance backend.
class Api {
  Api(this._client);

  final SupabaseClient _client;

  Future<AppSettings> fetchAppSettings() async {
    final data = await _client.from('app_settings').select().eq('id', 1).maybeSingle();
    return AppSettings.fromMap(data ?? const <String, dynamic>{});
  }

  Future<UserProfile?> fetchProfile(String userId) async {
    final data = await _client.from('users').select().eq('id', userId).maybeSingle();
    return data == null ? null : UserProfile.fromMap(data);
  }

  /// RLS returns only the geofences this employee is authorized to use.
  Future<List<Geofence>> fetchAssignedGeofences() async {
    final rows = await _client.from('geofences').select().eq('active', true).order('name');
    return (rows as List)
        .map((row) => Geofence.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<Attendance?> fetchAttendanceForDate(String userId, String date) async {
    final data = await _client
        .from('attendance')
        .select()
        .eq('user_id', userId)
        .eq('date', date)
        .maybeSingle();
    return data == null ? null : Attendance.fromMap(data);
  }

  Future<Attendance?> fetchTodayAttendance(String userId, String timezone) {
    return fetchAttendanceForDate(userId, businessDate(DateTime.now().toUtc(), timezone));
  }

  Future<List<Attendance>> fetchMonthAttendance(String userId, int year, int month) async {
    final padded = month.toString().padLeft(2, '0');
    final from = '$year-$padded-01';
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    final to = '$year-$padded-${lastDay.toString().padLeft(2, '0')}';
    final rows = await _client
        .from('attendance')
        .select()
        .eq('user_id', userId)
        .gte('date', from)
        .lte('date', to)
        .order('date');
    return (rows as List)
        .map((row) => Attendance.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<LocationEvent>> fetchRecentEvents(String userId, {int limit = 20}) async {
    final rows = await _client
        .from('location_events')
        .select('id, event_type, occurred_at, accuracy_meters')
        .eq('user_id', userId)
        .order('occurred_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((row) => LocationEvent.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> recordLocationEvent({
    required String geofenceId,
    required String eventType,
    required DateTime occurredAt,
    double? accuracyMeters,
    String? dedupeKey,
    String source = 'Mobile geolocation',
    Map<String, dynamic>? metadata,
  }) async {
    final iso = occurredAt.toUtc().toIso8601String();
    final key = dedupeKey ??
        'mobile:$geofenceId:$eventType:${occurredAt.toUtc().millisecondsSinceEpoch ~/ 60000}';
    await _client.rpc('record_location_event', params: {
      'p_geofence_id': geofenceId,
      'p_event_type': eventType,
      'p_occurred_at': iso,
      'p_accuracy_meters': accuracyMeters,
      'p_dedupe_key': key,
      'p_source': source,
      'p_metadata': metadata ?? const {'platform': 'flutter'},
    });
  }

  Future<Attendance> employeeCheckOut({
    required String attendanceId,
    required String summary,
    DateTime? occurredAt,
    double? accuracyMeters,
    String? geofenceId,
  }) async {
    final data = await _client.rpc('employee_check_out', params: {
      'p_attendance_id': attendanceId,
      'p_summary': summary,
      'p_occurred_at': (occurredAt ?? DateTime.now()).toUtc().toIso8601String(),
      'p_accuracy_meters': accuracyMeters,
      'p_geofence_id': geofenceId,
    });
    final map = (data is List ? data.first : data) as Map<String, dynamic>;
    return Attendance.fromMap(map);
  }
}
