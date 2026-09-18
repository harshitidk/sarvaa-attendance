DateTime? _date(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

/// Attendance joined with the employee's profile, for admin views.
class AttendanceRow {
  const AttendanceRow({
    required this.id,
    required this.userId,
    required this.date,
    required this.status,
    required this.source,
    this.employeeName = '',
    this.employeeCode = '',
    this.department,
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
  final String employeeName;
  final String employeeCode;
  final String? department;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final int? totalDurationSeconds;
  final String? workSummary;

  factory AttendanceRow.fromMap(Map<String, dynamic> map) {
    final user = (map['user'] as Map<String, dynamic>?) ?? const {};
    return AttendanceRow(
      id: map['id'] as String,
      userId: (map['user_id'] as String?) ?? '',
      date: (map['date'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'PRESENT',
      source: (map['source'] as String?) ?? 'automatic',
      employeeName: (user['name'] as String?) ?? '',
      employeeCode: (user['employee_id'] as String?) ?? '',
      department: user['department'] as String?,
      checkInAt: _date(map['check_in_at']),
      checkOutAt: _date(map['check_out_at']),
      totalDurationSeconds: (map['total_duration_seconds'] as num?)?.toInt(),
      workSummary: map['work_summary'] as String?,
    );
  }
}

class EmployeeRow {
  const EmployeeRow({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.department,
    this.locationId,
  });

  final String id;
  final String employeeId;
  final String name;
  final String email;
  final String role;
  final String status;
  final String? department;
  final String? locationId;

  factory EmployeeRow.fromMap(Map<String, dynamic> map) => EmployeeRow(
        id: map['id'] as String,
        employeeId: (map['employee_id'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        email: (map['email'] as String?) ?? '',
        role: (map['role'] as String?) ?? 'employee',
        status: (map['status'] as String?) ?? 'active',
        department: map['department'] as String?,
        locationId: map['location_id'] as String?,
      );
}

class Holiday {
  const Holiday({required this.id, required this.name, required this.date, this.locationId});

  final String id;
  final String name;
  final String date;
  final String? locationId;

  factory Holiday.fromMap(Map<String, dynamic> map) => Holiday(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? '',
        date: (map['date'] as String?) ?? '',
        locationId: map['location_id'] as String?,
      );
}

class WfhRow {
  const WfhRow({
    required this.id,
    required this.userId,
    required this.date,
    this.reason,
    this.employeeName = '',
  });

  final String id;
  final String userId;
  final String date;
  final String? reason;
  final String employeeName;

  factory WfhRow.fromMap(Map<String, dynamic> map) {
    final user = (map['user'] as Map<String, dynamic>?) ?? const {};
    return WfhRow(
      id: map['id'] as String,
      userId: (map['user_id'] as String?) ?? '',
      date: (map['date'] as String?) ?? '',
      reason: map['reason'] as String?,
      employeeName: (user['name'] as String?) ?? '',
    );
  }
}

class CorrectionRow {
  const CorrectionRow({
    required this.id,
    required this.attendanceId,
    required this.reason,
    required this.createdAt,
    this.oldValue = const {},
    this.newValue = const {},
  });

  final String id;
  final String attendanceId;
  final String reason;
  final DateTime createdAt;
  final Map<String, dynamic> oldValue;
  final Map<String, dynamic> newValue;

  factory CorrectionRow.fromMap(Map<String, dynamic> map) => CorrectionRow(
        id: map['id'] as String,
        attendanceId: (map['attendance_id'] as String?) ?? '',
        reason: (map['reason'] as String?) ?? '',
        createdAt: _date(map['created_at']) ?? DateTime.now(),
        oldValue: (map['old_value'] as Map<String, dynamic>?) ?? const {},
        newValue: (map['new_value'] as Map<String, dynamic>?) ?? const {},
      );
}

class AuditRow {
  const AuditRow({
    required this.id,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.entityId,
  });

  final String id;
  final String action;
  final String entityType;
  final DateTime createdAt;
  final String? entityId;

  factory AuditRow.fromMap(Map<String, dynamic> map) => AuditRow(
        id: map['id'] as String,
        action: (map['action'] as String?) ?? '',
        entityType: (map['entity_type'] as String?) ?? '',
        createdAt: _date(map['created_at']) ?? DateTime.now(),
        entityId: map['entity_id'] as String?,
      );
}
