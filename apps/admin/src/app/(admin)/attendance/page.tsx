import { createClient } from "@/lib/supabase/server";
import { businessDate } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { AttendanceTable, type AttendanceRow } from "@/components/attendance-table";

export const dynamic = "force-dynamic";

export default async function AttendancePage({
  searchParams,
}: {
  searchParams: Promise<{ from?: string; to?: string }>;
}) {
  const params = await searchParams;
  const supabase = await createClient();

  const { data: settings } = await supabase
    .from("app_settings")
    .select("company_timezone")
    .eq("id", 1)
    .single();

  const today = businessDate(new Date(), settings?.company_timezone ?? "Asia/Kolkata");
  const from = params.from ?? today;
  const to = params.to ?? from;

  const { data, error } = await supabase
    .from("attendance")
    .select(
      "id, user_id, date, status, check_in_at, check_out_at, total_duration_seconds, work_summary, source, created_at, updated_at, user:users(name, employee_id, department), sessions:attendance_sessions(id, check_in_at, check_out_at)",
    )
    .gte("date", from)
    .lte("date", to)
    .order("date", { ascending: false })
    .order("user_id", { ascending: true })
    .limit(1000);

  const rows = (data ?? []) as unknown as AttendanceRow[];

  return (
    <>
      <PageHeader
        title="Attendance"
        description="All employee attendance records with auditable manual corrections."
      />
      <form className="mb-4 flex flex-wrap items-end gap-3" method="get">
        <label className="text-sm">
          <span className="mb-1 block text-muted-foreground">From</span>
          <input
            type="date"
            name="from"
            defaultValue={from}
            className="h-9 rounded-md border border-input bg-transparent px-3 text-sm"
          />
        </label>
        <label className="text-sm">
          <span className="mb-1 block text-muted-foreground">To</span>
          <input
            type="date"
            name="to"
            defaultValue={to}
            className="h-9 rounded-md border border-input bg-transparent px-3 text-sm"
          />
        </label>
        <button className="h-9 rounded-md bg-primary px-4 text-sm font-medium text-primary-foreground">
          Apply
        </button>
      </form>

      {error ? <p className="text-sm text-destructive">{error.message}</p> : null}
      <AttendanceTable rows={rows} />
    </>
  );
}
