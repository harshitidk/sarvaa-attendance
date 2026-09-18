"use client";

/**
 * Minimal Google Maps JS API loader (no extra dependency).
 * Requires NEXT_PUBLIC_GOOGLE_MAPS_API_KEY with the Maps JavaScript API and
 * Places API enabled. When the key is absent the UI falls back gracefully.
 */

let loaderPromise: Promise<any> | null = null;

export function googleMapsKey(): string | undefined {
  const key = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
  return key && key.trim().length > 0 ? key : undefined;
}

export function hasGoogleMapsKey(): boolean {
  return Boolean(googleMapsKey());
}

export function loadGoogleMaps(): Promise<any> {
  if (typeof window === "undefined") {
    return Promise.reject(new Error("Google Maps can only load in the browser."));
  }
  const w = window as any;
  if (w.google?.maps) return Promise.resolve(w.google);
  if (loaderPromise) return loaderPromise;

  const key = googleMapsKey();
  if (!key) return Promise.reject(new Error("NEXT_PUBLIC_GOOGLE_MAPS_API_KEY is not set."));

  loaderPromise = new Promise((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>("script[data-google-maps]");
    if (existing) {
      existing.addEventListener("load", () => resolve((window as any).google));
      existing.addEventListener("error", () => reject(new Error("Failed to load Google Maps.")));
      return;
    }
    const script = document.createElement("script");
    script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&libraries=places`;
    script.async = true;
    script.defer = true;
    script.dataset.googleMaps = "true";
    script.onload = () => resolve((window as any).google);
    script.onerror = () => reject(new Error("Failed to load Google Maps."));
    document.head.appendChild(script);
  });

  return loaderPromise;
}
