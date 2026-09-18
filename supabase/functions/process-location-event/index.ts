// Supabase Edge Function: process-location-event
//
// The mobile app POSTs one or more OS geofence transitions here. The function
// runs with the caller's JWT so the SECURITY DEFINER RPC can attribute the
// event to the authenticated employee. Server receipt time is captured here,
// separately from the OS event time.
//
// Deploy: supabase functions deploy process-location-event
// Invoke: POST /functions/v1/process-location-event
//         Authorization: Bearer <user access token>

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

interface IncomingEvent {
  geofence_id: string;
  event_type: "ENTER" | "EXIT";
  occurred_at: string;
  accuracy_meters?: number | null;
  dedupe_key?: string | null;
  metadata?: Record<string, unknown>;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "missing authorization" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  let body: { events?: IncomingEvent[] } & Partial<IncomingEvent>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }

  const events: IncomingEvent[] = body.events ?? (body.geofence_id ? [body as IncomingEvent] : []);
  if (events.length === 0) {
    return json({ error: "no events supplied" }, 400);
  }

  const receivedAt = new Date().toISOString();
  const results: unknown[] = [];

  for (const event of events) {
    if (!event.geofence_id || !event.event_type || !event.occurred_at) {
      results.push({ ok: false, error: "missing required fields", event });
      continue;
    }

    const { data, error } = await supabase.rpc("record_location_event", {
      p_geofence_id: event.geofence_id,
      p_event_type: event.event_type,
      p_occurred_at: event.occurred_at,
      p_received_at: receivedAt,
      p_accuracy_meters: event.accuracy_meters ?? null,
      p_dedupe_key: event.dedupe_key ?? null,
      p_source: "OS geofence",
      p_metadata: event.metadata ?? {},
    });

    if (error) {
      results.push({ ok: false, error: error.message, event });
    } else {
      results.push({ ok: true, attendance: data?.[0] ?? null });
    }
  }

  const anyFailed = results.some((r) => !(r as { ok: boolean }).ok);
  return json({ received_at: receivedAt, results }, anyFailed ? 207 : 200);
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
