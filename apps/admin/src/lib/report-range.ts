/**
 * The report ranges offered in the admin Reports view, and the helpers that
 * turn a preset into concrete ISO date bounds.
 */

export type ReportPreset =
  | "thisMonth"
  | "pastMonth"
  | "thisQuarter"
  | "pastQuarter"
  | "past6Months";

export const REPORT_PRESETS: { key: ReportPreset; label: string }[] = [
  { key: "thisMonth", label: "This month" },
  { key: "pastMonth", label: "Past month" },
  { key: "thisQuarter", label: "This quarter" },
  { key: "pastQuarter", label: "Past quarter" },
  { key: "past6Months", label: "Past 6 months" },
];

function iso(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function isReportPreset(value: string | undefined): value is ReportPreset {
  return REPORT_PRESETS.some((p) => p.key === value);
}

/** Inclusive ISO bounds for a preset, anchored on today. */
export function reportRange(preset: ReportPreset, now = new Date()): { from: string; to: string } {
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth();
  const to = iso(now);

  switch (preset) {
    case "thisMonth":
      return { from: iso(new Date(Date.UTC(year, month, 1))), to };
    case "pastMonth":
      return {
        from: iso(new Date(Date.UTC(year, month - 1, 1))),
        to: iso(new Date(Date.UTC(year, month, 0))),
      };
    case "thisQuarter": {
      const start = Math.floor(month / 3) * 3;
      return { from: iso(new Date(Date.UTC(year, start, 1))), to };
    }
    case "pastQuarter": {
      const start = Math.floor(month / 3) * 3;
      return {
        from: iso(new Date(Date.UTC(year, start - 3, 1))),
        to: iso(new Date(Date.UTC(year, start, 0))),
      };
    }
    case "past6Months":
      return { from: iso(new Date(Date.UTC(year, month - 5, 1))), to };
  }
}

/** Local minute-of-day for an instant in the company timezone. */
export function minuteOfDay(instant: string, timezone: string): number {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: timezone,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(new Date(instant));
  const hour = Number(parts.find((p) => p.type === "hour")?.value ?? "0");
  const minute = Number(parts.find((p) => p.type === "minute")?.value ?? "0");
  return hour * 60 + minute;
}

/** Renders minutes past midnight as 12-hour time (e.g. `9:05 AM`). */
export function formatMinuteOfDay(minutes: number): string {
  const hour24 = ((Math.round(minutes / 60) % 24) + 24) % 24;
  const minute = ((Math.round(minutes) % 60) + 60) % 60;
  const period = hour24 < 12 ? "AM" : "PM";
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  return `${hour12}:${minute.toString().padStart(2, "0")} ${period}`;
}
