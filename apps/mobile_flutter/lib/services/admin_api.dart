import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_models.dart';
import '../models/models.dart';

/// Admin-only data access. RLS grants admins read/write across the company.
class AdminApi {
  AdminApi(this._client);

  final SupabaseClient _client;

  // ---------------------------------------------------------------- dashboard
  Future<List<AttendanceRow>> fetchAttendanceForDate(String date) async {
    final rows = await _client
        .from('attendance')
        .select('*, user:users(name, employee_id, department), sessions:attendance_sessions(*)')
        .eq('date', date)
        .order('created_at');
    return (rows as List)
        .map((row) => AttendanceRow.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  // --------------------------------------------------------------- attendance
  Future<List<AttendanceRow>> fetchAttendanceRange(String from, String to) async {
    final rows = await _client
        .from('attendance')
        .select('*, user:users(name, employee_id, department), sessions:attendance_sessions(*)')
        .gte('date', from)
        .lte('date', to)
        .order('date', ascending: false);
    return (rows as List)
        .map((row) => AttendanceRow.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// One employee's attendance across a range, newest first, for their profile.
  Future<List<AttendanceRow>> fetchEmployeeAttendance(
    String userId,
    String from,
    String to,
  ) async {
    final rows = await _client
        .from('attendance')
        .select('*, user:users(name, employee_id, department), sessions:attendance_sessions(*)')
        .eq('user_id', userId)
        .gte('date', from)
        .lte('date', to)
        .order('date', ascending: false);
    return (rows as List)
        .map((row) => AttendanceRow.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> applyManualCorrection({
    required String attendanceId,
    String? status,
    DateTime? checkInAt,
    DateTime? checkOutAt,
    required String reason,
  }) async {
    await _client.rpc('apply_manual_correction', params: {
      'p_attendance_id': attendanceId,
      'p_new_status': status,
      'p_check_in_at': checkInAt?.toUtc().toIso8601String(),
      'p_check_out_at': checkOutAt?.toUtc().toIso8601String(),
      'p_reason': reason,
    });
  }

  // ---------------------------------------------------------------- employees
  Future<List<EmployeeRow>> fetchEmployees() async {
    final rows = await _client.from('users').select().order('name');
    return (rows as List)
        .map((row) => EmployeeRow.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateEmployee(
    String id, {
    String? role,
    String? status,
    String? locationId,
    String? department,
    String? name,
    bool? attendanceEnabled,
  }) async {
    final patch = <String, dynamic>{};
    if (role != null) patch['role'] = role;
    if (status != null) patch['status'] = status;
    if (locationId != null) patch['location_id'] = locationId;
    if (department != null) patch['department'] = department;
    if (name != null) patch['name'] = name;
    if (attendanceEnabled != null) patch['attendance_enabled'] = attendanceEnabled;
    if (patch.isEmpty) return;
    await _client.from('users').update(patch).eq('id', id);
  }

  Future<List<Map<String, dynamic>>> fetchLocations() async {
    final rows = await _client.from('locations').select('id, name').order('name');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------- geofences
  Future<List<Geofence>> fetchGeofences() async {
    final rows = await _client.from('geofences').select().order('name');
    return (rows as List)
        .map((row) => Geofence.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveGeofence({
    String? id,
    required String name,
    required double latitude,
    required double longitude,
    required int radiusMeters,
    String? locationId,
    required bool active,
  }) async {
    final payload = {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'location_id': locationId,
      'active': active,
    };
    if (id == null) {
      await _client.from('geofences').insert(payload);
    } else {
      await _client.from('geofences').update(payload).eq('id', id);
    }
  }

  Future<void> setGeofenceActive(String id, bool active) async {
    await _client.from('geofences').update({'active': active}).eq('id', id);
  }

  Future<void> deleteGeofence(String id) async {
    await _client.from('geofences').delete().eq('id', id);
  }

  // --------------------------------------------------------- holidays and WFH
  Future<List<Holiday>> fetchHolidays() async {
    final rows = await _client.from('holidays').select().order('date', ascending: false);
    return (rows as List)
        .map((row) => Holiday.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> createHoliday({
    required String name,
    required String date,
    String? locationId,
  }) async {
    await _client.from('holidays').insert({
      'name': name,
      'date': date,
      'location_id': locationId,
    });
  }

  Future<void> deleteHoliday(String id) async {
    await _client.from('holidays').delete().eq('id', id);
  }

  Future<List<WfhRow>> fetchWfh() async {
    final rows = await _client
        .from('wfh_assignments')
        .select('*, user:users!wfh_assignments_user_id_fkey(name)')
        .order('date', ascending: false);
    return (rows as List)
        .map((row) => WfhRow.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> createWfh({
    required String userId,
    required String date,
    String? reason,
  }) async {
    await _client.from('wfh_assignments').insert({
      'user_id': userId,
      'date': date,
      'reason': reason,
    });
  }

  Future<void> deleteWfh(String id) async {
    await _client.from('wfh_assignments').delete().eq('id', id);
  }

  // ------------------------------------------------------------ wfh requests
  /// Requests awaiting a decision first, then recently decided ones.
  Future<List<WfhRequestRow>> fetchWfhRequests({bool pendingOnly = false}) async {
    var query = _client
        .from('wfh_requests')
        .select('*, user:users!wfh_requests_user_id_fkey(name, employee_id)');
    if (pendingOnly) query = query.eq('status', 'pending');
    final rows = await query.order('date', ascending: false).limit(200);
    return (rows as List)
        .map((row) => WfhRequestRow.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Approving materialises the WFH day the attendance engine reads;
  /// rejecting leaves nothing behind. Both are written to the audit log.
  Future<void> reviewWfhRequest({
    required String requestId,
    required bool approve,
    String? note,
  }) async {
    await _client.rpc('review_wfh_request', params: {
      'p_request_id': requestId,
      'p_approve': approve,
      'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
    });
  }

  // ---------------------------------------------------------- leave requests
  /// Requests awaiting a decision first, then recently decided ones.
  Future<List<LeaveRequestRow>> fetchLeaveRequests({bool pendingOnly = false}) async {
    var query = _client
        .from('leave_requests')
        .select('*, user:users!leave_requests_user_id_fkey(name, employee_id)');
    if (pendingOnly) query = query.eq('status', 'pending');
    final rows = await query.order('date', ascending: false).limit(200);
    return (rows as List)
        .map((row) => LeaveRequestRow.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Approving writes the LEAVE attendance day the absence finalizer reads;
  /// rejecting leaves nothing behind. Both are written to the audit log.
  Future<void> reviewLeaveRequest({
    required String requestId,
    required bool approve,
    String? note,
  }) async {
    await _client.rpc('review_leave_request', params: {
      'p_request_id': requestId,
      'p_approve': approve,
      'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
    });
  }

  // -------------------------------------------------------- company wfh days
  Future<List<CompanyWfhDay>> fetchCompanyWfhDays() async {
    final rows = await _client
        .from('company_wfh_days')
        .select()
        .order('date', ascending: false);
    return (rows as List)
        .map((row) => CompanyWfhDay.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Marks a date as work-from-home for the whole active roster, so nobody
  /// needs to check in.
  Future<void> setCompanyWfhDay({
    required String date,
    String? note,
    String? locationId,
  }) async {
    await _client.rpc('set_company_wfh_day', params: {
      'p_date': date,
      'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      'p_location_id': locationId,
    });
  }

  /// Removes the day and only the assignments it created.
  Future<void> clearCompanyWfhDay(String dayId) async {
    await _client.rpc('clear_company_wfh_day', params: {'p_day_id': dayId});
  }

  // -------------------------------------------------------------- corrections
  Future<List<CorrectionRow>> fetchCorrections() async {
    final rows = await _client
        .from('attendance_corrections')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((row) => CorrectionRow.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  // -------------------------------------------------------------------- audit
  Future<List<AuditRow>> fetchAuditLogs() async {
    final rows = await _client
        .from('audit_logs')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((row) => AuditRow.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  // ----------------------------------------------------------------- settings
  Future<AppSettings> fetchSettings() async {
    final data = await _client.from('app_settings').select().eq('id', 1).maybeSingle();
    return AppSettings.fromMap(data ?? const <String, dynamic>{});
  }

  /// Returns false when the update was blocked or affected no rows (e.g. RLS).
  Future<bool> updateSettings({
    required String companyTimezone,
    required String workdayStart,
    required String workdayEnd,
    required int exitGraceSeconds,
    required int eventRetentionDays,
    required List<int> workingDays,
  }) async {
    final result = await _client.from('app_settings').update({
      'company_timezone': companyTimezone,
      'workday_start': workdayStart,
      'workday_end': workdayEnd,
      'exit_grace_seconds': exitGraceSeconds,
      'event_retention_days': eventRetentionDays,
      'working_days': workingDays,
    }).eq('id', 1).select();
    return (result as List).isNotEmpty;
  }
}
