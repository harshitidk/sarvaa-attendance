"use client";

import { useEffect, useState } from "react";
import { format } from "date-fns";
import { Plus, Trash2 } from "lucide-react";
import type { Holiday, Location, User, WfhAssignment } from "@geo/shared";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input, Label, Select } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

type Employee = Pick<User, "id" | "name" | "employee_id">;

export function CalendarManager({
  holidays,
  wfh,
  locations,
  employees,
}: {
  holidays: Holiday[];
  wfh: WfhAssignment[];
  locations: Location[];
  employees: Employee[];
}) {
  const [error, setError] = useState<string | null>(null);
  const [holidayItems, setHolidayItems] = useState<Holiday[]>(holidays);
  const [wfhItems, setWfhItems] = useState<WfhAssignment[]>(wfh);

  useEffect(() => {
    setHolidayItems(holidays);
  }, [holidays]);
  useEffect(() => {
    setWfhItems(wfh);
  }, [wfh]);

  const [holiday, setHoliday] = useState({ name: "", date: "", location_id: "" });
  const [wfhDraft, setWfhDraft] = useState<{ user_ids: string[]; date: string; reason: string }>({
    user_ids: [],
    date: "",
    reason: "",
  });

  const employeeName = (id: string) => {
    const e = employees.find((x) => x.id === id);
    return e ? `${e.name} (${e.employee_id})` : id;
  };

  async function addHoliday() {
    setError(null);
    if (!holiday.name.trim() || !holiday.date) return setError("Holiday name and date are required.");
    const { data, error: e } = await createClient()
      .from("holidays")
      .insert({
        name: holiday.name.trim(),
        date: holiday.date,
        location_id: holiday.location_id || null,
      })
      .select()
      .single();
    if (e) return setError(e.message);
    setHolidayItems((prev) => [data as Holiday, ...prev]);
    setHoliday({ name: "", date: "", location_id: "" });
  }

  async function deleteHoliday(id: string) {
    const previous = holidayItems;
    setHolidayItems((prev) => prev.filter((h) => h.id !== id));
    const { error: e } = await createClient().from("holidays").delete().eq("id", id);
    if (e) {
      setHolidayItems(previous);
      setError(e.message);
    }
  }

  async function assignWfh() {
    setError(null);
    if (wfhDraft.user_ids.length === 0 || !wfhDraft.date) return setError("Select employees and a date.");
    const rows = wfhDraft.user_ids.map((user_id) => ({
      user_id,
      date: wfhDraft.date,
      reason: wfhDraft.reason.trim() || null,
    }));
    const { data, error: e } = await createClient()
      .from("wfh_assignments")
      .upsert(rows, { onConflict: "user_id,date" })
      .select();
    if (e) return setError(e.message);
    const saved = (data ?? []) as WfhAssignment[];
    setWfhItems((prev) => {
      const byKey = new Map(prev.map((w) => [`${w.user_id}:${w.date}`, w]));
      saved.forEach((w) => byKey.set(`${w.user_id}:${w.date}`, w));
      return Array.from(byKey.values());
    });
    setWfhDraft({ user_ids: [], date: "", reason: "" });
  }

  async function deleteWfh(id: string) {
    const previous = wfhItems;
    setWfhItems((prev) => prev.filter((w) => w.id !== id));
    const { error: e } = await createClient().from("wfh_assignments").delete().eq("id", id);
    if (e) {
      setWfhItems(previous);
      setError(e.message);
    }
  }

  return (
    <div className="space-y-6">
      {error ? <p className="text-sm text-destructive">{error}</p> : null}

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Holidays</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-3">
              <div className="space-y-1 sm:col-span-2">
                <Label htmlFor="h-name">Name</Label>
                <Input
                  id="h-name"
                  value={holiday.name}
                  onChange={(e) => setHoliday({ ...holiday, name: e.target.value })}
                  placeholder="Republic Day"
                />
              </div>
              <div className="space-y-1">
                <Label htmlFor="h-date">Date</Label>
                <Input
                  id="h-date"
                  type="date"
                  value={holiday.date}
                  onChange={(e) => setHoliday({ ...holiday, date: e.target.value })}
                />
              </div>
              <div className="space-y-1 sm:col-span-2">
                <Label htmlFor="h-loc">Scope</Label>
                <Select
                  id="h-loc"
                  value={holiday.location_id}
                  onChange={(e) => setHoliday({ ...holiday, location_id: e.target.value })}
                >
                  <option value="">Company-wide</option>
                  {locations.map((l) => (
                    <option key={l.id} value={l.id}>
                      {l.name}
                    </option>
                  ))}
                </Select>
              </div>
              <div className="flex items-end">
                <Button onClick={addHoliday} className="w-full">
                  <Plus className="h-4 w-4" /> Add
                </Button>
              </div>
            </div>

            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Name</TableHead>
                  <TableHead>Scope</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {holidayItems.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4} className="py-6 text-center text-muted-foreground">
                      No holidays configured.
                    </TableCell>
                  </TableRow>
                ) : (
                  holidayItems.map((h) => (
                    <TableRow key={h.id}>
                      <TableCell className="tabular-nums">{h.date}</TableCell>
                      <TableCell>{h.name}</TableCell>
                      <TableCell>
                        {h.location_id ? locations.find((l) => l.id === h.location_id)?.name ?? "Location" : "Company-wide"}
                      </TableCell>
                      <TableCell className="text-right">
                        <Button variant="ghost" size="sm" onClick={() => deleteHoliday(h.id)}>
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Work from home</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-3">
              <div className="space-y-1 sm:col-span-3">
                <Label htmlFor="w-employees">Employees (multi-select)</Label>
                <select
                  id="w-employees"
                  multiple
                  value={wfhDraft.user_ids}
                  onChange={(e) =>
                    setWfhDraft({
                      ...wfhDraft,
                      user_ids: Array.from(e.target.selectedOptions, (o) => o.value),
                    })
                  }
                  className="h-28 w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm"
                >
                  {employees.map((e) => (
                    <option key={e.id} value={e.id}>
                      {e.name} ({e.employee_id})
                    </option>
                  ))}
                </select>
              </div>
              <div className="space-y-1">
                <Label htmlFor="w-date">Date</Label>
                <Input
                  id="w-date"
                  type="date"
                  value={wfhDraft.date}
                  onChange={(e) => setWfhDraft({ ...wfhDraft, date: e.target.value })}
                />
              </div>
              <div className="space-y-1 sm:col-span-2">
                <Label htmlFor="w-reason">Reason (optional)</Label>
                <Input
                  id="w-reason"
                  value={wfhDraft.reason}
                  onChange={(e) => setWfhDraft({ ...wfhDraft, reason: e.target.value })}
                />
              </div>
              <div className="sm:col-span-3">
                <Button onClick={assignWfh} className="w-full sm:w-auto">
                  <Plus className="h-4 w-4" /> Assign WFH
                </Button>
              </div>
            </div>

            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Employee</TableHead>
                  <TableHead>Reason</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {wfhItems.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4} className="py-6 text-center text-muted-foreground">
                      No WFH assignments.
                    </TableCell>
                  </TableRow>
                ) : (
                  wfhItems.map((w) => (
                    <TableRow key={w.id}>
                      <TableCell className="tabular-nums">{w.date}</TableCell>
                      <TableCell>{employeeName(w.user_id)}</TableCell>
                      <TableCell>{w.reason ?? "—"}</TableCell>
                      <TableCell className="text-right">
                        <Button variant="ghost" size="sm" onClick={() => deleteWfh(w.id)}>
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
