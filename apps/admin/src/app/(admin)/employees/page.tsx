import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { PageHeader } from "@/components/page-header";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";

export const dynamic = "force-dynamic";

export default async function EmployeesPage() {
  const supabase = await createClient();
  const { data: employees } = await supabase
    .from("users")
    .select("id, employee_id, name, email, role, department, status, location:locations(name)")
    .order("name");

  const rows = (employees ?? []) as unknown as {
    id: string;
    employee_id: string;
    name: string;
    email: string;
    role: string;
    department: string | null;
    status: string;
    location: { name: string } | null;
  }[];

  return (
    <>
      <PageHeader
        title="Employees"
        description="Manage employee accounts, roles and office assignment."
      />
      <div className="rounded-lg border bg-card">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Employee ID</TableHead>
              <TableHead>Email</TableHead>
              <TableHead>Department</TableHead>
              <TableHead>Office</TableHead>
              <TableHead>Role</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={7} className="py-10 text-center text-muted-foreground">
                  No employees yet. Create an auth user to provision a profile.
                </TableCell>
              </TableRow>
            ) : (
              rows.map((row) => (
                <TableRow key={row.id}>
                  <TableCell>
                    <Link href={`/employees/${row.id}`} className="font-medium text-primary hover:underline">
                      {row.name}
                    </Link>
                  </TableCell>
                  <TableCell className="tabular-nums">{row.employee_id}</TableCell>
                  <TableCell>{row.email}</TableCell>
                  <TableCell>{row.department ?? "—"}</TableCell>
                  <TableCell>{row.location?.name ?? "—"}</TableCell>
                  <TableCell className="capitalize">{row.role}</TableCell>
                  <TableCell>
                    <Badge tone={row.status === "active" ? "positive" : "neutral"}>{row.status}</Badge>
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
