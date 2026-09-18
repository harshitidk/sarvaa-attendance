"use client";

import { useEffect, useRef, useState } from "react";
import { LocateFixed, MapPin } from "lucide-react";
import { hasGoogleMapsKey, loadGoogleMaps } from "@/lib/google-maps";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

export interface GeofencePoint {
  latitude: number;
  longitude: number;
  radius_meters: number;
}

/**
 * Interactive Google Map used to place a geofence: search for a place, click or
 * drag the marker, and drag the circle edge to change the radius. Calls onChange
 * with the resulting point. Falls back to a message when no API key is set.
 */
export function GoogleMapPicker({
  value,
  onChange,
}: {
  value: GeofencePoint;
  onChange: (point: GeofencePoint) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  const mapRef = useRef<any>(null);
  const markerRef = useRef<any>(null);
  const circleRef = useRef<any>(null);
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;

  const enabled = hasGoogleMapsKey();
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!enabled || !containerRef.current) return;
    let cancelled = false;

    loadGoogleMaps()
      .then((google) => {
        if (cancelled || !containerRef.current) return;
        const center = { lat: value.latitude, lng: value.longitude };

        const map = new google.maps.Map(containerRef.current, {
          center,
          zoom: 16,
          mapTypeControl: false,
          streetViewControl: false,
          fullscreenControl: false,
        });
        const marker = new google.maps.Marker({ position: center, map, draggable: true });
        const circle = new google.maps.Circle({
          map,
          center,
          radius: value.radius_meters,
          editable: true,
          draggable: false,
          fillOpacity: 0.15,
          strokeOpacity: 0.8,
          strokeColor: "#2563eb",
          fillColor: "#2563eb",
        });

        mapRef.current = map;
        markerRef.current = marker;
        circleRef.current = circle;

        const emit = () => {
          const p = marker.getPosition();
          onChangeRef.current({
            latitude: p.lat(),
            longitude: p.lng(),
            radius_meters: Math.round(circle.getRadius()),
          });
        };

        map.addListener("click", (e: any) => {
          marker.setPosition(e.latLng);
          circle.setCenter(e.latLng);
          emit();
        });
        marker.addListener("dragend", () => {
          const p = marker.getPosition();
          circle.setCenter(p);
          emit();
        });
        circle.addListener("radius_changed", () => emit());
        circle.addListener("center_changed", () => {
          const c = circle.getCenter();
          if (c) {
            marker.setPosition(c);
            emit();
          }
        });

        if (google.maps.places && searchRef.current) {
          const box = new google.maps.places.SearchBox(searchRef.current);
          box.addListener("places_changed", () => {
            const places = box.getPlaces();
            if (!places || places.length === 0) return;
            const location = places[0].geometry?.location;
            if (!location) return;
            map.setCenter(location);
            map.setZoom(17);
            marker.setPosition(location);
            circle.setCenter(location);
            emit();
          });
        }

        setReady(true);
      })
      .catch((e: Error) => setError(e.message));

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled]);

  // Reflect external changes (manual coordinate entry / editing) on the map.
  useEffect(() => {
    if (!ready) return;
    const marker = markerRef.current;
    const circle = circleRef.current;
    const map = mapRef.current;
    if (!marker || !circle || !map) return;
    const current = marker.getPosition();
    if (!current || current.lat() !== value.latitude || current.lng() !== value.longitude) {
      const pos = { lat: value.latitude, lng: value.longitude };
      marker.setPosition(pos);
      circle.setCenter(pos);
      map.setCenter(pos);
    }
    if (Math.round(circle.getRadius()) !== value.radius_meters) {
      circle.setRadius(value.radius_meters);
    }
  }, [value, ready]);

  function useMyLocation() {
    if (!("geolocation" in navigator)) {
      setError("Geolocation is not supported by this browser.");
      return;
    }
    setError(null);
    navigator.geolocation.getCurrentPosition(
      (pos) =>
        onChangeRef.current({
          latitude: pos.coords.latitude,
          longitude: pos.coords.longitude,
          radius_meters: value.radius_meters,
        }),
      (err) => setError(err.message),
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }

  if (!enabled) {
    return (
      <div className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">
        <MapPin className="mb-1 h-4 w-4" />
        Set <code className="font-mono">NEXT_PUBLIC_GOOGLE_MAPS_API_KEY</code> to place the geofence on a
        Google map. You can still enter coordinates manually below.
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <Input ref={searchRef} placeholder="Search a place or address" />
      <div ref={containerRef} className="h-64 w-full rounded-lg border bg-muted" />
      <div className="flex items-center justify-between">
        <Button type="button" variant="outline" size="sm" onClick={useMyLocation}>
          <LocateFixed className="h-3.5 w-3.5" /> Use my location
        </Button>
        <span className="text-xs tabular-nums text-muted-foreground">
          {value.latitude.toFixed(5)}, {value.longitude.toFixed(5)} · {value.radius_meters} m
        </span>
      </div>
      {error ? <p className="text-sm text-destructive">{error}</p> : null}
    </div>
  );
}
