"use client";

import { useEffect, useMemo, useState } from "react";
import { format } from "date-fns";
import { Pencil, Search } from "lucide-react";
import type { Attendance, AttendanceStatus, User } from "@geo/shared";
import { ATTENDANCE_STATUSES, STATUS_LABELS, formatDuration } from "@geo/shared";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input, Label, Select, Textarea } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { StatusBadge } from "@/components/status-badge";

export type AttendanceRow = Attendance & {
  user: Pick<User, "name" | "employee_id" | "department"> | null;
};

function time(value: string | null) {
  return value ? format(new Date(value), "h:mm a") : "—";
}

export function AttendanceTable({ rows }: { rows: AttendanceRow[] }) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<"all" | AttendanceStatus>("all");
  const [editing, setEditing] = useState<AttendanceRow | null>(null);
  const [rowsState, setRowsState] = useState<AttendanceRow[]>(rows);

  useEffect(() => {
    setRowsState(rows);
  }, [rows]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return rowsState.filter((row) => {
      const matchesQuery =
        q.length === 0 ||
        row.user?.name.toLowerCase().includes(q) ||
        row.user?.employee_id.toLowerCase().includes(q) ||
        (row.user?.department ?? "").toLowerCase().includes(q);
      const matchesStatus = status === "all" || row.status === status;
      return matchesQuery && matchesStatus;
    });
  }, [rowsState, query, status]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative w-full max-w-sm">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search name, ID or department"
            className="pl-8"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <Select
          className="w-44"
          value={status}
          onChange={(e) => setStatus(e.target.value as typeof status)}
        >
          <option value="all">All statuses</option>
          {ATTENDANCE_STATUSES.map((s) => (
            <option key={s} value={s}>
              {STATUS_LABELS[s]}
            </option>
          ))}
        </Select>
        <span className="text-sm text-muted-foreground">{filtered.length} records</span>
      </div>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Employee</TableHead>
              <TableHead>Department</TableHead>
              <TableHead>Date</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Check-in</TableHead>
              <TableHead>Check-out</TableHead>
              <TableHead>Duration</TableHead>
              <TableHead>Summary</TableHead>
              <TableHead>Source</TableHead>
              <TableHead className="text-right">Action</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 ? (
              <TableRow>
                <TableCell colSpan={10} className="py-10 text-center text-muted-foreground">
                  No attendance records.
                </TableCell>
              </TableRow>
            ) : (
              filtered.map((row) => (
                <TableRow key={row.id}>
                  <TableCell>
                    <div className="font-medium">{row.user?.name ?? "Unknown"}</div>
                    <div className="text-xs text-muted-foreground">{row.user?.employee_id}</div>
                  </TableCell>
                  <TableCell>{row.user?.department ?? "—"}</TableCell>
                  <TableCell>{row.date}</TableCell>
                  <TableCell>
                    <StatusBadge status={row.status} />
                  </TableCell>
                  <TableCell className="tabular-nums">{time(row.check_in_at)}</TableCell>
                  <TableCell className="tabular-nums">{time(row.check_out_at)}</TableCell>
                  <TableCell className="tabular-nums">
                    {formatDuration(row.total_duration_seconds)}
                  </TableCell>
                  <TableCell className="max-w-[220px] truncate text-muted-foreground" title={row.work_summary ?? ""}>
                    {row.work_summary ?? "—"}
                  </TableCell>
                  <TableCell className="capitalize">{row.source}</TableCell>
                  <TableCell className="text-right">
                    <Button variant="outline" size="sm" onClick={() => setEditing(row)}>
                      <Pencil className="h-3.5 w-3.5" /> Correct
                    </Button>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>

      {editing ? (
        <CorrectionDialog
          row={editing}
          onClose={() => setEditing(null)}
          onSaved={(updated) => {
            setRowsState((prev) =>
              prev.map((r) => (r.id === updated.id ? { ...r, ...updated, user: r.user } : r)),
            );
            setEditing(null);
          }}
        />
      ) : null}
    </div>
  );
}

function toLocalInput(value: string | null): string {
  if (!value) return "";
  const d = new Date(value);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(
    d.getMinutes(),
  )}`;
}

function CorrectionDialog({
  row,
  onClose,
  onSaved,
}: {
  row: AttendanceRow;
  onClose: () => void;
  onSaved: (updated: Attendance) => void;
}) {
  const [status, setStatus] = useState<AttendanceStatus>(row.status);
  const [checkIn, setCheckIn] = useState(toLocalInput(row.check_in_at));
  const [checkOut, setCheckOut] = useState(toLocalInput(row.check_out_at));
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setError(null);
    if (!reason.trim()) {
      setError("A reason is required for every correction.");
      return;
    }
    setSaving(true);
    const { data, error: rpcError } = await createClient().rpc("apply_manual_correction", {
      p_attendance_id: row.id,
      p_new_status: status,
      p_check_in_at: checkIn ? new Date(checkIn).toISOString() : null,
      p_check_out_at: checkOut ? new Date(checkOut).toISOString() : null,
      p_reason: reason.trim(),
    });
    setSaving(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }
    const updated = (Array.isArray(data) ? data[0] : data) as Attendance | null;
    if (updated) onSaved(updated);
    else onClose();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
      <div className="w-full max-w-md rounded-lg border bg-card p-6 shadow-lg">
        <h3 className="text-lg font-semibold">Correct attendance</h3>
        <p className="mt-1 text-sm text-muted-foreground">
          {row.user?.name} · {row.date}. The previous values are preserved in the audit trail.
        </p>

        <div className="mt-4 space-y-3">
          <div className="space-y-1">
            <Label htmlFor="correction-status">Status</Label>
            <Select
              id="correction-status"
              value={status}
              onChange={(e) => setStatus(e.target.value as AttendanceStatus)}
            >
              {ATTENDANCE_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {STATUS_LABELS[s]}
                </option>
              ))}
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label htmlFor="correction-in">Check-in</Label>
              <Input
                id="correction-in"
                type="datetime-local"
                value={checkIn}
                onChange={(e) => setCheckIn(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="correction-out">Check-out</Label>
              <Input
                id="correction-out"
                type="datetime-local"
                value={checkOut}
                onChange={(e) => setCheckOut(e.target.value)}
              />
            </div>
          </div>
          <div className="space-y-1">
            <Label htmlFor="correction-reason">Reason</Label>
            <Textarea
              id="correction-reason"
              placeholder="e.g. GPS event missed; employee confirmed on-site"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </div>
          {error ? <p className="text-sm text-destructive">{error}</p> : null}
        </div>

        <div className="mt-6 flex justify-end gap-2">
          <Button variant="outline" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Saving…" : "Save correction"}
          </Button>
        </div>
      </div>
    </div>
  );
}
