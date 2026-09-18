import { format } from "date-fns";
import { createClient } from "@/lib/supabase/server";
import { PageHeader } from "@/components/page-header";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

export const dynamic = "force-dynamic";

export default async function AuditPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("audit_logs")
    .select("id, action, entity_type, entity_id, metadata, created_at, actor:users(name, email)")
    .order("created_at", { ascending: false })
    .limit(300);

  const rows = (data ?? []) as unknown as {
    id: string;
    action: string;
    entity_type: string;
    entity_id: string | null;
    metadata: Record<string, unknown>;
    created_at: string;
    actor: { name: string; email: string } | null;
  }[];

  return (
    <>
      <PageHeader title="Audit log" description="Sensitive administrative operations are recorded here." />
      <div className="rounded-lg border bg-card">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>When</TableHead>
              <TableHead>Actor</TableHead>
              <TableHead>Action</TableHead>
              <TableHead>Entity</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={4} className="py-10 text-center text-muted-foreground">
                  No audit entries yet.
                </TableCell>
              </TableRow>
            ) : (
              rows.map((row) => (
                <TableRow key={row.id}>
                  <TableCell className="whitespace-nowrap tabular-nums text-muted-foreground">
                    {format(new Date(row.created_at), "dd MMM yyyy h:mm a")}
                  </TableCell>
                  <TableCell>{row.actor?.name ?? row.actor?.email ?? "System"}</TableCell>
                  <TableCell className="capitalize">{row.action}</TableCell>
                  <TableCell>
                    <span className="font-mono text-xs">
                      {row.entity_type}
                      {row.entity_id ? `#${row.entity_id.slice(0, 8)}` : ""}
                    </span>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>
    </>
  );
}
