# Test Plan & Standards — Geofenced Attendance

The `app-tester` agent uses this document as its source of truth. Any change
that violates a standard below is a **regression** and must be fixed.

## Commands

| Purpose | Command |
| --- | --- |
| Types | `pnpm -r typecheck` |
| Engine + RLS SQL tests | `pnpm test:engine` |
| Everything | `pnpm test` |
| Production build | `pnpm --filter @geo/admin build` |
| Run production | `pnpm --filter @geo/admin start` |
| Dev | `pnpm --filter @geo/admin dev` |

## Standards (must hold)

1. **Zero type errors** across `packages/shared`, `apps/admin`, `apps/mobile`.
2. **Zero build errors**; `next build` completes and all routes are emitted.
3. **Attendance rules** (verified by `supabase/tests/engine.sql`):
   - first valid ENTER establishes check-in; later ENTERs never overwrite it;
   - duplicate/replayed events are idempotent;
   - EXIT establishes checkout; re-entry within the grace window cancels it;
   - WFH and HOLIDAY exceptions take priority over office attendance;
   - `employee_check_out` requires a non-blank summary, stores it, and never
     moves an existing checkout time;
   - manual corrections preserve old/new values, actor, reason and timestamp;
   - absence is only assigned after the configured cutoff.
4. **Authorization**: an employee can read only their own records; admins can
   read all. Enforced in the database (RLS), not just the UI.
5. **UI latency**: every user action (check-in, check-out, geofence
   create/edit/delete, correction, holiday/WFH) reflects **optimistically and
   immediately** — no `router.refresh()` in a click path. On failure the UI
   rolls back and shows the error.
6. **Time format**: all times render as 12-hour with AM/PM (e.g. `9:05 AM`).
7. **Check-out requires a work summary** (minimum 3 characters).
8. **Failures never fabricate attendance**: a failed/denied GPS read must not
   create or alter an attendance record.
9. **Mobile (360 px)**:
   - no horizontal scrolling;
   - interactive targets at least 44 px tall;
   - the bottom navigation auto-hides on scroll and can be collapsed;
   - safe-area insets respected on notched devices.
10. **Resilience**: every route has an error boundary; async failures surface a
    message and do not leave a stuck loading state.
11. **Secrets**: no service-role key or DB password in client code or the repo;
    only `NEXT_PUBLIC_*` values reach the browser.

## Test matrix

### A. Static
- [ ] `pnpm -r typecheck`
- [ ] `pnpm --filter @geo/admin build`

### B. Engine (SQL)
- [ ] `pnpm test:engine` → "ALL ENGINE TESTS PASSED (21 checks)"

### C. RLS (committed: `supabase/tests/rls.sql`, run by `pnpm test:engine`)
- [ ] admin sees all `users`; employee sees only self
- [ ] employee sees only their assigned geofence(s)
- [ ] cross-employee `attendance` read returns nothing
- [ ] employee cannot call `apply_manual_correction` / `finalize_absences`
- [ ] hosted project: repeat read-only checks against the configured project

### D. Employee flow (browser)
- [ ] login routes to `/employee`
- [ ] location permission prompt appears; denial shows guidance
- [ ] Check in outside the geofence is refused with a distance message
- [ ] Check in inside creates `PRESENT` with a check-in time
- [ ] Check out without a summary is blocked
- [ ] Check out with a summary creates `CHECKED_OUT`, stores the summary
- [ ] times display in AM/PM
- [ ] automatic detection toggles and records only on boundary crossings

### E. Admin flow
- [ ] `/` routes admins to `/dashboard`
- [ ] dashboard counts match the database
- [ ] attendance table shows times in AM/PM and the work summary
- [ ] correction dialog requires a reason and updates the row in place
- [ ] geofences create/edit/delete/activate without a page reload
- [ ] holidays and WFH add/delete without a page reload
- [ ] CSV exports include the work summary
- [ ] audit log records corrections

### F. Security
- [ ] cross-employee `attendance` read returns nothing
- [ ] replayed `record_location_event` (same dedupe key) does not duplicate
- [ ] manipulated `p_attendance_id` in `employee_check_out` is rejected

## Environment constraints
- Docker/Supabase local stack is **not** available. Engine tests run on a
  throwaway local Postgres via `scripts/test-engine.sh`.
- Geolocation requires a secure context: `localhost` or HTTPS
  (`pnpm --filter @geo/admin dev:https`).
- Hosted project credentials live in `.env` / app `.env.local` (gitignored).

## Reporting
Report findings as: **ID · severity (blocker/major/minor) · steps · expected ·
actual · evidence · fix**. Fix blockers and majors in the same run; note minors.
