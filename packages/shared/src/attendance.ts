import type {
  AppSettings,
  Attendance,
  AttendanceStatus,
  Geofence,
  LocationEventInput,
} from "./types";
import { DEFAULT_SETTINGS } from "./constants";

const EARTH_RADIUS_METERS = 6_371_000;

/** Great-circle distance in meters between two coordinates. */
export function distanceMeters(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** True when a coordinate lies inside a circular geofence. */
export function isInsideGeofence(
  point: { latitude: number; longitude: number },
  geofence: Pick<Geofence, "latitude" | "longitude" | "radius_meters">,
): boolean {
  return (
    distanceMeters(point.latitude, point.longitude, geofence.latitude, geofence.longitude) <=
    geofence.radius_meters
  );
}

/**
 * Local business date (YYYY-MM-DD) for an instant in the company timezone.
 * Business dates always use the company's configured timezone (PRD §7).
 */
export function businessDate(instant: Date | string, timezone: string): string {
  const date = typeof instant === "string" ? new Date(instant) : instant;
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

export function durationSeconds(checkIn: string, checkOut: string): number {
  return Math.max(0, Math.round((new Date(checkOut).getTime() - new Date(checkIn).getTime()) / 1000));
}

export function formatDuration(totalSeconds: number | null | undefined): string {
  if (totalSeconds == null || totalSeconds <= 0) return "—";
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  return `${hours}h ${minutes.toString().padStart(2, "0")}m`;
}

export interface AttendanceEngineInput {
  current: Attendance | null;
  event: Pick<LocationEventInput, "event_type" | "occurred_at">;
  settings?: Pick<AppSettings, "exit_grace_seconds">;
  exception?: "HOLIDAY" | "WFH" | "LEAVE" | null;
}

export interface AttendanceEngineOutput {
  status: AttendanceStatus;
  check_in_at: string | null;
  check_out_at: string | null;
  total_duration_seconds: number | null;
  changed: boolean;
}

/**
 * Pure mirror of the server-side attendance state machine. Useful for previews,
 * optimistic UI and tests. The database function remains authoritative.
 *
 * Rules:
 *  - first valid ENTER establishes check-in; later ENTERs never overwrite it
 *  - a confirmed EXIT may establish checkout
 *  - a re-entry within the exit grace window cancels a drift-induced checkout
 *  - manual (admin-corrected) records are never mutated automatically
 */
export function applyEvent(input: AttendanceEngineInput): AttendanceEngineOutput {
  const { current, event, exception = null } = input;
  const grace = input.settings?.exit_grace_seconds ?? DEFAULT_SETTINGS.exit_grace_seconds;

  if (exception) {
    return {
      status: exception,
      check_in_at: current?.check_in_at ?? null,
      check_out_at: current?.check_out_at ?? null,
      total_duration_seconds: current?.total_duration_seconds ?? null,
      changed: current?.status !== exception,
    };
  }

  if (current?.source === "manual") {
    return {
      status: current.status,
      check_in_at: current.check_in_at,
      check_out_at: current.check_out_at,
      total_duration_seconds: current.total_duration_seconds,
      changed: false,
    };
  }

  if (event.event_type === "ENTER") {
    if (!current) {
      return {
        status: "PRESENT",
        check_in_at: event.occurred_at,
        check_out_at: null,
        total_duration_seconds: null,
        changed: true,
      };
    }
    if (current.check_out_at) {
      const sinceExit =
        (new Date(event.occurred_at).getTime() - new Date(current.check_out_at).getTime()) / 1000;
      if (sinceExit <= grace) {
        return {
          status: "PRESENT",
          check_in_at: current.check_in_at,
          check_out_at: null,
          total_duration_seconds: null,
          changed: true,
        };
      }
    }
    if (!current.check_in_at) {
      return {
        status: "PRESENT",
        check_in_at: event.occurred_at,
        check_out_at: current.check_out_at,
        total_duration_seconds: current.total_duration_seconds,
        changed: true,
      };
    }
    return {
      status: current.status,
      check_in_at: current.check_in_at,
      check_out_at: current.check_out_at,
      total_duration_seconds: current.total_duration_seconds,
      changed: false,
    };
  }

  // EXIT
  if (!current?.check_in_at) {
    return {
      status: current?.status ?? "PRESENT",
      check_in_at: current?.check_in_at ?? null,
      check_out_at: current?.check_out_at ?? null,
      total_duration_seconds: current?.total_duration_seconds ?? null,
      changed: false,
    };
  }
  if (!current.check_out_at || new Date(event.occurred_at) > new Date(current.check_out_at)) {
    return {
      status: "CHECKED_OUT",
      check_in_at: current.check_in_at,
      check_out_at: event.occurred_at,
      total_duration_seconds: durationSeconds(current.check_in_at, event.occurred_at),
      changed: true,
    };
  }
  return {
    status: current.status,
    check_in_at: current.check_in_at,
    check_out_at: current.check_out_at,
    total_duration_seconds: current.total_duration_seconds,
    changed: false,
  };
}

/**
 * Whether an event should create/modify attendance given an existing state.
 * Duplicate/replayed events are idempotent (PRD §7, §21).
 */
export function isDuplicateEvent(existingDedupeKeys: string[], event: LocationEventInput): boolean {
  if (!event.dedupe_key) return false;
  return existingDedupeKeys.includes(event.dedupe_key);
}

/** Absence is only assigned after the configured cutoff (PRD §22). */
export function shouldMarkAbsent(
  now: Date,
  settings: Pick<AppSettings, "company_timezone" | "absence_cutoff">,
): boolean {
  const local = new Intl.DateTimeFormat("en-GB", {
    timeZone: settings.company_timezone,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(now);
  return local >= settings.absence_cutoff;
}
