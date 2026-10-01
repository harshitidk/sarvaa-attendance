"use client";

import { useState } from "react";
import type { AppSettings } from "@geo/shared";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input, Label } from "@/components/ui/input";

export function SettingsForm({
  settings,
  attendanceEnabled,
}: {
  settings: AppSettings;
  attendanceEnabled: boolean;
}) {
  const [draft, setDraft] = useState({
    company_timezone: settings.company_timezone,
    workday_start: settings.workday_start,
    workday_end: settings.workday_end,
    exit_grace_seconds: String(settings.exit_grace_seconds),
    event_retention_days: String(settings.event_retention_days),
  });
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [tracking, setTracking] = useState(attendanceEnabled);
  const [trackingBusy, setTrackingBusy] = useState(false);

  async function toggleTracking(next: boolean) {
    setError(null);
    setStatus(null);
    setTrackingBusy(true);
    const { error: rpcError } = await createClient().rpc("set_my_attendance_enabled", {
      p_enabled: next,
    });
    setTrackingBusy(false);
    if (rpcError) return setError(rpcError.message);
    setTracking(next);
    setStatus(next ? "Attendance tracking enabled." : "Attendance tracking disabled.");
  }

  async function save() {
    setError(null);
    setStatus(null);
    setSaving(true);
    const { error: saveError } = await createClient()
      .from("app_settings")
      .update({
        company_timezone: draft.company_timezone,
        workday_start: draft.workday_start,
        workday_end: draft.workday_end,
        exit_grace_seconds: Number(draft.exit_grace_seconds),
        event_retention_days: Number(draft.event_retention_days),
      })
      .eq("id", 1);
    setSaving(false);
    if (saveError) return setError(saveError.message);
    setStatus("Settings saved.");
  }

  return (
    <div className="grid gap-6 lg:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Company rules</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="space-y-1">
            <Label htmlFor="s-tz">Company timezone</Label>
            <Input
              id="s-tz"
              value={draft.company_timezone}
              onChange={(e) => setDraft({ ...draft, company_timezone: e.target.value })}
              placeholder="Asia/Kolkata"
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label htmlFor="s-start">Workday start</Label>
              <Input
                id="s-start"
                type="time"
                value={draft.workday_start}
                onChange={(e) => setDraft({ ...draft, workday_start: e.target.value })}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="s-end">Workday end</Label>
              <Input
                id="s-end"
                type="time"
                value={draft.workday_end}
                onChange={(e) => setDraft({ ...draft, workday_end: e.target.value })}
              />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label htmlFor="s-grace">Exit grace (seconds)</Label>
              <Input
                id="s-grace"
                inputMode="numeric"
                value={draft.exit_grace_seconds}
                onChange={(e) => setDraft({ ...draft, exit_grace_seconds: e.target.value })}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="s-retention">Event retention (days)</Label>
              <Input
                id="s-retention"
                inputMode="numeric"
                value={draft.event_retention_days}
                onChange={(e) => setDraft({ ...draft, event_retention_days: e.target.value })}
              />
            </div>
          </div>
          {error ? <p className="text-sm text-destructive">{error}</p> : null}
          {status ? <p className="text-sm text-emerald-600">{status}</p> : null}
          <Button onClick={save} disabled={saving}>
            {saving ? "Saving…" : "Save settings"}
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>My attendance</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-sm text-muted-foreground">
            Track my own check-ins and check-outs, like the team. Optional — turn it off any
            time. When on, use <strong>My attendance</strong> in the sidebar.
          </p>
          <Button
            variant={tracking ? "outline" : "default"}
            onClick={() => toggleTracking(!tracking)}
            disabled={trackingBusy}
          >
            {trackingBusy
              ? "Saving…"
              : tracking
                ? "Turn off attendance tracking"
                : "Enable attendance tracking"}
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
