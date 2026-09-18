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
  });

  final String id;
  final String employeeId;
  final String name;
  final String email;
  final String role;
  final String? department;
  final String? locationId;
  final String status;

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
        id: map['id'] as String,
        employeeId: (map['employee_id'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        email: (map['email'] as String?) ?? '',
        role: (map['role'] as String?) ?? 'employee',
        department: map['department'] as String?,
        locationId: map['location_id'] as String?,
        status: (map['status'] as String?) ?? 'active',
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

  bool get isCheckedIn => checkInAt != null;
  bool get isCheckedOut => checkOutAt != null;

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
      );

  Attendance copyWith({
    String? status,
    DateTime? checkInAt,
    DateTime? checkOutAt,
    int? totalDurationSeconds,
    String? workSummary,
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
    );
  }
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
    this.absenceCutoff = '12:00',
    this.exitGraceSeconds = 300,
    this.eventRetentionDays = 180,
    this.workingDays = const [1, 2, 3, 4, 5, 6],
  });

  final String companyTimezone;
  final String workdayStart;
  final String workdayEnd;
  final String absenceCutoff;
  final int exitGraceSeconds;
  final int eventRetentionDays;

  /// ISO weekday numbers that count as working days (1=Mon .. 7=Sun).
  final List<int> workingDays;

  factory AppSettings.fromMap(Map<String, dynamic> map) => AppSettings(
        companyTimezone: (map['company_timezone'] as String?) ?? 'Asia/Kolkata',
        workdayStart: (map['workday_start'] as String?) ?? '09:00',
        workdayEnd: (map['workday_end'] as String?) ?? '18:00',
        absenceCutoff: (map['absence_cutoff'] as String?) ?? '12:00',
        exitGraceSeconds: (map['exit_grace_seconds'] as num?)?.toInt() ?? 300,
        eventRetentionDays: (map['event_retention_days'] as num?)?.toInt() ?? 180,
        workingDays: ((map['working_days'] as List?) ?? const [1, 2, 3, 4, 5, 6])
            .map((value) => (value as num).toInt())
            .toList(),
      );
}

class LocationEvent {
  const LocationEvent({
    required this.id,
    required this.eventType,
    required this.occurredAt,
    this.accuracyMeters,
  });

  final String id;
  final String eventType;
  final DateTime occurredAt;
  final double? accuracyMeters;

  factory LocationEvent.fromMap(Map<String, dynamic> map) => LocationEvent(
        id: map['id'] as String,
        eventType: (map['event_type'] as String?) ?? 'ENTER',
        occurredAt: _parseDate(map['occurred_at']) ?? DateTime.now(),
        accuracyMeters: (map['accuracy_meters'] as num?)?.toDouble(),
      );
}
