-- ===========================================================================
-- 0006_wfh_requests.sql
--
-- Two additions, both deliberately built *around* the attendance engine
-- rather than inside it:
--
--   1. wfh_requests    — an employee asks for a WFH day; an admin decides.
--   2. company_wfh_days — an admin marks a date as WFH for everyone.
--
-- The engine in 0003 treats any `wfh_assignments` row as WFH. Instead of
-- teaching it two new concepts (and re-validating its 22 checks), approval
-- and company days *materialise* rows into `wfh_assignments`. The engine is
-- unchanged and keeps working exactly as tested.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Provenance on wfh_assignments, so materialised rows can be withdrawn again
-- ---------------------------------------------------------------------------
alter table public.wfh_assignments
  add column if not exists company_day_id uuid,
  add column if not exists request_id     uuid;

-- ---------------------------------------------------------------------------
-- Company-wide WFH days
-- ---------------------------------------------------------------------------
create table if not exists public.company_wfh_days (
  id          uuid primary key default gen_random_uuid(),
  date        date not null,
  note        text,
  location_id uuid references public.locations (id) on delete cascade,
  created_by  uuid references public.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (date, location_id)
);

create index if not exists company_wfh_days_date_idx
  on public.company_wfh_days (date);

-- ---------------------------------------------------------------------------
-- Employee-initiated WFH requests
-- ---------------------------------------------------------------------------
create table if not exists public.wfh_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.users (id) on delete cascade,
  date          date not null,
  reason        text,
  status        text not null default 'pending'
                  check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decision_note text,
  reviewed_by   uuid references public.users (id) on delete set null,
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);

-- At most one live request per person per day; decided ones may pile up.
create unique index if not exists wfh_requests_one_open_per_day
  on public.wfh_requests (user_id, date)
  where status = 'pending';

create index if not exists wfh_requests_status_idx
  on public.wfh_requests (status, date desc);

alter table public.company_wfh_days enable row level security;
alter table public.wfh_requests     enable row level security;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

-- Everyone may see which dates are company WFH days; only admins set them.
drop policy if exists company_wfh_select on public.company_wfh_days;
create policy company_wfh_select on public.company_wfh_days
  for select to authenticated using (true);

drop policy if exists company_wfh_admin_write on public.company_wfh_days;
create policy company_wfh_admin_write on public.company_wfh_days
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Employees see their own requests; admins see all.
drop policy if exists wfh_requests_select on public.wfh_requests;
create policy wfh_requests_select on public.wfh_requests
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- Employees may only ever file a *pending* request, for themselves, for a
-- date that is not in the past. Approving is not something they can do.
drop policy if exists wfh_requests_insert_own on public.wfh_requests;
create policy wfh_requests_insert_own on public.wfh_requests
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and date >= (now() at time zone public.app_timezone())::date
  );

-- An employee may withdraw their own request while it is still pending.
drop policy if exists wfh_requests_cancel_own on public.wfh_requests;
create policy wfh_requests_cancel_own on public.wfh_requests
  for update to authenticated
  using (user_id = auth.uid() and status = 'pending')
  with check (user_id = auth.uid() and status in ('pending', 'cancelled'));

drop policy if exists wfh_requests_admin_write on public.wfh_requests;
create policy wfh_requests_admin_write on public.wfh_requests
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- review_wfh_request — the admin decision, and the only way a request becomes
-- an actual WFH day.
-- ---------------------------------------------------------------------------
create or replace function public.review_wfh_request(
  p_request_id uuid,
  p_approve    boolean,
  p_note       text default null
)
returns public.wfh_requests
language plpgsql security definer set search_path = public as $$
declare
  v_request public.wfh_requests;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can review work-from-home requests';
  end if;

  select * into v_request from public.wfh_requests where id = p_request_id for update;
  if not found then
    raise exception 'Request not found';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'This request has already been %', v_request.status;
  end if;

  update public.wfh_requests
     set status        = case when p_approve then 'approved' else 'rejected' end,
         decision_note = p_note,
         reviewed_by   = auth.uid(),
         reviewed_at   = now()
   where id = p_request_id
   returning * into v_request;

  -- Approval is what the engine actually reads.
  if p_approve then
    insert into public.wfh_assignments (user_id, date, reason, created_by, request_id)
    values (v_request.user_id, v_request.date,
            coalesce(v_request.reason, 'Approved WFH request'),
            auth.uid(), v_request.id)
    on conflict (user_id, date) do nothing;
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(),
          case when p_approve then 'wfh_request_approved' else 'wfh_request_rejected' end,
          'wfh_requests', v_request.id,
          jsonb_build_object('user_id', v_request.user_id,
                             'date', v_request.date,
                             'note', p_note));

  return v_request;
end $$;

-- ---------------------------------------------------------------------------
-- set_company_wfh_day / clear_company_wfh_day — mark a date so nobody on the
-- roster needs to check in that day.
-- ---------------------------------------------------------------------------
create or replace function public.set_company_wfh_day(
  p_date        date,
  p_note        text default null,
  p_location_id uuid default null
)
returns public.company_wfh_days
language plpgsql security definer set search_path = public as $$
declare
  v_day public.company_wfh_days;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can set a company work-from-home day';
  end if;

  insert into public.company_wfh_days (date, note, location_id, created_by)
  values (p_date, p_note, p_location_id, auth.uid())
  on conflict (date, location_id)
    do update set note = excluded.note, created_by = excluded.created_by
  returning * into v_day;

  -- Materialise for the roster the engine will ask about.
  insert into public.wfh_assignments (user_id, date, reason, created_by, company_day_id)
  select u.id, p_date, coalesce(p_note, 'Company work-from-home day'),
         auth.uid(), v_day.id
    from public.users u
   where u.status = 'active'
     and u.role = 'employee'
     and (p_location_id is null or u.location_id = p_location_id)
  on conflict (user_id, date) do nothing;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'company_wfh_day_set', 'company_wfh_days', v_day.id,
          jsonb_build_object('date', p_date, 'location_id', p_location_id));

  return v_day;
end $$;

create or replace function public.clear_company_wfh_day(p_day_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_day public.company_wfh_days;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can clear a company work-from-home day';
  end if;

  select * into v_day from public.company_wfh_days where id = p_day_id;
  if not found then
    return;
  end if;

  -- Only the rows this day created; an individually granted WFH survives.
  delete from public.wfh_assignments where company_day_id = p_day_id;
  delete from public.company_wfh_days where id = p_day_id;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), 'company_wfh_day_cleared', 'company_wfh_days', p_day_id,
          jsonb_build_object('date', v_day.date));
end $$;

-- Supabase grants these to `authenticated` at bootstrap for tables that exist
-- then; new tables need it spelled out. RLS above is what actually decides.
grant select, insert, update, delete on public.wfh_requests     to authenticated;
grant select, insert, update, delete on public.company_wfh_days to authenticated;

grant execute on function public.review_wfh_request(uuid, boolean, text) to authenticated;
grant execute on function public.set_company_wfh_day(date, text, uuid)   to authenticated;
grant execute on function public.clear_company_wfh_day(uuid)             to authenticated;
