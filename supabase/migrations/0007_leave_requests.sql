-- ===========================================================================
-- 0007_leave_requests.sql
--
-- Two additions:
--
--   1. leave_requests — an employee asks for a day off (sick / paid / unpaid),
--      an admin decides. Approval materialises a LEAVE attendance row, which is
--      what the absence finalizer already understands. Rejection leaves nothing.
--
--   2. A work-summary edit window. The summary is written at check-out; the
--      employee may revise it for a short while afterwards, then it is frozen.
--      The clock starts when the summary is first stored, and an update never
--      restarts it.
--
-- Both are built around the attendance engine: an approved leave is a `manual`
-- attendance row, so automatic geofence events already refuse to clobber it.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Provenance for the summary edit window
-- ---------------------------------------------------------------------------
alter table public.attendance add column if not exists work_summary_at timestamptz;

-- ---------------------------------------------------------------------------
-- Leave types
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.leave_type as enum ('sick', 'paid', 'unpaid');
exception when duplicate_object then null; end $$;

-- Which request produced an approved LEAVE row (traceability).
alter table public.attendance add column if not exists leave_request_id uuid;

-- ---------------------------------------------------------------------------
-- Employee-initiated leave requests
-- ---------------------------------------------------------------------------
create table if not exists public.leave_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.users (id) on delete cascade,
  date          date not null,
  leave_type    public.leave_type not null,
  reason        text not null check (length(btrim(reason)) >= 3),
  status        text not null default 'pending'
                  check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decision_note text,
  reviewed_by   uuid references public.users (id) on delete set null,
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);

-- At most one live request per person per day; decided ones may pile up.
create unique index if not exists leave_requests_one_open_per_day
  on public.leave_requests (user_id, date)
  where status = 'pending';

create index if not exists leave_requests_status_idx
  on public.leave_requests (status, date desc);

alter table public.leave_requests enable row level security;

-- ---------------------------------------------------------------------------
-- RLS — mirrors wfh_requests: file only for yourself, only a pending request,
-- never in the past; admins see and decide everything.
-- ---------------------------------------------------------------------------
drop policy if exists leave_requests_select on public.leave_requests;
create policy leave_requests_select on public.leave_requests
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists leave_requests_insert_own on public.leave_requests;
create policy leave_requests_insert_own on public.leave_requests
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and date >= (now() at time zone public.app_timezone())::date
  );

drop policy if exists leave_requests_cancel_own on public.leave_requests;
create policy leave_requests_cancel_own on public.leave_requests
  for update to authenticated
  using (user_id = auth.uid() and status = 'pending')
  with check (user_id = auth.uid() and status in ('pending', 'cancelled'));

drop policy if exists leave_requests_admin_write on public.leave_requests;
create policy leave_requests_admin_write on public.leave_requests
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- review_leave_request — the admin decision, and the only path from a request
-- to a real LEAVE day.
-- ---------------------------------------------------------------------------
create or replace function public.review_leave_request(
  p_request_id uuid,
  p_approve    boolean,
  p_note       text default null
)
returns public.leave_requests
language plpgsql security definer set search_path = public as $$
declare
  v_request public.leave_requests;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can review leave requests';
  end if;

  select * into v_request from public.leave_requests where id = p_request_id for update;
  if not found then
    raise exception 'Request not found';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'This request has already been %', v_request.status;
  end if;

  update public.leave_requests
     set status        = case when p_approve then 'approved' else 'rejected' end,
         decision_note = p_note,
         reviewed_by   = auth.uid(),
         reviewed_at   = now()
   where id = p_request_id
   returning * into v_request;

  -- Approval is what the absence finalizer reads. `manual` source also makes
  -- the row immune to later automatic geofence events.
  if p_approve then
    insert into public.attendance (user_id, date, status, source, leave_request_id)
    values (v_request.user_id, v_request.date, 'LEAVE', 'manual', v_request.id)
    on conflict (user_id, date) do update
      set status          = 'LEAVE',
          source          = 'manual',
          leave_request_id = excluded.leave_request_id;
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(),
          case when p_approve then 'leave_request_approved' else 'leave_request_rejected' end,
          'leave_requests', v_request.id,
          jsonb_build_object('user_id', v_request.user_id,
                             'date', v_request.date,
                             'leave_type', v_request.leave_type,
                             'note', p_note));

  return v_request;
end $$;

-- ---------------------------------------------------------------------------
-- employee_check_out — explicit check-out with a mandatory work summary.
-- A later call may revise the summary only within the edit window; the window
-- is measured from the moment the summary was first stored.
-- ---------------------------------------------------------------------------
create or replace function public.employee_check_out(
  p_attendance_id  uuid,
  p_summary        text,
  p_occurred_at    timestamptz default now(),
  p_accuracy_meters double precision default null,
  p_geofence_id    uuid default null
)
returns public.attendance
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_att public.attendance%rowtype;
  v_out timestamptz;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_summary is null or length(trim(p_summary)) < 3 then
    raise exception 'a work summary of at least 3 characters is required to check out'
      using errcode = '22023';
  end if;

  select * into v_att from public.attendance where id = p_attendance_id for update;
  if not found then
    raise exception 'attendance % not found', p_attendance_id using errcode = 'P0002';
  end if;
  if v_att.user_id <> v_uid and not public.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if v_att.check_in_at is null then
    raise exception 'cannot check out without a check-in' using errcode = 'P0001';
  end if;

  -- The summary freezes a short while after it is first written. The owner
  -- cannot extend the window by editing; an admin is not bound by it.
  if v_att.work_summary is not null
     and v_att.work_summary_at is not null
     and v_att.user_id = v_uid
     and not public.is_admin()
     and now() > v_att.work_summary_at + interval '40 minutes'
     and v_att.work_summary is distinct from trim(p_summary) then
    raise exception 'the work summary can no longer be edited'
      using errcode = 'P0001';
  end if;

  v_out := coalesce(v_att.check_out_at, coalesce(p_occurred_at, now()));

  update public.attendance
     set check_out_at = v_out,
         status = 'CHECKED_OUT',
         total_duration_seconds = greatest(0, extract(epoch from (v_out - v_att.check_in_at))::int),
         work_summary = trim(p_summary),
         -- First write starts the clock; later edits do not restart it.
         work_summary_at = case
           when v_att.work_summary is null then now()
           else v_att.work_summary_at
         end
   where id = p_attendance_id
   returning * into v_att;

  insert into public.location_events (
    user_id, geofence_id, event_type, occurred_at, accuracy_meters,
    source, dedupe_key, metadata, processed
  ) values (
    v_uid, p_geofence_id, 'EXIT', v_out, p_accuracy_meters,
    'Browser geolocation',
    md5(concat_ws('|', 'checkout', p_attendance_id, v_out::text)),
    jsonb_build_object('note', 'explicit checkout', 'work_summary', trim(p_summary)),
    true
  )
  on conflict (dedupe_key) do nothing;

  return v_att;
end $$;

revoke all on function public.employee_check_out(
  uuid, text, timestamptz, double precision, uuid) from public, anon;
grant execute on function public.employee_check_out(
  uuid, text, timestamptz, double precision, uuid) to authenticated;

revoke all on function public.review_leave_request(uuid, boolean, text) from public, anon;
grant execute on function public.review_leave_request(uuid, boolean, text) to authenticated;

-- Supabase grants these at bootstrap for tables that exist then; new tables
-- need it spelled out. RLS above is what actually decides.
grant select, insert, update, delete on public.leave_requests to authenticated;
