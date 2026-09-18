import { createClient } from "@/lib/supabase/server";
import { businessDate, type Attendance, type Geofence } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { CheckInPanel, type RecentEvent } from "@/components/employee/check-in-panel";

export const dynamic = "force-dynamic";

export default async function EmployeeTodayPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const { data: settings } = await supabase
    .from("app_settings")
    .select("company_timezone")
    .eq("id", 1)
    .single();
  const today = businessDate(new Date(), settings?.company_timezone ?? "Asia/Kolkata");

  const [{ data: geofences }, { data: attendance }, { data: events }] = await Promise.all([
    supabase.from("geofences").select("*").eq("active", true).order("name"),
    supabase.from("attendance").select("*").eq("user_id", user.id).eq("date", today).maybeSingle(),
    supabase
      .from("location_events")
      .select("id, event_type, occurred_at, accuracy_meters")
      .eq("user_id", user.id)
      .order("occurred_at", { ascending: false })
      .limit(8),
  ]);

  return (
    <>
      <PageHeader
        title="Today"
        description={`${today} · check in and out from this browser using GPS.`}
      />
      <CheckInPanel
        geofences={(geofences ?? []) as Geofence[]}
        attendance={(attendance as Attendance) ?? null}
        recentEvents={(events ?? []) as RecentEvent[]}
        timezone={settings?.company_timezone ?? "Asia/Kolkata"}
      />
    </>
  );
}
