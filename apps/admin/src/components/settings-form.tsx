"use client";

import { useState } from "react";
import type { AppSettings } from "@geo/shared";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input, Label } from "@/components/ui/input";

export function SettingsForm({ settings }: { settings: AppSettings }) {
  const [draft, setDraft] = useState({
    company_timezone: settings.company_timezone,
    workday_start: settings.workday_start,
    workday_end: settings.workday_end,
    absence_cutoff: settings.absence_cutoff,
    exit_grace_seconds: String(settings.exit_grace_seconds),
    event_retention_days: String(settings.event_retention_days),
  });
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

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
        absence_cutoff: draft.absence_cutoff,
        exit_grace_seconds: Number(draft.exit_grace_seconds),
        event_retention_days: Number(draft.event_retention_days),
      })
      .eq("id", 1);
    setSaving(false);
    if (saveError) return setError(saveError.message);
    setStatus("Settings saved.");
  }

  async function finalizeAbsences() {
    setError(null);
    setStatus(null);
    const { data, error: rpcError } = await createClient().rpc("finalize_absences", { p_date: null });
    if (rpcError) return setError(rpcError.message);
    setStatus(`Absence finalization complete. ${data ?? 0} record(s) created.`);
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
          <div className="grid grid-cols-3 gap-3">
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
            <div className="space-y-1">
              <Label htmlFor="s-cutoff">Absence cutoff</Label>
              <Input
                id="s-cutoff"
                type="time"
                value={draft.absence_cutoff}
                onChange={(e) => setDraft({ ...draft, absence_cutoff: e.target.value })}
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
          <CardTitle>Attendance operations</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-sm text-muted-foreground">
            Run absence finalization after the cutoff. Employees with no valid attendance and no
            holiday/WFH/leave exception are marked <strong>ABSENT</strong>. Corrections remain possible
            afterward.
          </p>
          <Button variant="outline" onClick={finalizeAbsences}>
            Run absence finalization for today
          </Button>
          <p className="text-xs text-muted-foreground">
            In production, schedule this via a cron job (Supabase scheduled Edge Function).
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
