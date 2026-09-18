import { createClient } from "@/lib/supabase/server";
import { DEFAULT_SETTINGS, type AppSettings } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { SettingsForm } from "@/components/settings-form";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("app_settings")
    .select(
      "company_timezone, workday_start, workday_end, absence_cutoff, exit_grace_seconds, event_retention_days",
    )
    .eq("id", 1)
    .single();

  const settings = (data ?? DEFAULT_SETTINGS) as AppSettings;

  return (
    <>
      <PageHeader
        title="Settings"
        description="Company timezone, working hours, grace period and absence cutoff."
      />
      <SettingsForm settings={settings} />
    </>
  );
}
