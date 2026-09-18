# Geofenced Employee Attendance

Internal attendance system that records employee attendance based on presence within
company-defined workplace geofences.

- **Employee app** — React Native + Expo (iOS/Android): login, location permissions,
  geofence transition reporting, today status, monthly history.
- **Admin dashboard** — Next.js + TypeScript + Tailwind/shadcn: attendance table,
  employees, geofences, holidays, WFH, manual corrections, audit, CSV export.
- **Backend** — Supabase (Auth + Postgres + RLS + Edge Functions). The OS detects
  geofence transitions; the backend decides whether they create/update attendance.

> The OS handles geofence monitoring. The app never streams continuous location.

## Repository layout

```
apps/
  mobile/        Expo employee app
  admin/         Next.js admin dashboard
packages/
  shared/        Types, enums, constants, pure attendance business rules
supabase/
  migrations/    Schema, RLS, attendance engine
  functions/     process-location-event Edge Function
```

## Prerequisites

- Node >= 20, pnpm 11+
- [Supabase CLI](https://supabase.com/docs/guides/cli) and Docker (for local dev)
- Expo Go or a dev build on a physical device for geofencing tests

## Getting started

```bash
pnpm install

# Configure environment (each app reads its own .env)
cp .env.example .env                       # root (Supabase CLI / reference)
cp apps/admin/.env.example apps/admin/.env.local
cp apps/mobile/.env.example apps/mobile/.env
#   -> fill in the Supabase URL + anon key in both app env files

supabase start                # boots local Postgres + Auth + Studio (needs Docker)
pnpm supabase:reset           # applies migrations + seed
pnpm supabase:types           # regenerate DB types into packages/shared
pnpm dev:admin                # http://localhost:3000
pnpm dev:mobile               # Expo dev server
```

Create the first admin: sign up (or insert) an auth user, then set the role:

```sql
update public.users set role = 'admin', employee_id = 'ADM-0001', name = 'Admin'
 where email = 'admin@example.com';
```


## Core model

At most **one primary attendance record per employee per local business date**.
States: `PRESENT`, `CHECKED_OUT`, `WFH`, `HOLIDAY`, `LEAVE`, `ABSENT`,
`MANUAL_OVERRIDE`. Raw geofence transitions are kept separately in
`location_events` for auditability without continuous tracking.

## Verification

```bash
pnpm -r typecheck     # shared + admin + mobile
pnpm --filter @geo/admin build
```

The attendance state machine (idempotent events, first-check-in-wins, exit grace,
WFH/holiday priority, auditable corrections, absence finalization) is implemented
server-side in `supabase/migrations/0003_attendance_engine.sql` and mirrored as a
pure function in `packages/shared/src/attendance.ts`.

## Stack versions

Expo SDK 52 (React 18) · Next.js 14 (React 18) · Supabase JS v2 · Tailwind CSS 3.

## Recommended build order

1. Schema + RLS + attendance engine (this repo: `supabase/migrations`)
2. Location POC on real iOS/Android devices
3. Employee app
4. Admin dashboard
5. Corrections, audit, export
6. Hardening, device testing, deployment

See `Geofenced_Employee_Attendance_PRD.docx` for the full specification.
