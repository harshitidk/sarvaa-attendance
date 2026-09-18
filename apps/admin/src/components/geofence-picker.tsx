"use client";

import { hasGoogleMapsKey } from "@/lib/google-maps";
import { GoogleMapPicker } from "@/components/google-map-picker";
import { LeafletMapPicker, type GeofencePoint } from "@/components/leaflet-map-picker";

export type { GeofencePoint };

/**
 * Interactive geofence picker. Uses Google Maps when NEXT_PUBLIC_GOOGLE_MAPS_API_KEY
 * is configured, otherwise a keyless OpenStreetMap/Leaflet map. Either way the
 * admin selects the area visually instead of typing coordinates.
 */
export function GeofencePicker({
  value,
  onChange,
}: {
  value: GeofencePoint;
  onChange: (point: GeofencePoint) => void;
}) {
  return hasGoogleMapsKey() ? (
    <GoogleMapPicker value={value} onChange={onChange} />
  ) : (
    <LeafletMapPicker value={value} onChange={onChange} />
  );
}
