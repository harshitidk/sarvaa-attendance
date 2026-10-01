import Link from "next/link";
import { notFound } from "next/navigation";
import { format } from "date-fns";
import { createClient } from "@/lib/supabase/server";
import { formatDuration, type AttendanceStatus } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/status-badge";
import {
  formatMinuteOfDay,
  isReportPreset,
  minuteOfDay,
  reportRange,
  type ReportPreset,
} from "@/lib/report-range";

export const dynamic = "force-dynamic";

const OFFICE: AttendanceStatus[] = ["PRESENT", "CHECKED_OUT", "MANUAL_OVERRIDE"];

interface Row {
  id: string;
  date: string;
  status: AttendanceStatus;
  check_in_at: string | null;
  check_out_at: string | null;
  total_duration_seconds: number | null;
  work_summary: string | null;
  sessions: { id: string }[] | null;
}

export default async function ReportEmployeePage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ preset?: string }>;
}) {
  const { id } = await params;
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

  const { data: profile } = await supabase
    .from("users")
    .select("id, employee_id, name, department")
    .eq("id", id)
    .single();
  if (!profile) notFound();

  const { data } = await supabase
    .from("attendance")
    .select(
      "id, date, status, check_in_at, check_out_at, total_duration_seconds, work_summary, sessions:attendance_sessions(id)",
    )
    .eq("user_id", id)
    .gte("date", from)
    .lte("date", to)
    .order("date", { ascending: false });

  const rows = (data ?? []) as unknown as Row[];

  let presentDays = 0;
  let wfh = 0;
  let leave = 0;
  let holiday = 0;
  let absent = 0;
  let workSeconds = 0;
  let visits = 0;
  let checkInMinutes = 0;
  let checkInCount = 0;

  for (const row of rows) {
    if (row.check_in_at) {
      checkInMinutes += minuteOfDay(row.check_in_at, timezone);
      checkInCount += 1;
    }
    if (OFFICE.includes(row.status)) {
      presentDays += 1;
      workSeconds += row.total_duration_seconds ?? 0;
      visits += row.sessions?.length ?? 0;
    } else if (row.status === "WFH") wfh += 1;
    else if (row.status === "LEAVE") leave += 1;
    else if (row.status === "HOLIDAY") holiday += 1;
    else if (row.status === "ABSENT") absent += 1;
  }

  const averageSeconds = presentDays === 0 ? 0 : Math.floor(workSeconds / presentDays);
  const averageCheckIn =
    checkInCount === 0 ? null : formatMinuteOfDay(checkInMinutes / checkInCount);

  return (
    <>
      <PageHeader
        title={profile.name}
        description={`${profile.employee_id}${
          profile.department ? ` · ${profile.department}` : ""
        } · ${from} → ${to}`}
      />

      <Link
        href={`/reports?preset=${preset}`}
        className="mb-4 inline-block text-sm text-muted-foreground hover:text-foreground"
      >
        ← Back to reports
      </Link>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat label="Time in office" value={formatDuration(workSeconds)} />
        <Stat
          label="Avg / attended day"
          value={presentDays === 0 ? "—" : formatDuration(averageSeconds)}
        />
        <Stat label="Avg check-in" value={averageCheckIn ?? "—"} />
        <Stat label="Office visits" value={String(visits)} />
      </div>

      <Card className="mt-4">
        <CardHeader>
          <CardTitle>Days</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-5 gap-3 text-center">
            <Count label="Present" value={presentDays} />
            <Count label="Home" value={wfh} />
            <Count label="Leave" value={leave} />
            <Count label="Holiday" value={holiday} />
            <Count label="Absent" value={absent} />
          </div>
        </CardContent>
      </Card>

      <Card className="mt-4">
        <CardHeader>
          <CardTitle>Records</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {rows.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              No records in this range.
            </p>
          ) : (
            rows.map((row) => (
              <div
                key={row.id}
                className="flex items-center justify-between rounded-md border px-3 py-2"
              >
                <div>
                  <p className="text-sm font-medium">
                    {format(new Date(`${row.date}T00:00:00`), "EEE, d MMM y")}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {row.check_in_at ? format(new Date(row.check_in_at), "h:mm a") : "—"}
                    {" → "}
                    {row.check_out_at ? format(new Date(row.check_out_at), "h:mm a") : "—"}
                    {row.sessions && row.sessions.length > 1
                      ? ` · ${row.sessions.length} visits`
                      : ""}
                  </p>
                </div>
                <div className="flex items-center gap-4">
                  <span className="text-xs tabular-nums text-muted-foreground">
                    {formatDuration(row.total_duration_seconds)}
                  </span>
                  <StatusBadge status={row.status} />
                </div>
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <Card>
      <CardContent className="pt-6">
        <p className="text-2xl font-semibold tabular-nums">{value}</p>
        <p className="text-xs text-muted-foreground">{label}</p>
      </CardContent>
    </Card>
  );
}

function Count({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <p className="text-xl font-semibold tabular-nums">{value}</p>
      <p className="text-xs text-muted-foreground">{label}</p>
    </div>
  );
}
