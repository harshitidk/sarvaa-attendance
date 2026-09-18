import { useCallback, useEffect, useState } from "react";
import { ScrollView, StyleSheet, Text, TouchableOpacity, View } from "react-native";
import { format } from "date-fns";
import { useAuth } from "@/providers/auth";
import { fetchRecentEvents } from "@/lib/api";
import { getPermissionState, requestPermissions, stopGeofencing, type PermissionState } from "@/lib/geofencing";
import { colors, radius, spacing } from "@/theme";

const PERMISSION_COPY: Record<PermissionState, string> = {
  granted: "Location permission granted — background detection is enabled.",
  "foreground-only": "Only while using the app. Allow 'Always' for automatic background detection.",
  denied: "Location permission denied. Attendance cannot be recorded automatically.",
  "services-disabled": "Location services are turned off in device settings.",
};

export default function SettingsScreen() {
  const { profile, signOut } = useAuth();
  const [permission, setPermission] = useState<PermissionState>("denied");
  const [events, setEvents] = useState<
    { id: string; event_type: string; occurred_at: string; accuracy_meters: number | null }[]
  >([]);

  const load = useCallback(async () => {
    setPermission(await getPermissionState());
    if (profile) setEvents((await fetchRecentEvents(profile.id)) as typeof events);
  }, [profile]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Account</Text>
        <Row label="Name" value={profile?.name ?? "—"} />
        <Row label="Employee ID" value={profile?.employee_id ?? "—"} />
        <Row label="Email" value={profile?.email ?? "—"} />
        <Row label="Department" value={profile?.department ?? "—"} />
      </View>

      <View style={styles.card}>
        <Text style={styles.cardTitle}>Location permission</Text>
        <Text style={styles.hint}>{PERMISSION_COPY[permission]}</Text>
        {permission !== "granted" ? (
          <TouchableOpacity
            style={styles.button}
            onPress={async () => {
              setPermission(await requestPermissions());
            }}
          >
            <Text style={styles.buttonText}>Review permission</Text>
          </TouchableOpacity>
        ) : null}
      </View>

      <View style={styles.card}>
        <Text style={styles.cardTitle}>Recent location events</Text>
        <Text style={styles.hint}>
          Only geofence transitions are logged. Continuous location is never collected.
        </Text>
        {events.length === 0 ? (
          <Text style={[styles.hint, { marginTop: spacing.md }]}>No events recorded yet.</Text>
        ) : (
          events.map((event) => (
            <View key={event.id} style={styles.eventRow}>
              <Text style={styles.eventType}>{event.event_type}</Text>
              <Text style={styles.eventMeta}>
                {format(new Date(event.occurred_at), "d MMM h:mm a")}
                {event.accuracy_meters ? ` · ±${Math.round(event.accuracy_meters)}m` : ""}
              </Text>
            </View>
          ))
        )}
      </View>

      <TouchableOpacity
        style={[styles.button, styles.dangerButton]}
        onPress={async () => {
          await stopGeofencing();
          await signOut();
        }}
      >
        <Text style={styles.buttonText}>Sign out</Text>
      </TouchableOpacity>
    </ScrollView>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={styles.rowValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, gap: spacing.lg },
  card: {
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
  },
  cardTitle: { fontSize: 15, fontWeight: "600", color: colors.foreground, marginBottom: spacing.sm },
  hint: { fontSize: 13, color: colors.muted, lineHeight: 18 },
  row: { flexDirection: "row", justifyContent: "space-between", paddingVertical: spacing.sm },
  rowLabel: { color: colors.muted, fontSize: 14 },
  rowValue: { color: colors.foreground, fontSize: 14, fontWeight: "500", flexShrink: 1, textAlign: "right" },
  button: {
    marginTop: spacing.lg,
    minHeight: 44,
    justifyContent: "center",
    backgroundColor: colors.primary,
    borderRadius: radius.sm,
    paddingVertical: spacing.md,
    alignItems: "center",
  },
  dangerButton: { backgroundColor: colors.danger },
  buttonText: { color: colors.primaryForeground, fontWeight: "600" },
  eventRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    borderTopWidth: 1,
    borderTopColor: colors.border,
    paddingVertical: spacing.sm,
  },
  eventType: { fontSize: 13, fontWeight: "600", color: colors.foreground },
  eventMeta: { fontSize: 12, color: colors.muted },
});

export { RouteErrorBoundary as ErrorBoundary } from "@/components/route-error";
