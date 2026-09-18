import Link from "next/link";
import { format } from "date-fns";
import { createClient } from "@/lib/supabase/server";
import { PRESENT_STATUSES, formatDuration, type Attendance } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { AttendanceCalendar, type CalendarRecord } from "@/components/attendance-calendar";

export const dynamic = "force-dynamic";

export default async function EmployeeHistoryPage({
  searchParams,
}: {
  searchParams: Promise<{ month?: string }>;
}) {
  const { month: monthParam } = await searchParams;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const monthKey = monthParam ?? format(new Date(), "yyyy-MM");
  const [yearStr, monthStr] = monthKey.split("-");
  const year = Number(yearStr);
  const month = Number(monthStr);
  const from = `${monthKey}-01`;
  const to = format(new Date(Date.UTC(year, month, 0)), "yyyy-MM-dd");

  const { data } = await supabase
    .from("attendance")
    .select("*")
    .eq("user_id", user.id)
    .gte("date", from)
    .lte("date", to)
    .order("date");

  const records = (data ?? []) as Attendance[];

  const totals = records.reduce(
    (acc, r) => {
      if (PRESENT_STATUSES.includes(r.status)) acc.present += 1;
      else if (r.status === "WFH") acc.wfh += 1;
      else if (r.status === "HOLIDAY") acc.holiday += 1;
      else if (r.status === "ABSENT") acc.absent += 1;
      return acc;
    },
    { present: 0, wfh: 0, holiday: 0, absent: 0 },
  );

  const prev = format(new Date(Date.UTC(year, month - 2, 1)), "yyyy-MM");
  const next = format(new Date(Date.UTC(year, month, 1)), "yyyy-MM");

  return (
    <>
      <PageHeader title="History" description="Your monthly attendance." />

      <div className="mb-4 flex items-center justify-between">
        <Link
          href={`/employee/history?month=${prev}`}
          className="flex h-10 items-center rounded-md px-3 text-sm font-medium text-primary hover:bg-accent"
        >
          ‹ Prev
        </Link>
        <span className="font-medium">{monthKey}</span>
        <Link
          href={`/employee/history?month=${next}`}
          className="flex h-10 items-center rounded-md px-3 text-sm font-medium text-primary hover:bg-accent"
        >
          Next ›
        </Link>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Tile label="Present" value={totals.present} />
        <Tile label="WFH" value={totals.wfh} />
        <Tile label="Holiday" value={totals.holiday} />
        <Tile label="Absent" value={totals.absent} />
      </div>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Calendar</CardTitle>
        </CardHeader>
        <CardContent>
          <AttendanceCalendar year={year} month={month} records={records as unknown as CalendarRecord[]} />
        </CardContent>
      </Card>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Daily detail</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {records.length === 0 ? (
            <p className="text-sm text-muted-foreground">No records for this month.</p>
          ) : (
            records.map((r) => (
              <div key={r.id} className="flex items-center justify-between border-b pb-2 text-sm last:border-0">
                <div>
                  <span className="font-medium">{r.date}</span>
                  <span className="ml-2 text-xs text-muted-foreground">{r.status}</span>
                </div>
                <span className="tabular-nums text-muted-foreground">
                  {r.check_in_at ? format(new Date(r.check_in_at), "h:mm a") : "—"}–
                  {r.check_out_at ? format(new Date(r.check_out_at), "h:mm a") : "—"} ·{" "}
                  {formatDuration(r.total_duration_seconds)}
                </span>
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </>
  );
}

function Tile({ label, value }: { label: string; value: number }) {
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-sm text-muted-foreground">{label}</p>
        <p className="mt-1 text-2xl font-semibold tabular-nums">{value}</p>
      </CardContent>
    </Card>
  );
}
