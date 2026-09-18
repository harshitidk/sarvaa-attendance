"use client";

import { useState } from "react";
import { format } from "date-fns";
import { Download } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { downloadCsv, toCsv } from "@/lib/csv";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input, Label } from "@/components/ui/input";

type ReportType = "attendance" | "wfh" | "holidays" | "corrections";

const REPORTS: { type: ReportType; title: string; description: string }[] = [
  { type: "attendance", title: "Attendance", description: "Daily/monthly attendance with status, times and duration." },
  { type: "wfh", title: "WFH assignments", description: "Employee work-from-home records." },
  { type: "holidays", title: "Holidays", description: "Company-wide and location-specific holidays." },
  { type: "corrections", title: "Manual corrections", description: "Auditable correction history." },
];

export function ExportPanel({ defaultFrom, defaultTo }: { defaultFrom: string; defaultTo: string }) {
  const [from, setFrom] = useState(defaultFrom);
  const [to, setTo] = useState(defaultTo);
  const [busy, setBusy] = useState<ReportType | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function run(type: ReportType) {
    setError(null);
    setBusy(type);
    const supabase = createClient();
    try {
      let rows: Record<string, unknown>[] = [];
      if (type === "attendance") {
        const { data, error: e } = await supabase
          .from("attendance")
          .select("date, status, check_in_at, check_out_at, total_duration_seconds, work_summary, source, user:users(employee_id, name, department)")
          .gte("date", from)
          .lte("date", to)
          .order("date");
        if (e) throw e;
        rows = (data ?? []).map((r: Record<string, unknown>) => {
          const user = r.user as { employee_id?: string; name?: string; department?: string } | null;
          return {
            date: r.date,
            employee_id: user?.employee_id ?? "",
            name: user?.name ?? "",
            department: user?.department ?? "",
            status: r.status,
            check_in_at: r.check_in_at,
            check_out_at: r.check_out_at,
            total_duration_seconds: r.total_duration_seconds,
            work_summary: r.work_summary ?? "",
            source: r.source,
          };
        });
      } else if (type === "wfh") {
        const { data, error: e } = await supabase
          .from("wfh_assignments")
          .select("date, reason, user:users(employee_id, name)")
          .gte("date", from)
          .lte("date", to)
          .order("date");
        if (e) throw e;
        rows = (data ?? []).map((r: Record<string, unknown>) => {
          const user = r.user as { employee_id?: string; name?: string } | null;
          return {
            date: r.date,
            employee_id: user?.employee_id ?? "",
            name: user?.name ?? "",
            reason: r.reason ?? "",
          };
        });
      } else if (type === "holidays") {
        const { data, error: e } = await supabase
          .from("holidays")
          .select("date, name, location:locations(name)")
          .gte("date", from)
          .lte("date", to)
          .order("date");
        if (e) throw e;
        rows = (data ?? []).map((r: Record<string, unknown>) => {
          const location = r.location as { name?: string } | null;
          return { date: r.date, name: r.name, scope: location?.name ?? "Company-wide" };
        });
      } else {
        const { data, error: e } = await supabase
          .from("attendance_corrections")
          .select("created_at, reason, old_value, new_value, admin:users(name), attendance:attendance(date, user:users(employee_id))")
          .order("created_at", { ascending: false });
        if (e) throw e;
        rows = (data ?? []).map((r: Record<string, unknown>) => {
          const admin = r.admin as { name?: string } | null;
          const attendance = r.attendance as { date?: string; user?: { employee_id?: string } } | null;
          return {
            created_at: r.created_at,
            date: attendance?.date ?? "",
            employee_id: attendance?.user?.employee_id ?? "",
            admin: admin?.name ?? "",
            reason: r.reason,
            old_status: (r.old_value as { status?: string } | null)?.status ?? "",
            new_status: (r.new_value as { status?: string } | null)?.status ?? "",
          };
        });
      }

      if (rows.length === 0) {
        setError("No records found for the selected range.");
        return;
      }
      downloadCsv(`${type}-${from}_to_${to}.csv`, toCsv(rows));
    } finally {
      setBusy(null);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>CSV exports</CardTitle>
      </CardHeader>
      <CardContent className="space-y-5">
        <div className="flex flex-wrap items-end gap-3">
          <div className="space-y-1">
            <Label htmlFor="export-from">From</Label>
            <Input id="export-from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="export-to">To</Label>
            <Input id="export-to" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </div>
          <p className="pb-2 text-xs text-muted-foreground">
            Date range applies to attendance, WFH and holidays. Corrections export all history.
          </p>
        </div>

        {error ? <p className="text-sm text-destructive">{error}</p> : null}

        <div className="grid gap-3 sm:grid-cols-2">
          {REPORTS.map((report) => (
            <div key={report.type} className="rounded-lg border p-4">
              <p className="font-medium">{report.title}</p>
              <p className="mt-1 text-sm text-muted-foreground">{report.description}</p>
              <Button
                variant="outline"
                size="sm"
                className="mt-3"
                disabled={busy !== null}
                onClick={() => run(report.type)}
              >
                <Download className="h-3.5 w-3.5" />
                {busy === report.type ? "Preparing…" : "Download CSV"}
              </Button>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
