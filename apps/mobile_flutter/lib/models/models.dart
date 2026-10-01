DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.email,
    required this.role,
    this.department,
    this.locationId,
    this.status = 'active',
    this.attendanceEnabled = false,
  });

  final String id;
  final String employeeId;
  final String name;
  final String email;
  final String role;
  final String? department;
  final String? locationId;
  final String status;

  /// Whether this user tracks their own attendance. Always true for employees;
  /// admins opt in from Settings.
  final bool attendanceEnabled;

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
        id: map['id'] as String,
        employeeId: (map['employee_id'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        email: (map['email'] as String?) ?? '',
        role: (map['role'] as String?) ?? 'employee',
        department: map['department'] as String?,
        locationId: map['location_id'] as String?,
        status: (map['status'] as String?) ?? 'active',
        attendanceEnabled: (map['attendance_enabled'] as bool?) ?? false,
      );
}

class Attendance {
  const Attendance({
    required this.id,
    required this.userId,
    required this.date,
    required this.status,
    required this.source,
    this.checkInAt,
    this.checkOutAt,
    this.totalDurationSeconds,
    this.workSummary,
    this.workSummaryAt,
    this.sessions = const [],
  });

  final String id;
  final String userId;
  final String date;
  final String status;
  final String source;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final int? totalDurationSeconds;
  final String? workSummary;

  /// When the summary was first stored. Starts the edit window; an edit never
  /// moves it.
  final DateTime? workSummaryAt;

  /// Every office visit recorded that day, oldest first.
  final List<AttendanceSession> sessions;

  bool get isCheckedIn => checkInAt != null;
  bool get isCheckedOut => checkOutAt != null;

  int get visitCount => sessions.length;

  factory Attendance.fromMap(Map<String, dynamic> map) => Attendance(
        id: map['id'] as String,
        userId: (map['user_id'] as String?) ?? '',
        date: (map['date'] as String?) ?? '',
        status: (map['status'] as String?) ?? 'PRESENT',
        source: (map['source'] as String?) ?? 'automatic',
        checkInAt: _parseDate(map['check_in_at']),
        checkOutAt: _parseDate(map['check_out_at']),
        totalDurationSeconds: (map['total_duration_seconds'] as num?)?.toInt(),
        workSummary: map['work_summary'] as String?,
        workSummaryAt: _parseDate(map['work_summary_at']),
        sessions: ((map['sessions'] as List?) ?? const [])
            .map((row) => AttendanceSession.fromMap(row as Map<String, dynamic>))
            .toList(),
      );

  Attendance copyWith({
    String? status,
    DateTime? checkInAt,
    DateTime? checkOutAt,
    int? totalDurationSeconds,
    String? workSummary,
    DateTime? workSummaryAt,
    List<AttendanceSession>? sessions,
    bool clearCheckOut = false,
  }) {
    return Attendance(
      id: id,
      userId: userId,
      date: date,
      status: status ?? this.status,
      source: source,
      checkInAt: checkInAt ?? this.checkInAt,
      checkOutAt: clearCheckOut ? null : (checkOutAt ?? this.checkOutAt),
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      workSummary: workSummary ?? this.workSummary,
      workSummaryAt: workSummaryAt ?? this.workSummaryAt,
      sessions: sessions ?? this.sessions,
    );
  }
}

/// One continuous visit to the office: a check-in and its check-out.
class AttendanceSession {
  const AttendanceSession({
    required this.id,
    required this.checkInAt,
    this.checkOutAt,
    this.durationSeconds,
    this.closedBy,
    this.summary,
  });

  final String id;
  final DateTime checkInAt;
  final DateTime? checkOutAt;
  final int? durationSeconds;

  /// `manual` (employee checked out) or `auto` (safety-net on leaving).
  final String? closedBy;
  final String? summary;

  bool get isOpen => checkOutAt == null;

  factory AttendanceSession.fromMap(Map<String, dynamic> map) => AttendanceSession(
        id: (map['id'] as String?) ?? '',
        checkInAt: _parseDate(map['check_in_at']) ?? DateTime.now(),
        checkOutAt: _parseDate(map['check_out_at']),
        durationSeconds: (map['duration_seconds'] as num?)?.toInt(),
        closedBy: map['closed_by'] as String?,
        summary: map['summary'] as String?,
      );
}

class Geofence {
  const Geofence({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.active,
    this.locationId,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final bool active;
  final String? locationId;

  factory Geofence.fromMap(Map<String, dynamic> map) => Geofence(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? 'Geofence',
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        radiusMeters: (map['radius_meters'] as num).toInt(),
        active: (map['active'] as bool?) ?? true,
        locationId: map['location_id'] as String?,
      );
}

class AppSettings {
  const AppSettings({
    this.companyTimezone = 'Asia/Kolkata',
    this.workdayStart = '09:00',
    this.workdayEnd = '18:00',
    this.exitGraceSeconds = 300,
    this.eventRetentionDays = 180,
    this.workingDays = const [1, 2, 3, 4, 5, 6],
  });

  final String companyTimezone;
  final String workdayStart;
  final String workdayEnd;
  final int exitGraceSeconds;
  final int eventRetentionDays;

  /// ISO weekday numbers that count as working days (1=Mon .. 7=Sun).
  final List<int> workingDays;

  factory AppSettings.fromMap(Map<String, dynamic> map) => AppSettings(
        companyTimezone: (map['company_timezone'] as String?) ?? 'Asia/Kolkata',
        workdayStart: (map['workday_start'] as String?) ?? '09:00',
        workdayEnd: (map['workday_end'] as String?) ?? '18:00',
        exitGraceSeconds: (map['exit_grace_seconds'] as num?)?.toInt() ?? 300,
        eventRetentionDays: (map['event_retention_days'] as num?)?.toInt() ?? 180,
        workingDays: ((map['working_days'] as List?) ?? const [1, 2, 3, 4, 5, 6])
            .map((value) => (value as num).toInt())
            .toList(),
      );
}

/// An employee's own request to work from home on a given day.
///
/// A request is only a request: the day is not WFH until an admin approves it,
/// at which point the backend materialises the actual assignment.
class WfhRequest {
  const WfhRequest({
    required this.id,
    required this.date,
    required this.status,
    this.reason,
    this.decisionNote,
    this.reviewedAt,
  });

  final String id;
  final String date;

  /// `pending`, `approved`, `rejected` or `cancelled`.
  final String status;
  final String? reason;
  final String? decisionNote;
  final DateTime? reviewedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  String get statusLabel => switch (status) {
        'pending' => 'Awaiting approval',
        'approved' => 'Approved',
        'rejected' => 'Declined',
        'cancelled' => 'Withdrawn',
        _ => status,
      };

  factory WfhRequest.fromMap(Map<String, dynamic> map) => WfhRequest(
        id: map['id'] as String,
        date: (map['date'] as String?) ?? '',
        status: (map['status'] as String?) ?? 'pending',
        reason: map['reason'] as String?,
        decisionNote: map['decision_note'] as String?,
        reviewedAt: _parseDate(map['reviewed_at']),
      );
}

/// The kinds of leave an employee can ask for.
enum LeaveType {
  sick('sick', 'Sick leave'),
  paid('paid', 'Paid leave'),
  unpaid('unpaid', 'Unpaid leave');

  const LeaveType(this.value, this.label);

  /// Value stored in `leave_requests.leave_type`.
  final String value;
  final String label;

  static LeaveType fromValue(String? value) => LeaveType.values.firstWhere(
        (type) => type.value == value,
        orElse: () => LeaveType.sick,
      );
}

/// An employee's own request for a day off.
///
/// A request is only a request: the day becomes LEAVE only when an admin
/// approves it, at which point the backend writes the attendance row.
class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.date,
    required this.leaveType,
    required this.status,
    this.reason,
    this.decisionNote,
    this.reviewedAt,
  });

  final String id;
  final String date;
  final LeaveType leaveType;

  /// `pending`, `approved`, `rejected` or `cancelled`.
  final String status;
  final String? reason;
  final String? decisionNote;
  final DateTime? reviewedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  String get statusLabel => switch (status) {
        'pending' => 'Awaiting approval',
        'approved' => 'Approved',
        'rejected' => 'Declined',
        'cancelled' => 'Withdrawn',
        _ => status,
      };

  factory LeaveRequest.fromMap(Map<String, dynamic> map) => LeaveRequest(
        id: map['id'] as String,
        date: (map['date'] as String?) ?? '',
        leaveType: LeaveType.fromValue(map['leave_type'] as String?),
        status: (map['status'] as String?) ?? 'pending',
        reason: map['reason'] as String?,
        decisionNote: map['decision_note'] as String?,
        reviewedAt: _parseDate(map['reviewed_at']),
      );
}
