export type UserRole = "employee" | "admin";

export type AttendanceStatus =
  | "PRESENT"
  | "CHECKED_OUT"
  | "WFH"
  | "HOLIDAY"
  | "LEAVE"
  | "ABSENT"
  | "MANUAL_OVERRIDE";

export type AttendanceSource = "automatic" | "manual";

export type GeofenceEventType = "ENTER" | "EXIT";

export interface AppSettings {
  company_timezone: string;
  workday_start: string;
  workday_end: string;
  exit_grace_seconds: number;
  event_retention_days: number;
}

export interface Location {
  id: string;
  name: string;
  address: string | null;
  timezone: string | null;
  active: boolean;
}

export interface User {
  id: string;
  employee_id: string;
  name: string;
  email: string;
  role: UserRole;
  department: string | null;
  location_id: string | null;
  status: "active" | "inactive";
  created_at: string;
}

export interface Geofence {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  radius_meters: number;
  location_id: string | null;
  active: boolean;
}

export interface Attendance {
  id: string;
  user_id: string;
  date: string;
  status: AttendanceStatus;
  check_in_at: string | null;
  check_out_at: string | null;
  total_duration_seconds: number | null;
  work_summary: string | null;
  source: AttendanceSource;
  created_at: string;
  updated_at: string;
}

export interface LocationEvent {
  id: string;
  user_id: string;
  geofence_id: string | null;
  event_type: GeofenceEventType;
  occurred_at: string;
  received_at: string;
  accuracy_meters: number | null;
  source: string;
  dedupe_key: string;
  processed: boolean;
  metadata: Record<string, unknown>;
}

export interface Holiday {
  id: string;
  name: string;
  date: string;
  location_id: string | null;
  created_by: string | null;
}

export interface WfhAssignment {
  id: string;
  user_id: string;
  date: string;
  reason: string | null;
  created_by: string | null;
}

export interface AttendanceCorrection {
  id: string;
  attendance_id: string;
  admin_id: string;
  old_value: Record<string, unknown>;
  new_value: Record<string, unknown>;
  reason: string;
  created_at: string;
}

export interface AuditLog {
  id: string;
  actor_id: string | null;
  action: string;
  entity_type: string;
  entity_id: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
}

export interface LocationEventInput {
  geofence_id: string;
  event_type: GeofenceEventType;
  occurred_at: string;
  accuracy_meters?: number | null;
  dedupe_key?: string | null;
  metadata?: Record<string, unknown>;
}

export interface AttendanceEventResult {
  attendance_id: string | null;
  status: AttendanceStatus | null;
  check_in_at: string | null;
  check_out_at: string | null;
  business_date: string;
  duplicate: boolean;
}
