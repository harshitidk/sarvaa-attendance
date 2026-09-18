import { format } from "date-fns";
import { createClient } from "@/lib/supabase/server";
import { businessDate } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { ExportPanel } from "@/components/export-panel";

export const dynamic = "force-dynamic";

export default async function ExportsPage() {
  const supabase = await createClient();
  const { data: settings } = await supabase
    .from("app_settings")
    .select("company_timezone")
    .eq("id", 1)
    .single();

  const today = businessDate(new Date(), settings?.company_timezone ?? "Asia/Kolkata");
  const monthStart = format(new Date(`${today}T00:00:00Z`), "yyyy-MM-01");

  return (
    <>
      <PageHeader title="Exports" description="CSV is sufficient for V1; Excel/PDF can be added later." />
      <ExportPanel defaultFrom={monthStart} defaultTo={today} />
    </>
  );
}
