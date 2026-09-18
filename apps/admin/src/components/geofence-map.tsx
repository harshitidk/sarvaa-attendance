"use client";

import { useEffect, useRef, useState } from "react";
import "leaflet/dist/leaflet.css";
import type { Geofence } from "@geo/shared";
import { hasGoogleMapsKey, loadGoogleMaps } from "@/lib/google-maps";

type GeofenceShape = Pick<Geofence, "latitude" | "longitude" | "radius_meters">;

/**
 * Read-only geofence preview. Uses Google Maps when a key is configured,
 * otherwise a keyless Leaflet/OpenStreetMap map. Both draw the radius circle.
 */
export function GeofenceMap({ geofence }: { geofence: GeofenceShape }) {
  const enabled = hasGoogleMapsKey();
  const containerRef = useRef<HTMLDivElement>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (enabled || !containerRef.current) return;
    let cancelled = false;
    let map: any = null;

    (async () => {
      const L = (await import("leaflet")).default;
      if (cancelled || !containerRef.current) return;
      const center: [number, number] = [geofence.latitude, geofence.longitude];
      map = L.map(containerRef.current, {
        center,
        zoom: 16,
        zoomControl: true,
        scrollWheelZoom: false,
        dragging: false,
      });
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        attribution: "&copy; OpenStreetMap contributors",
      }).addTo(map);
      L.circle(center, {
        radius: geofence.radius_meters,
        color: "#2563eb",
        fillColor: "#2563eb",
        fillOpacity: 0.15,
      }).addTo(map);
    })();

    return () => {
      cancelled = true;
      if (map) map.remove();
    };
  }, [enabled, geofence.latitude, geofence.longitude, geofence.radius_meters]);

  useEffect(() => {
    if (!enabled || !containerRef.current) return;
    let cancelled = false;

    loadGoogleMaps()
      .then((google) => {
        if (cancelled || !containerRef.current) return;
        const center = { lat: geofence.latitude, lng: geofence.longitude };
        const map = new google.maps.Map(containerRef.current, {
          center,
          zoom: 16,
          disableDefaultUI: true,
          gestureHandling: "none",
        });
        new google.maps.Marker({ position: center, map });
        new google.maps.Circle({
          map,
          center,
          radius: geofence.radius_meters,
          fillOpacity: 0.15,
          strokeOpacity: 0.8,
          strokeColor: "#2563eb",
          fillColor: "#2563eb",
        });
      })
      .catch(() => setFailed(true));

    return () => {
      cancelled = true;
    };
  }, [enabled, geofence.latitude, geofence.longitude, geofence.radius_meters]);

  return (
    <div className="overflow-hidden rounded-lg border">
      <div ref={containerRef} className="h-56 w-full bg-muted" />
      <div className="flex items-center justify-between border-t bg-muted/40 px-3 py-2 text-xs text-muted-foreground">
        <span className="tabular-nums">
          {geofence.latitude.toFixed(5)}, {geofence.longitude.toFixed(5)}
        </span>
        <span>Radius {geofence.radius_meters} m{failed ? " · map unavailable" : ""}</span>
      </div>
    </div>
  );
}
