import { useCallback, useEffect, useState } from "react";
import {
  ActivityIndicator,
  Modal,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";
import { format } from "date-fns";
import { useAuth } from "@/providers/auth";
import {
  employeeCheckOut,
  fetchAssignedGeofences,
  fetchAppTimezone,
  fetchMonthAttendance,
  fetchTodayAttendance,
  recordLocationEvent,
} from "@/lib/api";
import {
  getCurrentPosition,
  getPermissionState,
  isGeofencingActive,
  requestPermissions,
  syncGeofences,
  type PermissionState,
} from "@/lib/geofencing";
import {
  businessDate,
  distanceMeters,
  formatDuration,
  STATUS_LABELS,
  type Attendance,
  type Geofence,
} from "@geo/shared";
import { colors, radius, spacing, statusColor } from "@/theme";

interface Summary {
  present: number;
  wfh: number;
  holiday: number;
  absent: number;
}

export default function HomeScreen() {
  const { profile } = useAuth();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [timezone, setTimezone] = useState("Asia/Kolkata");
  const [today, setToday] = useState<Attendance | null>(null);
  const [summary, setSummary] = useState<Summary>({ present: 0, wfh: 0, holiday: 0, absent: 0 });
  const [office, setOffice] = useState<string | null>(null);
  const [geofences, setGeofences] = useState<Geofence[]>([]);
  const [permission, setPermission] = useState<PermissionState>("denied");
  const [geofenceActive, setGeofenceActive] = useState(false);
  const [checkoutOpen, setCheckoutOpen] = useState(false);
  const [workSummary, setWorkSummary] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!profile) return;
    const tz = await fetchAppTimezone();
    setTimezone(tz);

    const now = new Date();
    const [attendance, month, geofences, perm, active] = await Promise.all([
      fetchTodayAttendance(profile.id, tz),
      fetchMonthAttendance(profile.id, now.getFullYear(), now.getMonth() + 1),
      fetchAssignedGeofences(),
      getPermissionState(),
      isGeofencingActive(),
    ]);

    setToday(attendance);
    setPermission(perm);
    setGeofenceActive(active);
    setGeofences(geofences);
    setOffice(geofences[0]?.name ?? null);

    setSummary(
      month.reduce<Summary>(
        (acc, r) => {
          if (r.status === "PRESENT" || r.status === "CHECKED_OUT" || r.status === "MANUAL_OVERRIDE")
            acc.present += 1;
          else if (r.status === "WFH") acc.wfh += 1;
          else if (r.status === "HOLIDAY") acc.holiday += 1;
          else if (r.status === "ABSENT") acc.absent += 1;
          return acc;
        },
        { present: 0, wfh: 0, holiday: 0, absent: 0 },
      ),
    );

    if (perm === "granted" && geofences.length > 0) {
      try {
        await syncGeofences(geofences);
      } catch {
        // Background geofencing is unavailable (e.g. Expo Go); manual actions still work.
      }
      setGeofenceActive(await isGeofencingActive());
    }
  }, [profile]);

  useEffect(() => {
    load().finally(() => setLoading(false));
  }, [load]);

  async function onRefresh() {
    setRefreshing(true);
    await load();
    setRefreshing(false);
  }

  async function enableLocation() {
    const state = await requestPermissions();
    setPermission(state);
    await load();
  }

  function openCheckout() {
    setActionError(null);
    setActionMessage(null);
    setWorkSummary(today?.work_summary ?? "");
    setCheckoutOpen(true);
  }

  function closeCheckout() {
    if (submitting) return;
    setCheckoutOpen(false);
    setActionError(null);
  }

  async function checkIn() {
    setActionError(null);
    setActionMessage(null);
    setSubmitting(true);
    const previous = today;
    try {
      const position = await getCurrentPosition();
      const { latitude, longitude, accuracy } = position.coords;
      const target = nearestGeofence(geofences, latitude, longitude);
      if (!target) {
        setActionError("No geofence is assigned to your account.");
        return;
      }
      const distance = distanceMeters(latitude, longitude, target.latitude, target.longitude);
      if (distance > target.radius_meters) {
        setActionError(`You are about ${Math.round(distance)} m from ${target.name}. Move inside to check in.`);
        return;
      }
      const nowIso = new Date().toISOString();
      // Reflect the expected state immediately, even on the first check-in of
      // the day when no attendance row exists yet. Rolled back on failure below.
      setToday(
        optimisticCheckIn(previous, nowIso, profile?.id ?? "", businessDate(new Date(), timezone)),
      );
      await recordLocationEvent({
        geofenceId: target.id,
        eventType: "ENTER",
        occurredAt: nowIso,
        accuracyMeters: accuracy,
        dedupeKey: `mobile:${target.id}:ENTER:${Math.floor(Date.now() / 60000)}`,
        source: "Mobile geolocation",
        metadata: { platform: "expo-location", note: "explicit check-in" },
      });
    } catch (e) {
      setToday(previous);
      setActionError(errorMessage(e, "Check-in failed. Please try again."));
      return;
    } finally {
      setSubmitting(false);
    }
    setActionMessage("Check-in recorded.");
    try {
      await load();
    } catch {
      // The check-in is committed; the next refresh will reconcile the view.
    }
  }

  async function submitCheckout() {
    if (!today?.id) {
      setActionError("Check in before checking out.");
      return;
    }
    const summaryText = workSummary.trim();
    if (summaryText.length < 3) {
      setActionError("Please describe what you worked on today.");
      return;
    }
    setActionError(null);
    setActionMessage(null);
    setSubmitting(true);
    const previous = today;
    setToday(optimisticCheckOut(today, new Date().toISOString(), summaryText));
    try {
      await employeeCheckOut({ attendanceId: today.id, summary: summaryText });
    } catch (e) {
      setToday(previous);
      setActionError(errorMessage(e, "Check-out failed. Please try again."));
      return;
    } finally {
      setSubmitting(false);
    }
    setCheckoutOpen(false);
    setWorkSummary("");
    setActionMessage("Check-out recorded.");
    try {
      await load();
    } catch {
      // The check-out is committed; the next refresh will reconcile the view.
    }
  }

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  const tone = today ? statusColor[today.status] : statusColor.ABSENT;
  const date = businessDate(new Date(), timezone);

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
    >
      <View style={[styles.statusCard, { backgroundColor: tone.bg }]}>
        <Text style={[styles.statusLabel, { color: tone.fg }]}>
          {today ? STATUS_LABELS[today.status] : "Not checked in"}
        </Text>
        <Text style={styles.statusDate}>{format(new Date(`${date}T00:00:00`), "EEEE, d MMM yyyy")}</Text>
        <View style={styles.timeRow}>
          <TimeBox label="Check-in" value={today?.check_in_at ? format(new Date(today.check_in_at), "h:mm a") : "—"} />
          <TimeBox label="Check-out" value={today?.check_out_at ? format(new Date(today.check_out_at), "h:mm a") : "—"} />
          <TimeBox label="Duration" value={formatDuration(today?.total_duration_seconds)} />
        </View>
      </View>

      <View style={styles.card}>
        <Text style={styles.cardTitle}>Attendance</Text>
        {!today?.check_in_at ? (
          <>
            <Text style={styles.cardHint}>
              Check in when you arrive. We confirm you are inside your office geofence.
            </Text>
            <TouchableOpacity
              style={[styles.button, submitting ? styles.buttonDisabled : undefined]}
              onPress={checkIn}
              disabled={submitting}
            >
              {submitting ? (
                <ActivityIndicator color={colors.primaryForeground} />
              ) : (
                <Text style={styles.buttonText}>Check in</Text>
              )}
            </TouchableOpacity>
          </>
        ) : !today.check_out_at ? (
          <>
            <Text style={styles.cardHint}>Add a short work summary when you leave.</Text>
            <TouchableOpacity style={styles.button} onPress={openCheckout}>
              <Text style={styles.buttonText}>Check out</Text>
            </TouchableOpacity>
          </>
        ) : (
          <>
            <Text style={styles.cardHint}>You are checked out. You can update your summary anytime.</Text>
            <TouchableOpacity style={styles.secondaryButton} onPress={openCheckout}>
              <Text style={styles.secondaryButtonText}>Update work summary</Text>
            </TouchableOpacity>
          </>
        )}
        {actionMessage ? <Text style={styles.successText}>{actionMessage}</Text> : null}
        {actionError && !checkoutOpen ? <Text style={styles.errorText}>{actionError}</Text> : null}
      </View>

      {today?.work_summary ? (
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Work summary</Text>
          <Text style={styles.summaryText}>{today.work_summary}</Text>
        </View>
      ) : null}

      <View style={styles.card}>
        <Text style={styles.cardTitle}>Assigned office</Text>
        <Text style={styles.cardValue}>{office ?? "No geofence assigned"}</Text>
        <Text style={styles.cardHint}>
          {geofenceActive
            ? "Automatic detection is active in the background."
            : "Automatic detection is not running."}
        </Text>
      </View>

      {permission !== "granted" ? (
        <View style={[styles.card, styles.warningCard]}>
          <Text style={styles.cardTitle}>Location permission</Text>
          <Text style={styles.cardHint}>
            {permission === "services-disabled"
              ? "Location services are turned off. Enable them in your device settings."
              : permission === "foreground-only"
                ? "Allow 'Always' location access so attendance works with the app closed."
                : "Location permission is required to record attendance automatically."}
          </Text>
          <TouchableOpacity style={styles.button} onPress={enableLocation}>
            <Text style={styles.buttonText}>Enable location</Text>
          </TouchableOpacity>
        </View>
      ) : null}

      <View style={styles.card}>
        <Text style={styles.cardTitle}>This month</Text>
        <View style={styles.summaryRow}>
          <Summary label="Present" value={summary.present} color={colors.positive} />
          <Summary label="WFH" value={summary.wfh} color={colors.info} />
          <Summary label="Holiday" value={summary.holiday} color={colors.neutral} />
          <Summary label="Absent" value={summary.absent} color={colors.warning} />
        </View>
      </View>

      <Text style={styles.privacy}>
        Only geofence entry/exit transitions are recorded — never a continuous location trail.
      </Text>

      <Modal visible={checkoutOpen} transparent animationType="fade" onRequestClose={closeCheckout}>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalCard}>
            <Text style={styles.modalTitle}>Check out</Text>
            <Text style={styles.modalHint}>
              Tell us what you worked on today. This is required to check out.
            </Text>
            <TextInput
              style={styles.summaryInput}
              multiline
              autoFocus
              placeholder="e.g. Completed the attendance API, reviewed 2 PRs, attended standup."
              placeholderTextColor={colors.muted}
              value={workSummary}
              onChangeText={setWorkSummary}
            />
            {actionError ? <Text style={styles.errorText}>{actionError}</Text> : null}
            <View style={styles.modalActions}>
              <TouchableOpacity
                style={[styles.secondaryButton, styles.modalButton]}
                onPress={closeCheckout}
                disabled={submitting}
              >
                <Text style={styles.secondaryButtonText}>Cancel</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.button, styles.modalButton, submitting ? styles.buttonDisabled : undefined]}
                onPress={submitCheckout}
                disabled={submitting}
              >
                {submitting ? (
                  <ActivityIndicator color={colors.primaryForeground} />
                ) : (
                  <Text style={styles.buttonText}>Confirm check-out</Text>
                )}
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
    </ScrollView>
  );
}

function nearestGeofence(geofences: Geofence[], latitude: number, longitude: number): Geofence | null {
  let nearest: Geofence | null = null;
  let nearestDistance = Number.POSITIVE_INFINITY;
  for (const geofence of geofences) {
    const distance = distanceMeters(latitude, longitude, geofence.latitude, geofence.longitude);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = geofence;
    }
  }
  return nearest;
}

function optimisticCheckIn(record: Attendance | null, at: string, userId: string, date: string): Attendance {
  const base: Attendance = record ?? {
    id: "",
    user_id: userId,
    date,
    status: "PRESENT",
    check_in_at: null,
    check_out_at: null,
    total_duration_seconds: null,
    work_summary: null,
    source: "automatic",
    created_at: at,
    updated_at: at,
  };
  return {
    ...base,
    status: "PRESENT",
    check_in_at: base.check_in_at ?? at,
    check_out_at: null,
    total_duration_seconds: null,
  };
}

function optimisticCheckOut(record: Attendance, at: string, summary: string): Attendance {
  const checkOutAt = record.check_out_at ?? at;
  return {
    ...record,
    status: "CHECKED_OUT",
    check_out_at: checkOutAt,
    total_duration_seconds: record.check_in_at
      ? Math.max(0, Math.round((new Date(checkOutAt).getTime() - new Date(record.check_in_at).getTime()) / 1000))
      : record.total_duration_seconds,
    work_summary: summary,
  };
}

function errorMessage(error: unknown, fallback: string): string {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === "object" && error !== null && "message" in error) {
    const message = (error as { message?: unknown }).message;
    if (typeof message === "string" && message) return message;
  }
  return fallback;
}

function TimeBox({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.timeBox}>
      <Text style={styles.timeLabel}>{label}</Text>
      <Text style={styles.timeValue}>{value}</Text>
    </View>
  );
}

function Summary({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <View style={styles.summaryItem}>
      <Text style={[styles.summaryValue, { color }]}>{value}</Text>
      <Text style={styles.summaryLabel}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, gap: spacing.lg },
  center: { flex: 1, alignItems: "center", justifyContent: "center", backgroundColor: colors.background },
  statusCard: { borderRadius: radius.lg, padding: spacing.xl },
  statusLabel: { fontSize: 24, fontWeight: "700" },
  statusDate: { marginTop: spacing.xs, color: colors.muted, fontSize: 14 },
  timeRow: { flexDirection: "row", marginTop: spacing.xl, gap: spacing.lg },
  timeBox: { flex: 1 },
  timeLabel: { fontSize: 12, color: colors.muted },
  timeValue: { fontSize: 18, fontWeight: "600", color: colors.foreground, marginTop: 2 },
  card: {
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
  },
  warningCard: { borderColor: colors.warning },
  cardTitle: { fontSize: 14, fontWeight: "600", color: colors.foreground },
  cardValue: { marginTop: spacing.sm, fontSize: 16, color: colors.foreground },
  cardHint: { marginTop: spacing.sm, fontSize: 13, color: colors.muted, lineHeight: 18 },
  button: {
    marginTop: spacing.lg,
    minHeight: 44,
    justifyContent: "center",
    backgroundColor: colors.primary,
    borderRadius: radius.sm,
    paddingVertical: spacing.md,
    alignItems: "center",
  },
  buttonText: { color: colors.primaryForeground, fontWeight: "600" },
  summaryRow: { flexDirection: "row", marginTop: spacing.lg, justifyContent: "space-between" },
  summaryItem: { alignItems: "center", flex: 1 },
  summaryValue: { fontSize: 22, fontWeight: "700" },
  summaryLabel: { marginTop: 2, fontSize: 12, color: colors.muted },
  privacy: { fontSize: 12, color: colors.muted, textAlign: "center", paddingHorizontal: spacing.lg },
  buttonDisabled: { opacity: 0.6 },
  secondaryButton: {
    marginTop: spacing.lg,
    minHeight: 44,
    justifyContent: "center",
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.sm,
    paddingVertical: spacing.md,
    alignItems: "center",
  },
  secondaryButtonText: { color: colors.foreground, fontWeight: "600" },
  successText: { marginTop: spacing.md, fontSize: 13, color: colors.positive },
  errorText: { marginTop: spacing.md, fontSize: 13, color: colors.danger },
  summaryText: { marginTop: spacing.sm, fontSize: 14, color: colors.foreground, lineHeight: 20 },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.4)", justifyContent: "flex-end" },
  modalCard: {
    backgroundColor: colors.card,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    padding: spacing.xl,
  },
  modalTitle: { fontSize: 18, fontWeight: "700", color: colors.foreground },
  modalHint: { marginTop: spacing.xs, fontSize: 13, color: colors.muted, lineHeight: 18 },
  summaryInput: {
    marginTop: spacing.lg,
    minHeight: 120,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.sm,
    padding: spacing.md,
    fontSize: 15,
    color: colors.foreground,
    textAlignVertical: "top",
  },
  modalActions: { flexDirection: "row", gap: spacing.md, marginTop: spacing.lg },
  modalButton: { flex: 1, marginTop: 0 },
});

export { RouteErrorBoundary as ErrorBoundary } from "@/components/route-error";
