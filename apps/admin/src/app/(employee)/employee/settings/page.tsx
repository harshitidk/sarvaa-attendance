import { createClient } from "@/lib/supabase/server";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { SignOutButton } from "@/components/sign-out-button";

export const dynamic = "force-dynamic";

export default async function EmployeeSettingsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("users")
    .select("name, employee_id, email, department, location:locations(name)")
    .eq("id", user.id)
    .single();

  const p = profile as unknown as {
    name: string;
    employee_id: string;
    email: string;
    department: string | null;
    location: { name: string } | null;
  } | null;

  return (
    <>
      <PageHeader title="Settings" description="Your account and location guidance." />

      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Account</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row label="Name" value={p?.name ?? "—"} />
            <Row label="Employee ID" value={p?.employee_id ?? "—"} />
            <Row label="Email" value={p?.email ?? "—"} />
            <Row label="Department" value={p?.department ?? "—"} />
            <Row label="Office" value={p?.location?.name ?? "—"} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Location guidance</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>
              Attendance is recorded from geofence entry/exit transitions — not from continuous tracking.
              Your browser asks for location permission the first time you check in.
            </p>
            <ul className="list-disc space-y-1 pl-5">
              <li>Allow location access when prompted, and keep the page open for automatic detection.</li>
              <li>If you blocked it, re-enable location for this site in your browser's site settings.</li>
              <li>Location requires <code>localhost</code> or an HTTPS address.</li>
            </ul>
          </CardContent>
        </Card>

        <SignOutButton variant="destructive" size="default" className="h-11 w-full sm:w-auto" />
      </div>
    </>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between border-b py-1.5 last:border-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  );
}
