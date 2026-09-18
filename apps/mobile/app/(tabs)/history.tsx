import { useCallback, useEffect, useState } from "react";
import { ActivityIndicator, ScrollView, StyleSheet, Text, TouchableOpacity, View } from "react-native";
import { useAuth } from "@/providers/auth";
import { fetchAppTimezone, fetchMonthAttendance, fetchWfhForMonth } from "@/lib/api";
import { businessDate, STATUS_LABELS, formatDuration, type Attendance } from "@geo/shared";
import { colors, radius, spacing, statusColor } from "@/theme";

const WEEKDAYS = ["M", "T", "W", "T", "F", "S", "S"];

export default function HistoryScreen() {
  const { profile } = useAuth();
  const [cursor, setCursor] = useState(() => {
    const now = new Date();
    return { year: now.getFullYear(), month: now.getMonth() + 1 };
  });
  const [records, setRecords] = useState<Attendance[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Attendance | null>(null);
  const [timezone, setTimezone] = useState("Asia/Kolkata");

  const load = useCallback(async () => {
    if (!profile) return;
    setLoading(true);
    const [attendance, , tz] = await Promise.all([
      fetchMonthAttendance(profile.id, cursor.year, cursor.month),
      fetchWfhForMonth(profile.id, cursor.year, cursor.month),
      fetchAppTimezone(),
    ]);
    setRecords(attendance);
    setTimezone(tz);
    setLoading(false);
  }, [profile, cursor]);

  useEffect(() => {
    load();
  }, [load]);

  function shift(delta: number) {
    setSelected(null);
    setCursor(({ year, month }) => {
      const date = new Date(Date.UTC(year, month - 1 + delta, 1));
      return { year: date.getUTCFullYear(), month: date.getUTCMonth() + 1 };
    });
  }

  const byDate = new Map(records.map((r) => [r.date, r]));
  const first = new Date(Date.UTC(cursor.year, cursor.month - 1, 1));
  const daysInMonth = new Date(Date.UTC(cursor.year, cursor.month, 0)).getUTCDate();
  const startOffset = (first.getUTCDay() + 6) % 7;
  const today = businessDate(new Date(), timezone);
  const cells: (number | null)[] = [
    ...Array.from({ length: startOffset }, () => null),
    ...Array.from({ length: daysInMonth }, (_, i) => i + 1),
  ];
  while (cells.length % 7 !== 0) cells.push(null);

  const monthLabel = new Date(Date.UTC(cursor.year, cursor.month - 1, 1)).toLocaleString("en-US", {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <View style={styles.monthNav}>
        <TouchableOpacity onPress={() => shift(-1)} style={styles.navButton}>
          <Text style={styles.navText}>‹</Text>
        </TouchableOpacity>
        <Text style={styles.monthLabel}>{monthLabel}</Text>
        <TouchableOpacity onPress={() => shift(1)} style={styles.navButton}>
          <Text style={styles.navText}>›</Text>
        </TouchableOpacity>
      </View>

      {loading ? (
        <ActivityIndicator color={colors.primary} style={{ marginTop: spacing.xl }} />
      ) : (
        <>
          <View style={styles.weekRow}>
            {WEEKDAYS.map((d, i) => (
              <Text key={`${d}-${i}`} style={styles.weekday}>
                {d}
              </Text>
            ))}
          </View>
          <View style={styles.grid}>
            {cells.map((day, index) => {
              if (day === null) return <View key={index} style={styles.cell} />;
              const key = `${cursor.year}-${String(cursor.month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
              const record = byDate.get(key);
              const tone = record ? statusColor[record.status] : null;
              const isToday = key === today;
              return (
                <TouchableOpacity
                  key={index}
                  style={[
                    styles.cell,
                    tone ? { backgroundColor: tone.bg } : undefined,
                    isToday ? styles.todayCell : undefined,
                  ]}
                  onPress={() => setSelected(record ?? null)}
                  disabled={!record}
                >
                  <Text style={[styles.dayNumber, tone ? { color: tone.fg } : undefined]}>{day}</Text>
                  {record ? (
                    <Text style={[styles.dayStatus, { color: tone?.fg }]} numberOfLines={1}>
                      {record.status.replace("_", " ")}
                    </Text>
                  ) : null}
                </TouchableOpacity>
              );
            })}
          </View>

          {selected ? (
            <View style={styles.detailCard}>
              <Text style={styles.detailDate}>{selected.date}</Text>
              <Text style={[styles.detailStatus, { color: statusColor[selected.status].fg }]}>
                {STATUS_LABELS[selected.status]}
              </Text>
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Check-in</Text>
                <Text style={styles.detailValue}>
                  {selected.check_in_at ? selected.check_in_at.slice(11, 16) : "—"}
                </Text>
              </View>
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Check-out</Text>
                <Text style={styles.detailValue}>
                  {selected.check_out_at ? selected.check_out_at.slice(11, 16) : "—"}
                </Text>
              </View>
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Duration</Text>
                <Text style={styles.detailValue}>{formatDuration(selected.total_duration_seconds)}</Text>
              </View>
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Source</Text>
                <Text style={styles.detailValue}>
                  {selected.source === "manual" ? "Admin correction" : "Automatic"}
                </Text>
              </View>
            </View>
          ) : (
            <Text style={styles.hint}>Tap a day to see check-in, check-out and duration.</Text>
          )}
        </>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg },
  monthNav: { flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  navButton: { padding: spacing.md, minWidth: 44, minHeight: 44, alignItems: "center", justifyContent: "center" },
  navText: { fontSize: 26, color: colors.primary },
  monthLabel: { fontSize: 17, fontWeight: "600", color: colors.foreground },
  weekRow: { flexDirection: "row", marginTop: spacing.md },
  weekday: { flex: 1, textAlign: "center", fontSize: 12, color: colors.muted },
  grid: { flexDirection: "row", flexWrap: "wrap", marginTop: spacing.sm },
  cell: {
    width: `${100 / 7}%`,
    aspectRatio: 1,
    padding: 3,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: "transparent",
  },
  todayCell: { borderColor: colors.primary },
  dayNumber: { fontSize: 12, fontWeight: "600", color: colors.foreground },
  dayStatus: { fontSize: 8, marginTop: 1 },
  detailCard: {
    marginTop: spacing.xl,
    backgroundColor: colors.card,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
  },
  detailDate: { fontSize: 14, color: colors.muted },
  detailStatus: { fontSize: 18, fontWeight: "700", marginTop: 2 },
  detailRow: { flexDirection: "row", justifyContent: "space-between", marginTop: spacing.md },
  detailLabel: { color: colors.muted, fontSize: 14 },
  detailValue: { color: colors.foreground, fontSize: 14, fontWeight: "600" },
  hint: { marginTop: spacing.xl, textAlign: "center", color: colors.muted, fontSize: 13 },
});

export { RouteErrorBoundary as ErrorBoundary } from "@/components/route-error";
