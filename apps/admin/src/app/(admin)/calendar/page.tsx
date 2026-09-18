import { createClient } from "@/lib/supabase/server";
import type { Holiday, Location, User, WfhAssignment } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { CalendarManager } from "@/components/calendar-manager";

export const dynamic = "force-dynamic";

export default async function CalendarPage() {
  const supabase = await createClient();
  const [{ data: holidays }, { data: wfh }, { data: locations }, { data: employees }] = await Promise.all([
    supabase.from("holidays").select("*").order("date", { ascending: false }).limit(200),
    supabase.from("wfh_assignments").select("*").order("date", { ascending: false }).limit(200),
    supabase.from("locations").select("*").order("name"),
    supabase.from("users").select("id, name, employee_id").eq("role", "employee").order("name"),
  ]);

  return (
    <>
      <PageHeader
        title="Holidays & WFH"
        description="Exception priority: holiday → leave → WFH → office attendance → absent."
      />
      <CalendarManager
        holidays={(holidays ?? []) as Holiday[]}
        wfh={(wfh ?? []) as WfhAssignment[]}
        locations={(locations ?? []) as Location[]}
        employees={(employees ?? []) as Pick<User, "id" | "name" | "employee_id">[]}
      />
    </>
  );
}
