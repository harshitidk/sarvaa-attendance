import { createClient } from "@/lib/supabase/server";
import { businessDate, type AttendanceStatus } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/status-badge";
import { format } from "date-fns";

export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const supabase = await createClient();

  const { data: settings } = await supabase
    .from("app_settings")
    .select("company_timezone")
    .eq("id", 1)
    .single();

  const timezone = settings?.company_timezone ?? "Asia/Kolkata";
  const today = businessDate(new Date(), timezone);

  const todayDate = new Date(`${today}T00:00:00Z`);
  const monthStart = `${today.slice(0, 7)}-01`;
  const monday = new Date(todayDate);
  monday.setUTCDate(todayDate.getUTCDate() - ((todayDate.getUTCDay() + 6) % 7));
  const weekStart = monday.toISOString().slice(0, 10);

  const [{ count: employeeCount }, { data: todayRows }, { data: timeRows }] = await Promise.all([
    supabase.from("users").select("id", { count: "exact", head: true }).eq("role", "employee").eq("status", "active"),
    supabase
      .from("attendance")
      .select("id, status, check_in_at, check_out_at, user:users(name, employee_id, department)")
      .eq("date", today)
      .order("updated_at", { ascending: false }),
    supabase
      .from("attendance")
      .select("date, status, total_duration_seconds, user:users(name, employee_id)")
      .gte("date", monthStart)
      .lte("date", today),
  ]);

  const rows = (todayRows ?? []) as unknown as {
    id: string;
    status: AttendanceStatus;
    check_in_at: string | null;
    check_out_at: string | null;
    user: { name: string; employee_id: string; department: string | null } | null;
  }[];

  const count = (statuses: AttendanceStatus[]) => rows.filter((r) => statuses.includes(r.status)).length;
  const present = count(["PRESENT"]);
  const checkedOut = count(["CHECKED_OUT"]);
  const wfh = count(["WFH"]);
  const holiday = count(["HOLIDAY"]);
  const absent = count(["ABSENT", "LEAVE"]);
  const onSite = present + checkedOut;

  const OFFICE: AttendanceStatus[] = ["PRESENT", "CHECKED_OUT", "MANUAL_OVERRIDE"];
  const timeAgg = new Map<
    string,
    { name: string; code: string; weekSec: number; weekDays: number; monthSec: number; monthDays: number }
  >();
  for (const r of (timeRows ?? []) as unknown as {
    date: string;
    status: AttendanceStatus;
    total_duration_seconds: number | null;
    user: { name: string; employee_id: string } | null;
  }[]) {
    const key = r.user?.employee_id ?? r.user?.name ?? "unknown";
    const entry =
      timeAgg.get(key) ?? {
        name: r.user?.name ?? "Unknown",
        code: r.user?.employee_id ?? "",
        weekSec: 0,
        weekDays: 0,
        monthSec: 0,
        monthDays: 0,
      };
    const secs = r.total_duration_seconds ?? 0;
    const office = OFFICE.includes(r.status);
    entry.monthSec += secs;
    if (office) entry.monthDays += 1;
    if (r.date >= weekStart) {
      entry.weekSec += secs;
      if (office) entry.weekDays += 1;
    }
    timeAgg.set(key, entry);
  }
  const timeEntries = Array.from(timeAgg.values()).sort((a, b) => b.monthSec - a.monthSec);

  const fmtTime = (secs: number, days: number) => {
    if (!secs) return "—";
    const hours = Math.floor(secs / 3600);
    const mins = Math.round((secs % 3600) / 60);
    const total = `${hours}h ${mins.toString().padStart(2, "0")}m`;
    if (days <= 0) return total;
    const avg = Math.round(secs / days);
    return `${total} · avg ${Math.floor(avg / 3600)}h ${Math.round((avg % 3600) / 60).toString().padStart(2, "0")}m/day`;
  };

  return (
    <>
      <PageHeader
        title="Dashboard"
        description={`Today · ${today} · ${timezone}`}
      />

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <StatCard label="Present (on-site)" value={onSite} hint={`${present} not checked out`} />
        <StatCard label="Checked out" value={checkedOut} />
        <StatCard label="WFH" value={wfh} />
        <StatCard label="Holiday" value={holiday} />
        <StatCard label="Absent / leave" value={absent} />
      </div>

      <Card className="mt-6">
        <CardHeader className="flex-row items-center justify-between">
          <CardTitle>Today's activity</CardTitle>
          <span className="text-sm text-muted-foreground">
            {rows.length} of {employeeCount ?? 0} employees recorded
          </span>
        </CardHeader>
        <CardContent className="space-y-3">
          {rows.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              No attendance recorded yet today.
            </p>
          ) : (
            rows.slice(0, 12).map((row) => (
              <div
                key={row.id}
                className="flex items-center justify-between rounded-md border px-3 py-2"
              >
                <div>
                  <p className="text-sm font-medium">{row.user?.name ?? "Unknown"}</p>
                  <p className="text-xs text-muted-foreground">
                    {row.user?.employee_id}
                    {row.user?.department ? ` · ${row.user.department}` : ""}
                  </p>
                </div>
                <div className="flex items-center gap-4">
                  <span className="text-xs tabular-nums text-muted-foreground">
                    {row.check_in_at ? format(new Date(row.check_in_at), "h:mm a") : "—"}
                    {" → "}
                    {row.check_out_at ? format(new Date(row.check_out_at), "h:mm a") : "—"}
                  </span>
                  <StatusBadge status={row.status} />
                </div>
              </div>
            ))
          )}
        </CardContent>
      </Card>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Time in office — week &amp; month</CardTitle>
        </CardHeader>
        <CardContent>
          {timeEntries.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              No time recorded yet this month.
            </p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-muted-foreground">
                  <th className="pb-2 font-medium">Employee</th>
                  <th className="pb-2 font-medium">This week</th>
                  <th className="pb-2 font-medium">This month</th>
                </tr>
              </thead>
              <tbody>
                {timeEntries.map((e) => (
                  <tr key={e.code || e.name} className="border-t">
                    <td className="py-2">
                      <span className="font-medium">{e.name}</span>
                      {e.code ? (
                        <span className="ml-2 text-xs text-muted-foreground">{e.code}</span>
                      ) : null}
                    </td>
                    <td className="py-2 tabular-nums">{fmtTime(e.weekSec, e.weekDays)}</td>
                    <td className="py-2 tabular-nums">{fmtTime(e.monthSec, e.monthDays)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>
    </>
  );
}
