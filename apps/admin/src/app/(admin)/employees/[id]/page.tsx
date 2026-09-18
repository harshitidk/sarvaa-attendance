import { notFound } from "next/navigation";
import { format } from "date-fns";
import { createClient } from "@/lib/supabase/server";
import type { AttendanceStatus } from "@geo/shared";
import { PRESENT_STATUSES, formatDuration } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { AttendanceCalendar, type CalendarRecord } from "@/components/attendance-calendar";

export const dynamic = "force-dynamic";

export default async function EmployeeDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ month?: string }>;
}) {
  const { id } = await params;
  const { month: monthParam } = await searchParams;
  const supabase = await createClient();

  const monthKey = monthParam ?? format(new Date(), "yyyy-MM");
  const [yearStr, monthStr] = monthKey.split("-");
  const year = Number(yearStr);
  const month = Number(monthStr);
  const from = `${monthKey}-01`;
  const to = format(new Date(Date.UTC(year, month, 0)), "yyyy-MM-dd");

  const { data: profile } = await supabase
    .from("users")
    .select("id, employee_id, name, email, role, department, status, location:locations(name)")
    .eq("id", id)
    .single();

  if (!profile) notFound();

  const { data: attendance } = await supabase
    .from("attendance")
    .select("id, date, status, check_in_at, check_out_at, total_duration_seconds, work_summary, source")
    .eq("user_id", id)
    .gte("date", from)
    .lte("date", to)
    .order("date");

  const attendanceIds = (attendance ?? []).map((row) => row.id);
  const { data: corrections } = attendanceIds.length
    ? await supabase
        .from("attendance_corrections")
        .select("id, attendance_id, old_value, new_value, reason, created_at, admin:users(name)")
        .in("attendance_id", attendanceIds)
        .order("created_at", { ascending: false })
        .limit(20)
    : { data: [] };

  const records = (attendance ?? []) as unknown as (CalendarRecord & {
    id: string;
    total_duration_seconds: number | null;
    work_summary: string | null;
    source: string;
  })[];

  const totals = records.reduce(
    (acc, r) => {
      if (PRESENT_STATUSES.includes(r.status)) acc.present += 1;
      else if (r.status === "WFH") acc.wfh += 1;
      else if (r.status === "HOLIDAY") acc.holiday += 1;
      else if (r.status === "ABSENT") acc.absent += 1;
      else if (r.status === "LEAVE") acc.leave += 1;
      return acc;
    },
    { present: 0, wfh: 0, holiday: 0, absent: 0, leave: 0 },
  );

  const p = profile as unknown as {
    employee_id: string;
    name: string;
    email: string;
    department: string | null;
    status: string;
    location: { name: string } | null;
  };

  return (
    <>
      <PageHeader
        title={p.name}
        description={`${p.employee_id} · ${p.email}${p.location ? ` · ${p.location.name}` : ""}`}
        actions={<Badge tone={p.status === "active" ? "positive" : "neutral"}>{p.status}</Badge>}
      />

      <div className="grid gap-4 sm:grid-cols-3 xl:grid-cols-5">
        <SummaryTile label="Present" value={totals.present} />
        <SummaryTile label="WFH" value={totals.wfh} />
        <SummaryTile label="Holiday" value={totals.holiday} />
        <SummaryTile label="Absent" value={totals.absent} />
        <SummaryTile label="Leave" value={totals.leave} />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1.4fr_1fr]">
        <Card>
          <CardHeader>
            <CardTitle>Monthly calendar · {monthKey}</CardTitle>
          </CardHeader>
          <CardContent>
            <AttendanceCalendar year={year} month={month} records={records} />
          </CardContent>
        </Card>

        <div className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle>Daily detail</CardTitle>
            </CardHeader>
            <CardContent className="max-h-80 space-y-2 overflow-auto">
              {records.length === 0 ? (
                <p className="text-sm text-muted-foreground">No records for this month.</p>
              ) : (
                records.map((r) => (
                  <div key={r.id} className="border-b pb-2 text-sm last:border-0">
                    <div className="flex items-center justify-between">
                      <div>
                        <span className="font-medium">{r.date}</span>
                        <span className="ml-2 text-xs text-muted-foreground">{r.status}</span>
                      </div>
                      <span className="text-xs tabular-nums text-muted-foreground">
                        {r.check_in_at ? format(new Date(r.check_in_at), "h:mm a") : "—"}–
                        {r.check_out_at ? format(new Date(r.check_out_at), "h:mm a") : "—"}
                        {" · "}
                        {formatDuration(r.total_duration_seconds)}
                      </span>
                    </div>
                    {r.work_summary ? (
                      <p className="mt-1 text-xs text-muted-foreground">{r.work_summary}</p>
                    ) : null}
                  </div>
                ))
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Correction history</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {(corrections ?? []).length === 0 ? (
                <p className="text-sm text-muted-foreground">No corrections recorded.</p>
              ) : (
                (corrections ?? []).map((c) => {
                  const row = c as unknown as {
                    id: string;
                    reason: string;
                    created_at: string;
                    admin: { name: string } | null;
                  };
                  return (
                    <div key={row.id} className="rounded-md border p-2 text-sm">
                      <p className="font-medium">{row.reason}</p>
                      <p className="text-xs text-muted-foreground">
                        {row.admin?.name ?? "Admin"} · {format(new Date(row.created_at), "dd MMM yyyy h:mm a")}
                      </p>
                    </div>
                  );
                })
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </>
  );
}

function SummaryTile({ label, value }: { label: string; value: number }) {
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-sm text-muted-foreground">{label}</p>
        <p className="mt-1 text-2xl font-semibold tabular-nums">{value}</p>
      </CardContent>
    </Card>
  );
}
