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
    .select("company_timezone, absence_cutoff")
    .eq("id", 1)
    .single();

  const timezone = settings?.company_timezone ?? "Asia/Kolkata";
  const today = businessDate(new Date(), timezone);

  const [{ count: employeeCount }, { data: todayRows }] = await Promise.all([
    supabase.from("users").select("id", { count: "exact", head: true }).eq("role", "employee").eq("status", "active"),
    supabase
      .from("attendance")
      .select("id, status, check_in_at, check_out_at, user:users(name, employee_id, department)")
      .eq("date", today)
      .order("updated_at", { ascending: false }),
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
        <StatCard label="Absent / leave" value={absent} hint={`Cutoff ${settings?.absence_cutoff ?? "12:00"}`} />
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
    </>
  );
}
