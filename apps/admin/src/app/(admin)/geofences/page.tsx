import { createClient } from "@/lib/supabase/server";
import type { Geofence, Location } from "@geo/shared";
import { PageHeader } from "@/components/page-header";
import { GeofenceManager } from "@/components/geofence-manager";

export const dynamic = "force-dynamic";

export default async function GeofencesPage() {
  const supabase = await createClient();
  const [{ data: geofences }, { data: locations }] = await Promise.all([
    supabase.from("geofences").select("*").order("name"),
    supabase.from("locations").select("*").order("name"),
  ]);

  return (
    <>
      <PageHeader
        title="Geofences"
        description="Circular workplace geofences used for automatic check-in and check-out."
      />
      <GeofenceManager
        geofences={(geofences ?? []) as Geofence[]}
        locations={(locations ?? []) as Location[]}
      />
    </>
  );
}
