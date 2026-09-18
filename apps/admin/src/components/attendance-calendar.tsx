import type { AttendanceStatus } from "@geo/shared";
import { STATUS_LABELS, STATUS_TONE } from "@geo/shared";
import { cn } from "@/lib/utils";

export interface CalendarRecord {
  date: string;
  status: AttendanceStatus;
  check_in_at: string | null;
  check_out_at: string | null;
}

const TONE_CELL: Record<string, string> = {
  positive: "bg-emerald-100 text-emerald-900 border-emerald-200",
  info: "bg-blue-100 text-blue-900 border-blue-200",
  neutral: "bg-slate-100 text-slate-600 border-slate-200",
  warning: "bg-amber-100 text-amber-900 border-amber-200",
};

const TONE_DOT: Record<string, string> = {
  positive: "bg-emerald-500",
  info: "bg-blue-500",
  neutral: "bg-slate-400",
  warning: "bg-amber-500",
};

const WEEKDAYS = ["M", "T", "W", "T", "F", "S", "S"];

export function AttendanceCalendar({
  year,
  month,
  records,
}: {
  year: number;
  month: number; // 1-12
  records: CalendarRecord[];
}) {
  const first = new Date(Date.UTC(year, month - 1, 1));
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const startOffset = (first.getUTCDay() + 6) % 7; // Monday-first

  const byDate = new Map(records.map((r) => [r.date, r]));
  const cells: (CalendarRecord | null)[] = Array.from({ length: startOffset }, () => null);
  for (let day = 1; day <= daysInMonth; day += 1) {
    const key = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
    cells.push(byDate.get(key) ?? null);
  }
  while (cells.length % 7 !== 0) cells.push(null);

  return (
    <div>
      <div className="grid grid-cols-7 gap-1 text-center text-[11px] font-medium text-muted-foreground sm:text-xs">
        {WEEKDAYS.map((d, i) => (
          <div key={`${d}-${i}`} className="py-1">
            {d}
          </div>
        ))}
      </div>
      <div className="mt-1 grid grid-cols-7 gap-1">
        {cells.map((record, index) => {
          const dayNumber =
            index < startOffset ? null : index - startOffset + 1 <= daysInMonth ? index - startOffset + 1 : null;
          if (dayNumber === null) return <div key={index} className="h-12 rounded-md sm:h-16" />;
          const tone = record ? STATUS_TONE[record.status] : null;
          return (
            <div
              key={index}
              title={record ? STATUS_LABELS[record.status] : "No record"}
              className={cn(
                "flex h-12 flex-col items-center rounded-md border p-1 text-center sm:h-16 sm:items-start sm:p-1.5 sm:text-left",
                tone ? TONE_CELL[tone] : "border-border",
              )}
            >
              <span className="text-xs font-medium sm:text-sm">{dayNumber}</span>
              {record ? (
                <>
                  <span
                    className={cn("mt-auto h-2 w-2 rounded-full sm:hidden", TONE_DOT[STATUS_TONE[record.status]])}
                  />
                  <span className="mt-0.5 hidden w-full truncate text-[10px] leading-tight sm:block">
                    {record.status.replace("_", " ")}
                  </span>
                </>
              ) : null}
            </div>
          );
        })}
      </div>
    </div>
  );
}
