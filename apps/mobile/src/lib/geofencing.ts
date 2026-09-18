import * as Location from "expo-location";
import * as TaskManager from "expo-task-manager";
import * as Notifications from "expo-notifications";
import type { Geofence, GeofenceEventType } from "@geo/shared";
import { supabase } from "./supabase";

export const GEOFENCE_TASK = "geoattend-geofence-transitions";

/**
 * OS geofence transitions arrive here, including when the app is backgrounded
 * or the phone is locked. The backend remains authoritative; we only report the
 * transition and reflect the returned attendance state in a local notification.
 *
 * NOTE: the OS does not always provide the original detection timestamp, so
 * `occurred_at` is the delivery time. The server separately records receipt time.
 */
TaskManager.defineTask(GEOFENCE_TASK, async ({ data, error }) => {
  if (error) {
    console.warn("[geofence] task error", error.message);
    return;
  }

  const { eventType, region } = (data ?? {}) as {
    eventType?: Location.GeofencingEventType;
    region?: Location.LocationRegion;
  };
  if (!eventType || !region) return;

  const type: GeofenceEventType =
    eventType === Location.GeofencingEventType.Enter ? "ENTER" : "EXIT";

  const occurredAt = new Date().toISOString();
  const dedupeKey = `${region.identifier}:${type}:${Math.floor(Date.now() / 60000)}`;

  try {
    const { data: result, error: rpcError } = await supabase.rpc("record_location_event", {
      p_geofence_id: region.identifier,
      p_event_type: type,
      p_occurred_at: occurredAt,
      p_accuracy_meters: null,
      p_dedupe_key: dedupeKey,
      p_source: "OS geofence",
      p_metadata: { platform: "expo-location", occurredAtSource: "delivery" },
    });

    if (rpcError) {
      console.warn("[geofence] record failed", rpcError.message);
      return;
    }

    const status = (result as { status?: string }[] | null)?.[0]?.status;
    if (type === "ENTER") {
      await notify("Checked in", status === "WFH" ? "Work-from-home day" : "Presence recorded.");
    } else {
      await notify("Checked out", "Your check-out has been recorded.");
    }
  } catch (e) {
    console.warn("[geofence] unexpected error", e);
  }
});

async function notify(title: string, body: string) {
  try {
    await Notifications.scheduleNotificationAsync({
      content: { title, body },
      trigger: null,
    });
  } catch {
    // notifications are a convenience, never authoritative
  }
}

export type PermissionState =
  | "granted"
  | "foreground-only"
  | "denied"
  | "services-disabled";

export async function requestPermissions(): Promise<PermissionState> {
  const servicesEnabled = await Location.hasServicesEnabledAsync();
  if (!servicesEnabled) return "services-disabled";

  const foreground = await Location.requestForegroundPermissionsAsync();
  if (foreground.status !== "granted") return "denied";

  try {
    const background = await Location.requestBackgroundPermissionsAsync();
    if (background.status !== "granted") return "foreground-only";
  } catch {
    return "foreground-only";
  }

  return "granted";
}

export async function getPermissionState(): Promise<PermissionState> {
  const servicesEnabled = await Location.hasServicesEnabledAsync();
  if (!servicesEnabled) return "services-disabled";
  const foreground = await Location.getForegroundPermissionsAsync();
  if (foreground.status !== "granted") return "denied";
  try {
    const background = await Location.getBackgroundPermissionsAsync();
    return background.status === "granted" ? "granted" : "foreground-only";
  } catch {
    return "foreground-only";
  }
}

/** Register the employee's assigned geofences with the OS. */
export async function syncGeofences(geofences: Pick<Geofence, "id" | "latitude" | "longitude" | "radius_meters">[]) {
  const alreadyStarted = await TaskManager.isTaskRegisteredAsync(GEOFENCE_TASK);
  if (alreadyStarted) {
    await Location.stopGeofencingAsync(GEOFENCE_TASK);
  }
  if (geofences.length === 0) return;

  await Location.startGeofencingAsync(
    GEOFENCE_TASK,
    geofences.map((g) => ({
      identifier: g.id,
      latitude: g.latitude,
      longitude: g.longitude,
      radius: g.radius_meters,
      notifyOnEnter: true,
      notifyOnExit: true,
    })),
  );
}

export async function stopGeofencing() {
  const started = await TaskManager.isTaskRegisteredAsync(GEOFENCE_TASK);
  if (started) await Location.stopGeofencingAsync(GEOFENCE_TASK);
}

export async function isGeofencingActive(): Promise<boolean> {
  return TaskManager.isTaskRegisteredAsync(GEOFENCE_TASK);
}

/** Foreground-only check used to display current presence in the UI. */
export async function getCurrentPosition() {
  return Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
}
