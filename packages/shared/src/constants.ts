import type {
  AttendanceStatus,
  AttendanceSource,
  GeofenceEventType,
  UserRole,
} from "./types";

export const ATTENDANCE_STATUSES: AttendanceStatus[] = [
  "PRESENT",
  "CHECKED_OUT",
  "WFH",
  "HOLIDAY",
  "LEAVE",
  "ABSENT",
  "MANUAL_OVERRIDE",
];

export const USER_ROLES: UserRole[] = ["employee", "admin"];

export const GEOFENCE_EVENT_TYPES: GeofenceEventType[] = ["ENTER", "EXIT"];

export const ATTENDANCE_SOURCES: AttendanceSource[] = ["automatic", "manual"];

export const STATUS_LABELS: Record<AttendanceStatus, string> = {
  PRESENT: "Present",
  CHECKED_OUT: "Checked out",
  WFH: "Work from home",
  HOLIDAY: "Holiday",
  LEAVE: "Leave",
  ABSENT: "Absent",
  MANUAL_OVERRIDE: "Manual override",
};

/** Recommended exception priority (PRD §11). */
export const EXCEPTION_PRIORITY: AttendanceStatus[] = [
  "HOLIDAY",
  "LEAVE",
  "WFH",
  "PRESENT",
  "ABSENT",
];

/** Prototype geofence radius range (PRD §8). Validate at the real workplace. */
export const GEOFENCE_RADIUS_MIN_METERS = 25;
export const GEOFENCE_RADIUS_MAX_METERS = 5000;
export const GEOFENCE_RADIUS_DEFAULT_METERS = 150;

export const DEFAULT_SETTINGS = {
  company_timezone: "Asia/Kolkata",
  workday_start: "09:00",
  workday_end: "18:00",
  absence_cutoff: "12:00",
  exit_grace_seconds: 300,
  event_retention_days: 180,
} as const;

/** Statuses that count as a present/working day in summaries. */
export const PRESENT_STATUSES: AttendanceStatus[] = [
  "PRESENT",
  "CHECKED_OUT",
  "MANUAL_OVERRIDE",
];

export const STATUS_TONE: Record<AttendanceStatus, "positive" | "neutral" | "info" | "warning"> = {
  PRESENT: "positive",
  CHECKED_OUT: "positive",
  WFH: "info",
  HOLIDAY: "neutral",
  LEAVE: "neutral",
  ABSENT: "warning",
  MANUAL_OVERRIDE: "info",
};
