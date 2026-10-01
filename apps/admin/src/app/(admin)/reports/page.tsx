import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatDuration, type AttendanceStatus } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  REPORT_PRESETS,
  formatMinuteOfDay,
  isReportPreset,
  minuteOfDay,
  reportRange,
  type ReportPreset,
} from "@/lib/report-range";

export const dynamic = "force-dynamic";

const OFFICE: AttendanceStatus[] = ["PRESENT", "CHECKED_OUT", "MANUAL_OVERRIDE"];

interface ReportRow {
  user_id: string;
  date: string;
  status: AttendanceStatus;
  check_in_at: string | null;
  total_duration_seconds: number | null;
  sessions: { id: string }[] | null;
  user: { name: string; employee_id: string } | null;
}

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<{ preset?: string }>;
}) {
  const { preset: presetParam } = await searchParams;
  const preset: ReportPreset = isReportPreset(presetParam) ? presetParam : "thisMonth";

  const supabase = await createClient();
  const { data: settings } = await supabase
    .from("app_settings")
    .select("company_timezone")
    .eq("id", 1)
    .single();
  const timezone = settings?.company_timezone ?? "Asia/Kolkata";

  const { from, to } = reportRange(preset);

  const { data } = await supabase
    .from("attendance")
    .select(
      "user_id, date, status, check_in_at, total_duration_seconds, sessions:attendance_sessions(id), user:users(name, employee_id)",
    )
    .gte("date", from)
    .lte("date", to);

  const rows = (data ?? []) as unknown as ReportRow[];

  const byUser = new Map<
    string,
    {
      name: string;
      code: string;
      presentDays: number;
      attendedDays: number;
      workSeconds: number;
      visits: number;
      checkInMinutes: number;
      checkInCount: number;
    }
  >();

  for (const row of rows) {
    const key = row.user_id;
    const entry =
      byUser.get(key) ??
      {
        name: row.user?.name ?? "Unknown",
        code: row.user?.employee_id ?? "",
        presentDays: 0,
        attendedDays: 0,
        workSeconds: 0,
        visits: 0,
        checkInMinutes: 0,
        checkInCount: 0,
      };
    if (row.check_in_at) {
      entry.checkInMinutes += minuteOfDay(row.check_in_at, timezone);
      entry.checkInCount += 1;
    }
    if (OFFICE.includes(row.status)) {
      entry.presentDays += 1;
      entry.attendedDays += 1;
      entry.workSeconds += row.total_duration_seconds ?? 0;
      entry.visits += row.sessions?.length ?? 0;
    }
    byUser.set(key, entry);
  }

  const reports = Array.from(byUser.entries())
    .map(([id, e]) => ({
      id,
      ...e,
      averageSeconds: e.attendedDays === 0 ? 0 : Math.floor(e.workSeconds / e.attendedDays),
      averageCheckIn:
        e.checkInCount === 0 ? null : formatMinuteOfDay(e.checkInMinutes / e.checkInCount),
    }))
    .sort((a, b) => b.workSeconds - a.workSeconds);

  return (
    <>
      <PageHeader
        title="Reports"
        description={`${from} → ${to} · ${timezone}`}
      />

      <div className="mb-4 flex flex-wrap gap-2">
        {REPORT_PRESETS.map((p) => {
          const active = p.key === preset;
          return (
            <Link
              key={p.key}
              href={`/reports?preset=${p.key}`}
              className={`rounded-full border px-4 py-1.5 text-sm transition-colors ${
                active
                  ? "border-foreground bg-foreground text-background"
                  : "border-border bg-background text-muted-foreground hover:text-foreground"
              }`}
            >
              {p.label}
            </Link>
          );
        })}
      </div>

      {reports.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-sm text-muted-foreground">
            No records in this range.
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {reports.map((report) => (
            <Link key={report.id} href={`/reports/${report.id}?preset=${preset}`}>
              <Card className="h-full transition-colors hover:border-foreground/40">
                <CardHeader className="flex-row items-center justify-between">
                  <CardTitle className="text-base">
                    {report.name}
                    {report.code ? (
                      <span className="ml-2 text-xs font-normal text-muted-foreground">
                        {report.code}
                      </span>
                    ) : null}
                  </CardTitle>
                  <span className="text-xs text-muted-foreground">
                    {report.attendedDays} day{report.attendedDays === 1 ? "" : "s"}
                  </span>
                </CardHeader>
                <CardContent>
                  <div className="grid grid-cols-2 gap-4">
                    <Metric label="Time in office" value={formatDuration(report.workSeconds)} />
                    <Metric
                      label="Avg / attended day"
                      value={report.attendedDays === 0 ? "—" : formatDuration(report.averageSeconds)}
                    />
                    <Metric label="Avg check-in" value={report.averageCheckIn ?? "—"} />
                    <Metric label="Office visits" value={String(report.visits)} />
                  </div>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      )}
    </>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-lg font-semibold tabular-nums">{value}</p>
      <p className="text-xs text-muted-foreground">{label}</p>
    </div>
  );
}
