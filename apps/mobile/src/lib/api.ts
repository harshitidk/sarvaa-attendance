import type { Attendance, Geofence, Holiday, WfhAssignment } from "@geo/shared";
import { businessDate } from "@geo/shared";
import { supabase } from "./supabase";

export async function fetchAppTimezone(): Promise<string> {
  const { data } = await supabase.from("app_settings").select("company_timezone").eq("id", 1).single();
  return data?.company_timezone ?? "Asia/Kolkata";
}

/** RLS returns only the geofences this employee is authorized to use. */
export async function fetchAssignedGeofences(): Promise<Geofence[]> {
  const { data, error } = await supabase
    .from("geofences")
    .select("*")
    .eq("active", true)
    .order("name");
  if (error) throw error;
  return (data ?? []) as Geofence[];
}

export async function fetchAttendanceForDate(userId: string, date: string): Promise<Attendance | null> {
  const { data } = await supabase
    .from("attendance")
    .select("*")
    .eq("user_id", userId)
    .eq("date", date)
    .maybeSingle();
  return (data as Attendance) ?? null;
}

export async function fetchTodayAttendance(userId: string, timezone: string): Promise<Attendance | null> {
  return fetchAttendanceForDate(userId, businessDate(new Date(), timezone));
}

export async function fetchMonthAttendance(
  userId: string,
  year: number,
  month: number,
): Promise<Attendance[]> {
  const from = `${year}-${String(month).padStart(2, "0")}-01`;
  const to = new Date(Date.UTC(year, month, 0)).toISOString().slice(0, 10);
  const { data, error } = await supabase
    .from("attendance")
    .select("*")
    .eq("user_id", userId)
    .gte("date", from)
    .lte("date", to)
    .order("date");
  if (error) throw error;
  return (data ?? []) as Attendance[];
}

export async function fetchHolidays(): Promise<Holiday[]> {
  const { data } = await supabase.from("holidays").select("*").order("date");
  return (data ?? []) as Holiday[];
}

export async function fetchWfhForMonth(
  userId: string,
  year: number,
  month: number,
): Promise<WfhAssignment[]> {
  const from = `${year}-${String(month).padStart(2, "0")}-01`;
  const to = new Date(Date.UTC(year, month, 0)).toISOString().slice(0, 10);
  const { data } = await supabase
    .from("wfh_assignments")
    .select("*")
    .eq("user_id", userId)
    .gte("date", from)
    .lte("date", to);
  return (data ?? []) as WfhAssignment[];
}

export async function recordLocationEvent(params: {
  geofenceId: string;
  eventType: "ENTER" | "EXIT";
  occurredAt?: string;
  accuracyMeters?: number | null;
  latitude?: number | null;
  longitude?: number | null;
  dedupeKey?: string;
  source?: string;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  const occurredAt = params.occurredAt ?? new Date().toISOString();
  const { error } = await supabase.rpc("record_location_event", {
    p_geofence_id: params.geofenceId,
    p_event_type: params.eventType,
    p_occurred_at: occurredAt,
    p_accuracy_meters: params.accuracyMeters ?? null,
    p_latitude: params.latitude ?? null,
    p_longitude: params.longitude ?? null,
    p_dedupe_key: params.dedupeKey ?? `mobile:${params.geofenceId}:${params.eventType}:${occurredAt}`,
    p_source: params.source ?? "Mobile geolocation",
    p_metadata: params.metadata ?? {},
  });
  if (error) throw error;
}

export async function employeeCheckOut(params: {
  attendanceId: string;
  summary: string;
  occurredAt?: string;
  accuracyMeters?: number | null;
  geofenceId?: string | null;
}): Promise<Attendance> {
  const { data, error } = await supabase.rpc("employee_check_out", {
    p_attendance_id: params.attendanceId,
    p_summary: params.summary,
    p_occurred_at: params.occurredAt ?? new Date().toISOString(),
    p_accuracy_meters: params.accuracyMeters ?? null,
    p_geofence_id: params.geofenceId ?? null,
  });
  if (error) throw error;
  return (Array.isArray(data) ? data[0] : data) as Attendance;
}

/** Latest raw transitions, for the "location permission / diagnostics" view. */
export async function fetchRecentEvents(userId: string, limit = 20) {
  const { data } = await supabase
    .from("location_events")
    .select("id, event_type, occurred_at, received_at, accuracy_meters, geofence_id")
    .eq("user_id", userId)
    .order("occurred_at", { ascending: false })
    .limit(limit);
  return data ?? [];
}
