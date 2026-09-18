"use client";

import { useEffect, useState } from "react";
import { MapPin, Pencil, Trash2 } from "lucide-react";
import type { Geofence, Location } from "@geo/shared";
import { GEOFENCE_RADIUS_DEFAULT_METERS } from "@geo/shared";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input, Label, Select } from "@/components/ui/input";
import { GeofenceMap } from "@/components/geofence-map";
import { GeofencePicker } from "@/components/geofence-picker";

interface Draft {
  id?: string;
  name: string;
  latitude: string;
  longitude: string;
  radius_meters: string;
  location_id: string;
  active: boolean;
}

const EMPTY: Draft = {
  name: "",
  latitude: "28.63040",
  longitude: "77.21770",
  radius_meters: String(GEOFENCE_RADIUS_DEFAULT_METERS),
  location_id: "",
  active: true,
};

export function GeofenceManager({
  geofences,
  locations,
}: {
  geofences: Geofence[];
  locations: Location[];
}) {
  const [draft, setDraft] = useState<Draft>(EMPTY);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<Geofence[]>(geofences);

  useEffect(() => {
    setItems(geofences);
  }, [geofences]);

  async function save() {
    setError(null);
    const lat = Number(draft.latitude);
    const lng = Number(draft.longitude);
    const radius = Number(draft.radius_meters);
    if (!draft.name.trim()) return setError("Name is required.");
    if (!Number.isFinite(lat) || lat < -90 || lat > 90) return setError("Latitude must be between -90 and 90.");
    if (!Number.isFinite(lng) || lng < -180 || lng > 180) return setError("Longitude must be between -180 and 180.");
    if (!Number.isFinite(radius) || radius < 25 || radius > 5000)
      return setError("Radius must be between 25 and 5000 metres.");

    setSaving(true);
    const supabase = createClient();
    const payload = {
      name: draft.name.trim(),
      latitude: lat,
      longitude: lng,
      radius_meters: Math.round(radius),
      location_id: draft.location_id || null,
      active: draft.active,
    };
    const query = draft.id
      ? supabase.from("geofences").update(payload).eq("id", draft.id).select().single()
      : supabase.from("geofences").insert(payload).select().single();
    const { data, error: saveError } = await query;
    setSaving(false);
    if (saveError) return setError(saveError.message);

    const saved = data as Geofence;
    setItems((prev) =>
      draft.id
        ? prev.map((g) => (g.id === saved.id ? saved : g))
        : [...prev, saved].sort((a, b) => a.name.localeCompare(b.name)),
    );
    setDraft(EMPTY);
  }

  async function remove(id: string) {
    if (!confirm("Delete this geofence? Existing location events keep their history.")) return;
    const previous = items;
    setItems((prev) => prev.filter((g) => g.id !== id));
    const { error: deleteError } = await createClient().from("geofences").delete().eq("id", id);
    if (deleteError) {
      setItems(previous);
      setError(deleteError.message);
    }
  }

  async function toggleActive(geofence: Geofence) {
    setItems((prev) =>
      prev.map((g) => (g.id === geofence.id ? { ...g, active: !g.active } : g)),
    );
    const { error: toggleError } = await createClient()
      .from("geofences")
      .update({ active: !geofence.active })
      .eq("id", geofence.id);
    if (toggleError) {
      setItems((prev) => prev.map((g) => (g.id === geofence.id ? geofence : g)));
      setError(toggleError.message);
    }
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[380px_1fr]">
      <Card className="h-fit">
        <CardHeader>
          <CardTitle>{draft.id ? "Edit geofence" : "New geofence"}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="space-y-1">
            <Label htmlFor="gf-name">Name</Label>
            <Input id="gf-name" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
          </div>

          <GeofencePicker
            value={{
              latitude: Number(draft.latitude) || 0,
              longitude: Number(draft.longitude) || 0,
              radius_meters: Number(draft.radius_meters) || GEOFENCE_RADIUS_DEFAULT_METERS,
            }}
            onChange={(point) =>
              setDraft((prev) => ({
                ...prev,
                latitude: point.latitude.toFixed(5),
                longitude: point.longitude.toFixed(5),
                radius_meters: String(point.radius_meters),
              }))
            }
          />

          <div className="space-y-1">
            <div className="flex items-center justify-between">
              <Label htmlFor="gf-radius">Radius</Label>
              <span className="text-sm tabular-nums text-muted-foreground">{draft.radius_meters} m</span>
            </div>
            <input
              id="gf-radius"
              type="range"
              min={25}
              max={1000}
              step={5}
              value={Number(draft.radius_meters) || GEOFENCE_RADIUS_DEFAULT_METERS}
              onChange={(e) => setDraft({ ...draft, radius_meters: e.target.value })}
              className="w-full accent-primary"
            />
          </div>

          <div className="space-y-1">
            <Label htmlFor="gf-location">Office</Label>
            <Select
              id="gf-location"
              value={draft.location_id}
              onChange={(e) => setDraft({ ...draft, location_id: e.target.value })}
            >
              <option value="">Company-wide</option>
              {locations.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.name}
                </option>
              ))}
            </Select>
          </div>

          <details className="rounded-md border p-3">
            <summary className="cursor-pointer text-sm text-muted-foreground">
              Advanced: exact coordinates
            </summary>
            <div className="mt-3 grid grid-cols-3 gap-3">
              <div className="space-y-1">
                <Label htmlFor="gf-lat">Latitude</Label>
                <Input
                  id="gf-lat"
                  inputMode="decimal"
                  value={draft.latitude}
                  onChange={(e) => setDraft({ ...draft, latitude: e.target.value })}
                />
              </div>
              <div className="space-y-1">
                <Label htmlFor="gf-lng">Longitude</Label>
                <Input
                  id="gf-lng"
                  inputMode="decimal"
                  value={draft.longitude}
                  onChange={(e) => setDraft({ ...draft, longitude: e.target.value })}
                />
              </div>
              <div className="space-y-1">
                <Label htmlFor="gf-radius-num">Radius (m)</Label>
                <Input
                  id="gf-radius-num"
                  inputMode="numeric"
                  value={draft.radius_meters}
                  onChange={(e) => setDraft({ ...draft, radius_meters: e.target.value })}
                />
              </div>
            </div>
          </details>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={draft.active}
              onChange={(e) => setDraft({ ...draft, active: e.target.checked })}
            />
            Active
          </label>
          {error ? <p className="text-sm text-destructive">{error}</p> : null}
          <div className="flex gap-2">
            <Button onClick={save} disabled={saving}>
              {draft.id ? "Save changes" : "Create geofence"}
            </Button>
            {draft.id ? (
              <Button variant="outline" onClick={() => setDraft(EMPTY)}>
                Cancel
              </Button>
            ) : null}
          </div>
          <p className="text-xs text-muted-foreground">
            Prototype radius range is 100–300 m; validate the correct value at the real workplace.
          </p>
        </CardContent>
      </Card>

      <div className="space-y-4">
        {items.length === 0 ? (
          <Card>
            <CardContent className="py-12 text-center text-sm text-muted-foreground">
              <MapPin className="mx-auto mb-2 h-6 w-6" />
              No geofences configured.
            </CardContent>
          </Card>
        ) : (
          items.map((geofence) => (
            <Card key={geofence.id}>
              <CardContent className="grid gap-4 p-4 sm:grid-cols-[1fr_240px]">
                <div>
                  <div className="flex items-center gap-2">
                    <h3 className="font-medium">{geofence.name}</h3>
                    <Badge tone={geofence.active ? "positive" : "neutral"}>
                      {geofence.active ? "active" : "inactive"}
                    </Badge>
                  </div>
                  <p className="mt-1 text-sm tabular-nums text-muted-foreground">
                    {geofence.latitude.toFixed(5)}, {geofence.longitude.toFixed(5)} · {geofence.radius_meters} m
                  </p>
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() =>
                        setDraft({
                          id: geofence.id,
                          name: geofence.name,
                          latitude: String(geofence.latitude),
                          longitude: String(geofence.longitude),
                          radius_meters: String(geofence.radius_meters),
                          location_id: geofence.location_id ?? "",
                          active: geofence.active,
                        })
                      }
                    >
                      <Pencil className="h-3.5 w-3.5" /> Edit
                    </Button>
                    <Button variant="outline" size="sm" onClick={() => toggleActive(geofence)}>
                      {geofence.active ? "Deactivate" : "Activate"}
                    </Button>
                    <Button variant="destructive" size="sm" onClick={() => remove(geofence.id)}>
                      <Trash2 className="h-3.5 w-3.5" /> Delete
                    </Button>
                  </div>
                </div>
                <GeofenceMap geofence={geofence} />
              </CardContent>
            </Card>
          ))
        )}
      </div>
    </div>
  );
}
