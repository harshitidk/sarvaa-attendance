import { format } from "date-fns";
import { createClient } from "@/lib/supabase/server";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent } from "@/components/ui/card";

export const dynamic = "force-dynamic";

export default async function CorrectionsPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("attendance_corrections")
    .select(
      "id, reason, old_value, new_value, created_at, admin:users(name), attendance:attendance(date, user:users(name, employee_id))",
    )
    .order("created_at", { ascending: false })
    .limit(200);

  const rows = (data ?? []) as unknown as {
    id: string;
    reason: string;
    old_value: Record<string, unknown>;
    new_value: Record<string, unknown>;
    created_at: string;
    admin: { name: string } | null;
    attendance: { date: string; user: { name: string; employee_id: string } | null } | null;
  }[];

  return (
    <>
      <PageHeader
        title="Corrections"
        description="Every manual adjustment retains the old value, new value, actor, timestamp and reason."
      />
      <div className="space-y-3">
        {rows.length === 0 ? (
          <Card>
            <CardContent className="py-12 text-center text-sm text-muted-foreground">
              No corrections recorded.
            </CardContent>
          </Card>
        ) : (
          rows.map((row) => (
            <Card key={row.id}>
              <CardContent className="p-4">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <p className="font-medium">
                      {row.attendance?.user?.name ?? "Unknown"} · {row.attendance?.date ?? "—"}
                    </p>
                    <p className="text-sm text-muted-foreground">{row.reason}</p>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {row.admin?.name ?? "Admin"} · {format(new Date(row.created_at), "dd MMM yyyy h:mm a")}
                  </p>
                </div>
                <div className="mt-3 grid gap-3 text-xs sm:grid-cols-2">
                  <pre className="overflow-auto rounded-md bg-muted p-2">
                    {JSON.stringify(
                      {
                        status: row.old_value?.status,
                        check_in_at: row.old_value?.check_in_at,
                        check_out_at: row.old_value?.check_out_at,
                      },
                      null,
                      2,
                    )}
                  </pre>
                  <pre className="overflow-auto rounded-md bg-emerald-50 p-2">
                    {JSON.stringify(
                      {
                        status: row.new_value?.status,
                        check_in_at: row.new_value?.check_in_at,
                        check_out_at: row.new_value?.check_out_at,
                      },
                      null,
                      2,
                    )}
                  </pre>
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>
    </>
  );
}
