"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { format } from "date-fns";
import { CheckCircle2, Crosshair, LogIn, LogOut, MapPin, Play, Square } from "lucide-react";
import type { Attendance, Geofence } from "@geo/shared";
import { STATUS_LABELS, businessDate, distanceMeters, formatDuration } from "@geo/shared";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Label, Select, Textarea } from "@/components/ui/input";
import { StatusBadge } from "@/components/status-badge";

type PermissionState = "granted" | "denied" | "prompt" | "unsupported";

interface Reading {
  lat: number;
  lng: number;
  accuracy: number;
}

export interface RecentEvent {
  id: string;
  event_type: string;
  occurred_at: string;
  accuracy_meters: number | null;
}

export function CheckInPanel({
  geofences,
  attendance,
  recentEvents,
  timezone,
}: {
  geofences: Geofence[];
  attendance: Attendance | null;
  recentEvents: RecentEvent[];
  timezone: string;
}) {
  const [permission, setPermission] = useState<PermissionState>("prompt");
  const [secure, setSecure] = useState(true);
  const [geofenceId, setGeofenceId] = useState<string>(geofences[0]?.id ?? "");
  const [reading, setReading] = useState<Reading | null>(null);
  const [inside, setInside] = useState<boolean | null>(null);
  const [watching, setWatching] = useState(false);
  const [busy, setBusy] = useState(false);
  const [checkoutOpen, setCheckoutOpen] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [record, setRecord] = useState<Attendance | null>(attendance);
  const [events, setEvents] = useState<RecentEvent[]>(recentEvents);

  const watchId = useRef<number | null>(null);
  const lastInside = useRef<boolean | null>(null);
  const today = useMemo(() => businessDate(new Date(), timezone), [timezone]);

  const geofence = useMemo(
    () => geofences.find((g) => g.id === geofenceId) ?? geofences[0] ?? null,
    [geofences, geofenceId],
  );

  useEffect(() => {
    setSecure(window.isSecureContext);
    if (!("geolocation" in navigator)) {
      setPermission("unsupported");
      return;
    }
    if (navigator.permissions?.query) {
      navigator.permissions
        .query({ name: "geolocation" as PermissionName })
        .then((status) => {
          setPermission(status.state as PermissionState);
          status.onchange = () => setPermission(status.state as PermissionState);
        })
        .catch(() => {});
    }
    return () => {
      if (watchId.current !== null) navigator.geolocation.clearWatch(watchId.current);
    };
  }, []);

  const evaluate = useCallback(
    (position: GeolocationPosition) => {
      const { latitude, longitude, accuracy } = position.coords;
      setReading({ lat: latitude, lng: longitude, accuracy });
      if (!geofence) return null;
      const distance = distanceMeters(latitude, longitude, geofence.latitude, geofence.longitude);
      const isInside = distance <= geofence.radius_meters;
      setInside(isInside);
      return { isInside, distance };
    },
    [geofence],
  );

  const recordEvent = useCallback(
    async (eventType: "ENTER" | "EXIT", accuracy: number, note: string, lat: number, lng: number) => {
      if (!geofence) return;
      setError(null);
      const nowIso = new Date().toISOString();
      const previous = record;
      setRecord(applyOptimistic(previous, eventType, nowIso, today));
      setEvents((prev) =>
        [{ id: `local-${nowIso}`, event_type: eventType, occurred_at: nowIso, accuracy_meters: accuracy }, ...prev].slice(0, 8),
      );
      setMessage(`${eventType === "ENTER" ? "Check-in" : "Check-out"} recorded.`);

      const { data, error: rpcError } = await createClient().rpc("record_location_event", {
        p_geofence_id: geofence.id,
        p_event_type: eventType,
        p_occurred_at: nowIso,
        p_accuracy_meters: accuracy,
        p_latitude: lat,
        p_longitude: lng,
        p_dedupe_key: `web:${geofence.id}:${eventType}:${crypto.randomUUID()}`,
        p_source: "Browser geolocation",
        p_metadata: { platform: "web", note },
      });

      if (rpcError) {
        setRecord(previous);
        setError(rpcError.message);
        setMessage(null);
        return;
      }
      const row = (data as { status: Attendance["status"]; check_in_at: string | null; check_out_at: string | null; business_date: string; attendance_id: string | null }[] | null)?.[0];
      if (row) setRecord(fromRpc(previous, row, nowIso));
    },
    [geofence, record, today],
  );

  const checkIn = useCallback(() => {
    if (!geofence) return;
    setError(null);
    setMessage(null);
    setBusy(true);
    navigator.geolocation.getCurrentPosition(
      async (position) => {
        const result = evaluate(position);
        if (!result) {
          setBusy(false);
          return;
        }
        if (!result.isInside) {
          setError(`You are about ${Math.round(result.distance)} m from ${geofence.name}. Move inside to check in.`);
          setBusy(false);
          return;
        }
        await recordEvent("ENTER", position.coords.accuracy, "explicit check-in", position.coords.latitude, position.coords.longitude);
        setBusy(false);
      },
      (err) => {
        setError(err.message);
        setBusy(false);
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  }, [geofence, evaluate, recordEvent]);

  const locate = useCallback(() => {
    setError(null);
    setBusy(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        evaluate(position);
        setBusy(false);
      },
      (err) => {
        setError(err.message);
        setBusy(false);
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  }, [evaluate]);

  const submitCheckout = useCallback(
    async (summary: string) => {
      if (!record?.id) {
        setError("Check in before checking out.");
        setCheckoutOpen(false);
        return;
      }
      setCheckoutOpen(false);
      setError(null);
      const previous = record;
      const nowIso = new Date().toISOString();
      setRecord(applyOptimistic(previous, "EXIT", nowIso, today, summary));
      setMessage("Check-out recorded.");

      const { data, error: rpcError } = await createClient().rpc("employee_check_out", {
        p_attendance_id: record.id,
        p_summary: summary,
        p_occurred_at: nowIso,
        p_accuracy_meters: reading?.accuracy ?? null,
        p_geofence_id: geofence?.id ?? null,
      });

      if (rpcError) {
        setRecord(previous);
        setError(rpcError.message);
        setMessage(null);
        return;
      }
      const row = (Array.isArray(data) ? data[0] : data) as Attendance | null;
      if (row) setRecord(row);
    },
    [record, reading, geofence, today],
  );

  function startWatching() {
    if (!geofence || !("geolocation" in navigator)) return;
    setError(null);
    setMessage(null);
    lastInside.current = inside;
    const id = navigator.geolocation.watchPosition(
      async (position) => {
        const result = evaluate(position);
        if (!result) return;
        if (lastInside.current === null) {
          lastInside.current = result.isInside;
          return;
        }
        if (result.isInside !== lastInside.current) {
          lastInside.current = result.isInside;
          await recordEvent(result.isInside ? "ENTER" : "EXIT", position.coords.accuracy, "auto transition", position.coords.latitude, position.coords.longitude);
        }
      },
      (err) => {
        setError(err.message);
        setWatching(false);
      },
      { enableHighAccuracy: true, timeout: 20000, maximumAge: 5000 },
    );
    watchId.current = id;
    setWatching(true);
  }

  function stopWatching() {
    if (watchId.current !== null) navigator.geolocation.clearWatch(watchId.current);
    watchId.current = null;
    setWatching(false);
  }

  const distance =
    reading && geofence ? distanceMeters(reading.lat, reading.lng, geofence.latitude, geofence.longitude) : null;

  const checkedIn = Boolean(record?.check_in_at);
  const checkedOut = Boolean(record?.check_out_at);

  return (
    <div className="space-y-4">
      {!secure ? (
        <Card className="border-amber-300 bg-amber-50">
          <CardContent className="p-4 text-sm text-amber-900">
            Browser location requires a secure context. Use <code>localhost</code> or HTTPS.
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <CardTitle>Today</CardTitle>
          {record ? <StatusBadge status={record.status} /> : null}
        </CardHeader>
        <CardContent className="space-y-4">
          {geofences.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No geofence is assigned to your account. Ask an administrator to configure your office.
            </p>
          ) : (
            <>
              {geofences.length > 1 ? (
                <div className="space-y-1">
                  <span className="text-sm text-muted-foreground">Geofence</span>
                  <Select value={geofenceId} onChange={(e) => setGeofenceId(e.target.value)}>
                    {geofences.map((g) => (
                      <option key={g.id} value={g.id}>
                        {g.name}
                      </option>
                    ))}
                  </Select>
                </div>
              ) : null}

              <div className="grid grid-cols-3 gap-2">
                <Metric
                  label="Position"
                  value={inside === null ? "—" : inside ? "Inside" : "Outside"}
                  tone={inside === null ? "muted" : inside ? "positive" : "warning"}
                />
                <Metric label="Distance" value={distance === null ? "—" : `${Math.round(distance)} m`} hint={geofence ? `radius ${geofence.radius_meters} m` : undefined} />
                <Metric label="Accuracy" value={reading ? `±${Math.round(reading.accuracy)} m` : "—"} />
              </div>

              <div className="flex flex-col gap-2">
                {!checkedIn ? (
                  <Button className="h-12 w-full text-base" onClick={checkIn} disabled={busy}>
                    <LogIn className="h-4 w-4" />
                    {busy ? "Checking location…" : "Check in"}
                  </Button>
                ) : !checkedOut ? (
                  <Button className="h-12 w-full text-base" onClick={() => setCheckoutOpen(true)}>
                    <LogOut className="h-4 w-4" /> Check out
                  </Button>
                ) : (
                  <Button variant="outline" className="h-12 w-full text-base" onClick={() => setCheckoutOpen(true)}>
                    <CheckCircle2 className="h-4 w-4" /> Update work summary
                  </Button>
                )}

                <div className="flex flex-col gap-2 sm:flex-row">
                  <Button variant="outline" className="h-11 w-full sm:w-auto" onClick={locate} disabled={busy || watching}>
                    <Crosshair className="h-4 w-4" /> Locate me
                  </Button>
                  {watching ? (
                    <Button variant="outline" className="h-11 w-full sm:w-auto" onClick={stopWatching}>
                      <Square className="h-4 w-4" /> Stop automatic detection
                    </Button>
                  ) : (
                    <Button variant="outline" className="h-11 w-full sm:w-auto" onClick={startWatching} disabled={busy}>
                      <Play className="h-4 w-4" /> Start automatic detection
                    </Button>
                  )}
                </div>
              </div>

              {permission === "denied" ? (
                <p className="flex items-center gap-2 text-xs text-muted-foreground">
                  <MapPin className="h-3.5 w-3.5" />
                  Location is blocked. Enable it for this site in your browser settings.
                </p>
              ) : null}

              {message ? <p className="text-sm text-emerald-600">{message}</p> : null}
              {error ? <p className="text-sm text-destructive">{error}</p> : null}
            </>
          )}
        </CardContent>
      </Card>

      <div className="grid grid-cols-3 gap-2 sm:gap-4">
        <SummaryTile label="Check-in" value={record?.check_in_at ? format(new Date(record.check_in_at), "h:mm a") : "—"} />
        <SummaryTile label="Check-out" value={record?.check_out_at ? format(new Date(record.check_out_at), "h:mm a") : "—"} />
        <SummaryTile label="Duration" value={formatDuration(record?.total_duration_seconds)} />
      </div>

      {record?.work_summary ? (
        <Card>
          <CardHeader>
            <CardTitle>Work summary</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="whitespace-pre-wrap text-sm">{record.work_summary}</p>
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>Recent location events</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {events.length === 0 ? (
            <p className="text-sm text-muted-foreground">No events recorded yet.</p>
          ) : (
            events.map((event) => (
              <div key={event.id} className="flex items-center justify-between border-b pb-2 text-sm last:border-0">
                <span className="font-medium">{event.event_type}</span>
                <span className="tabular-nums text-muted-foreground">
                  {format(new Date(event.occurred_at), "d MMM h:mm a")}
                  {event.accuracy_meters ? ` · ±${Math.round(event.accuracy_meters)}m` : ""}
                </span>
              </div>
            ))
          )}
        </CardContent>
      </Card>

      {checkoutOpen ? (
        <CheckoutDialog
          initialSummary={record?.work_summary ?? ""}
          onClose={() => setCheckoutOpen(false)}
          onSubmit={submitCheckout}
        />
      ) : null}
    </div>
  );
}

function CheckoutDialog({
  initialSummary,
  onClose,
  onSubmit,
}: {
  initialSummary: string;
  onClose: () => void;
  onSubmit: (summary: string) => void;
}) {
  const [summary, setSummary] = useState(initialSummary);
  const [error, setError] = useState<string | null>(null);

  function submit() {
    if (summary.trim().length < 3) {
      setError("Please describe what you worked on today.");
      return;
    }
    onSubmit(summary.trim());
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-0 sm:items-center sm:p-4">
      <div className="w-full max-w-md rounded-t-2xl border bg-card p-5 shadow-lg sm:rounded-lg sm:p-6">
        <h3 className="text-lg font-semibold">Check out</h3>
        <p className="mt-1 text-sm text-muted-foreground">
          Tell us what you worked on today. This is required to check out.
        </p>
        <div className="mt-4 space-y-1">
          <Label htmlFor="work-summary">Work summary</Label>
          <Textarea
            id="work-summary"
            autoFocus
            placeholder="e.g. Completed the attendance API, reviewed 2 PRs, attended standup."
            value={summary}
            onChange={(e) => setSummary(e.target.value)}
            className="min-h-[120px]"
          />
        </div>
        {error ? <p className="mt-2 text-sm text-destructive">{error}</p> : null}
        <div className="mt-5 flex justify-end gap-2">
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={submit}>Confirm check-out</Button>
        </div>
      </div>
    </div>
  );
}

function fromRpc(
  previous: Attendance | null,
  row: { status: Attendance["status"]; check_in_at: string | null; check_out_at: string | null; business_date: string; attendance_id: string | null },
  at: string,
): Attendance {
  return {
    id: row.attendance_id ?? previous?.id ?? "",
    user_id: previous?.user_id ?? "",
    date: row.business_date,
    status: row.status,
    check_in_at: row.check_in_at,
    check_out_at: row.check_out_at,
    total_duration_seconds:
      row.check_in_at && row.check_out_at
        ? Math.max(0, Math.round((new Date(row.check_out_at).getTime() - new Date(row.check_in_at).getTime()) / 1000))
        : null,
    work_summary: previous?.work_summary ?? null,
    source: previous?.source ?? "automatic",
    created_at: previous?.created_at ?? at,
    updated_at: at,
  };
}

function applyOptimistic(
  previous: Attendance | null,
  eventType: "ENTER" | "EXIT",
  at: string,
  date: string,
  summary?: string,
): Attendance {
  const base: Attendance = previous ?? {
    id: "",
    user_id: "",
    date,
    status: "PRESENT",
    check_in_at: null,
    check_out_at: null,
    total_duration_seconds: null,
    work_summary: null,
    source: "automatic",
    created_at: at,
    updated_at: at,
  };

  if (eventType === "ENTER") {
    return {
      ...base,
      status: "PRESENT",
      check_in_at: base.check_in_at ?? at,
      check_out_at: null,
      total_duration_seconds: null,
    };
  }

  if (!base.check_in_at) return base;
  return {
    ...base,
    status: "CHECKED_OUT",
    check_out_at: base.check_out_at ?? at,
    total_duration_seconds: Math.max(
      0,
      Math.round((new Date(base.check_out_at ?? at).getTime() - new Date(base.check_in_at).getTime()) / 1000),
    ),
    work_summary: summary ?? base.work_summary,
  };
}

function SummaryTile({ label, value }: { label: string; value: string }) {
  return (
    <Card>
      <CardContent className="p-3 sm:p-4">
        <p className="text-[11px] text-muted-foreground sm:text-sm">{label}</p>
        <p className="mt-0.5 text-base font-semibold tabular-nums sm:text-xl">{value}</p>
      </CardContent>
    </Card>
  );
}

function Metric({
  label,
  value,
  hint,
  tone = "muted",
}: {
  label: string;
  value: string;
  hint?: string;
  tone?: "muted" | "positive" | "warning";
}) {
  const toneClass = tone === "positive" ? "text-emerald-600" : tone === "warning" ? "text-amber-600" : "text-foreground";
  return (
    <div className="rounded-lg border p-2.5">
      <p className="text-[11px] text-muted-foreground sm:text-xs">{label}</p>
      <p className={`mt-0.5 text-sm font-semibold sm:text-base ${toneClass}`}>{value}</p>
      {hint ? <p className="truncate text-[10px] text-muted-foreground sm:text-xs">{hint}</p> : null}
    </div>
  );
}
