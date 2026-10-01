import { createClient } from "@/lib/supabase/server";
import { DEFAULT_SETTINGS, type AppSettings } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { SettingsForm } from "@/components/settings-form";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [{ data }, { data: profile }] = await Promise.all([
    supabase
      .from("app_settings")
      .select(
        "company_timezone, workday_start, workday_end, exit_grace_seconds, event_retention_days",
      )
      .eq("id", 1)
      .single(),
    user
      ? supabase.from("users").select("attendance_enabled").eq("id", user.id).single()
      : Promise.resolve({ data: null }),
  ]);

  const settings = (data ?? DEFAULT_SETTINGS) as AppSettings;
  const attendanceEnabled = (profile?.attendance_enabled as boolean | undefined) ?? false;

  return (
    <>
      <PageHeader
        title="Settings"
        description="Company timezone, working hours, grace period and your own attendance tracking."
      />
      <SettingsForm settings={settings} attendanceEnabled={attendanceEnabled} />
    </>
  );
}
