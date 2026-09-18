"use client";

import { useEffect, useRef, useState } from "react";
import { LocateFixed } from "lucide-react";
import "leaflet/dist/leaflet.css";
import { Button } from "@/components/ui/button";

export interface GeofencePoint {
  latitude: number;
  longitude: number;
  radius_meters: number;
}

/**
 * Keyless interactive map (OpenStreetMap tiles via Leaflet). Used automatically
 * when no Google Maps API key is configured, so admins can always place a
 * geofence visually: click the map or drag the marker to set the centre.
 */
export function LeafletMapPicker({
  value,
  onChange,
}: {
  value: GeofencePoint;
  onChange: (point: GeofencePoint) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<any>(null);
  const markerRef = useRef<any>(null);
  const circleRef = useRef<any>(null);
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;

  const [ready, setReady] = useState(false);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      const L = (await import("leaflet")).default;
      if (cancelled || !containerRef.current) return;

      const center: [number, number] = [value.latitude, value.longitude];
      const map = L.map(containerRef.current, { center, zoom: 16 });
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        attribution: "&copy; OpenStreetMap contributors",
      }).addTo(map);

      const icon = L.divIcon({
        className: "",
        html: '<span style="display:block;width:14px;height:14px;border-radius:50%;background:#2563eb;border:2px solid #fff;box-shadow:0 0 0 2px #2563eb"></span>',
        iconSize: [14, 14],
        iconAnchor: [7, 7],
      });

      const marker = L.marker(center, { draggable: true, icon }).addTo(map);
      const circle = L.circle(center, {
        radius: value.radius_meters,
        color: "#2563eb",
        fillColor: "#2563eb",
        fillOpacity: 0.15,
      }).addTo(map);

      mapRef.current = map;
      markerRef.current = marker;
      circleRef.current = circle;

      const emit = () => {
        const p = marker.getLatLng();
        onChangeRef.current({
          latitude: p.lat,
          longitude: p.lng,
          radius_meters: Math.round(circle.getRadius()),
        });
      };

      map.on("click", (e: any) => {
        marker.setLatLng(e.latlng);
        circle.setLatLng(e.latlng);
        emit();
      });
      marker.on("dragend", () => {
        const p = marker.getLatLng();
        circle.setLatLng(p);
        emit();
      });

      setReady(true);
    })();

    return () => {
      cancelled = true;
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!ready) return;
    const marker = markerRef.current;
    const circle = circleRef.current;
    const map = mapRef.current;
    if (!marker || !circle || !map) return;
    const p = marker.getLatLng();
    if (p.lat !== value.latitude || p.lng !== value.longitude) {
      const latlng: [number, number] = [value.latitude, value.longitude];
      marker.setLatLng(latlng);
      circle.setLatLng(latlng);
      map.setView(latlng);
    }
    if (Math.round(circle.getRadius()) !== value.radius_meters) {
      circle.setRadius(value.radius_meters);
    }
  }, [value, ready]);

  function useMyLocation() {
    if (!("geolocation" in navigator)) return;
    navigator.geolocation.getCurrentPosition(
      (pos) =>
        onChangeRef.current({
          latitude: pos.coords.latitude,
          longitude: pos.coords.longitude,
          radius_meters: value.radius_meters,
        }),
      (err) => alert(err.message),
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }

  return (
    <div className="space-y-2">
      <div ref={containerRef} className="h-64 w-full rounded-lg border bg-muted" />
      <div className="flex items-center justify-between">
        <Button type="button" variant="outline" size="sm" onClick={useMyLocation}>
          <LocateFixed className="h-3.5 w-3.5" /> Use my location
        </Button>
        <span className="text-xs tabular-nums text-muted-foreground">
          {value.latitude.toFixed(5)}, {value.longitude.toFixed(5)} · {value.radius_meters} m
        </span>
      </div>
      <p className="text-xs text-muted-foreground">
        Click the map or drag the marker to set the centre. Use the radius slider to resize the area.
      </p>
    </div>
  );
}
