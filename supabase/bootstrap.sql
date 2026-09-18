-- ===========================================================================
-- bootstrap.sql — schema + RLS + attendance engine + seed (generated)
-- Paste into the Supabase SQL Editor and Run, or apply via scripts/db-apply.sh
-- ===========================================================================



-- >>> supabase/migrations/0001_schema.sql

-- ===========================================================================
-- 0001_schema.sql — Core schema for Geofenced Employee Attendance
-- ===========================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.user_role as enum ('employee', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.attendance_status as enum
    ('PRESENT', 'CHECKED_OUT', 'WFH', 'HOLIDAY', 'LEAVE', 'ABSENT', 'MANUAL_OVERRIDE');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.attendance_source as enum ('automatic', 'manual');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.geofence_event_type as enum ('ENTER', 'EXIT');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- app_settings — single-row company configuration
-- ---------------------------------------------------------------------------
create table if not exists public.app_settings (
  id                  smallint primary key default 1 check (id = 1),
  company_timezone    text        not null default 'Asia/Kolkata',
  workday_start       time        not null default '09:00',
  workday_end         time        not null default '18:00',
  absence_cutoff      time        not null default '12:00',
  exit_grace_seconds  integer     not null default 300 check (exit_grace_seconds >= 0),
  event_retention_days integer    not null default 180 check (event_retention_days > 0),
  updated_at          timestamptz not null default now()
);

insert into public.app_settings (id) values (1) on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- locations — offices / sites
-- ---------------------------------------------------------------------------
create table if not exists public.locations (
  id          uuid primary key default gen_random_uuid(),
  name        text        not null,
  address     text,
  timezone    text,
  active      boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- users — profile mirror of auth.users
-- ---------------------------------------------------------------------------
create table if not exists public.users (
  id           uuid primary key references auth.users (id) on delete cascade,
  employee_id  text        not null unique,
  name         text        not null,
  email        text        not null unique,
  role         public.user_role not null default 'employee',
  department   text,
  location_id  uuid        references public.locations (id) on delete set null,
  status       text        not null default 'active' check (status in ('active', 'inactive')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists users_location_idx on public.users (location_id);
create index if not exists users_role_idx     on public.users (role);

-- ---------------------------------------------------------------------------
-- geofences
-- ---------------------------------------------------------------------------
create table if not exists public.geofences (
  id             uuid primary key default gen_random_uuid(),
  name           text        not null,
  latitude       double precision not null check (latitude between -90 and 90),
  longitude      double precision not null check (longitude between -180 and 180),
  radius_meters  integer     not null check (radius_meters between 25 and 5000),
  location_id    uuid        references public.locations (id) on delete set null,
  active         boolean     not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists geofences_location_idx on public.geofences (location_id);
create index if not exists geofences_active_idx   on public.geofences (active);

-- ---------------------------------------------------------------------------
-- employee_geofences — optional explicit per-employee assignment.
-- When an employee has no rows here, all active geofences for their
-- location are considered assigned.
-- ---------------------------------------------------------------------------
create table if not exists public.employee_geofences (
  user_id     uuid not null references public.users (id) on delete cascade,
  geofence_id uuid not null references public.geofences (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, geofence_id)
);

-- ---------------------------------------------------------------------------
-- attendance — authoritative primary record (one per employee per date)
-- ---------------------------------------------------------------------------
create table if not exists public.attendance (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references public.users (id) on delete cascade,
  date                   date not null,
  status                 public.attendance_status not null default 'PRESENT',
  check_in_at            timestamptz,
  check_out_at           timestamptz,
  total_duration_seconds integer,
  source                 public.attendance_source not null default 'automatic',
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (user_id, date)
);

create index if not exists attendance_date_idx    on public.attendance (date);
create index if not exists attendance_user_idx    on public.attendance (user_id, date desc);
create index if not exists attendance_status_idx  on public.attendance (status);

-- ---------------------------------------------------------------------------
-- location_events — raw OS geofence transitions (audit/debug only)
-- ---------------------------------------------------------------------------
create table if not exists public.location_events (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.users (id) on delete cascade,
  geofence_id      uuid references public.geofences (id) on delete set null,
  event_type       public.geofence_event_type not null,
  occurred_at      timestamptz not null,
  received_at      timestamptz not null default now(),
  accuracy_meters  double precision,
  source           text not null default 'OS geofence',
  dedupe_key       text not null unique,
  processed        boolean not null default false,
  metadata         jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now()
);

create index if not exists location_events_user_idx on public.location_events (user_id, occurred_at desc);
create index if not exists location_events_geo_idx  on public.location_events (geofence_id);

-- ---------------------------------------------------------------------------
-- holidays — company-wide (location_id null) or location-specific
-- ---------------------------------------------------------------------------
create table if not exists public.holidays (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  date        date not null,
  location_id uuid references public.locations (id) on delete cascade,
  created_by  uuid references public.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

create unique index if not exists holidays_date_location_uidx
  on public.holidays (date, coalesce(location_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- ---------------------------------------------------------------------------
-- wfh_assignments
-- ---------------------------------------------------------------------------
create table if not exists public.wfh_assignments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  date        date not null,
  reason      text,
  created_by  uuid references public.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (user_id, date)
);

create index if not exists wfh_date_idx on public.wfh_assignments (date);

-- ---------------------------------------------------------------------------
-- attendance_corrections — immutable manual-edit history
-- ---------------------------------------------------------------------------
create table if not exists public.attendance_corrections (
  id            uuid primary key default gen_random_uuid(),
  attendance_id uuid not null references public.attendance (id) on delete cascade,
  admin_id      uuid not null references public.users (id) on delete set null,
  old_value     jsonb not null,
  new_value     jsonb not null,
  reason        text not null,
  created_at    timestamptz not null default now()
);

create index if not exists corrections_attendance_idx on public.attendance_corrections (attendance_id);

-- ---------------------------------------------------------------------------
-- audit_logs — sensitive administrative operations
-- ---------------------------------------------------------------------------
create table if not exists public.audit_logs (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references public.users (id) on delete set null,
  action      text not null,
  entity_type text not null,
  entity_id   uuid,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists audit_logs_entity_idx on public.audit_logs (entity_type, entity_id);
create index if not exists audit_logs_actor_idx  on public.audit_logs (actor_id, created_at desc);

-- ---------------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['app_settings', 'locations', 'users', 'geofences', 'attendance']
  loop
    execute format('drop trigger if exists trg_%s_touch on public.%I', t, t);
    execute format('create trigger trg_%s_touch before update on public.%I
                    for each row execute function public.touch_updated_at()', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Auto-provision a profile row when an auth user is created.
-- Metadata keys expected: employee_id, name, role, department, location_id.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.users (id, employee_id, name, email, role, department, location_id)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'employee_id', 'EMP-' || left(new.id::text, 8)),
    coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)),
    new.email,
    coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'employee'),
    new.raw_user_meta_data ->> 'department',
    nullif(new.raw_user_meta_data ->> 'location_id', '')::uuid
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- >>> supabase/migrations/0002_rls.sql

-- ===========================================================================
-- 0002_rls.sql — Row Level Security & helpers
-- Authorization is enforced database-side, never only in the UI.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and role = 'admin' and status = 'active'
  );
$$;

create or replace function public.is_active_user()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and status = 'active'
  );
$$;

create or replace function public.app_timezone()
returns text
language sql stable security definer set search_path = public as $$
  select company_timezone from public.app_settings where id = 1;
$$;

grant execute on function public.is_admin()      to authenticated;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.app_timezone()  to authenticated;

-- ---------------------------------------------------------------------------
-- Enable RLS
-- ---------------------------------------------------------------------------
alter table public.app_settings          enable row level security;
alter table public.locations             enable row level security;
alter table public.users                 enable row level security;
alter table public.geofences             enable row level security;
alter table public.employee_geofences    enable row level security;
alter table public.attendance            enable row level security;
alter table public.location_events       enable row level security;
alter table public.holidays              enable row level security;
alter table public.wfh_assignments       enable row level security;
alter table public.attendance_corrections enable row level security;
alter table public.audit_logs            enable row level security;

-- ---------------------------------------------------------------------------
-- app_settings: readable by authenticated, writable by admins only
-- ---------------------------------------------------------------------------
drop policy if exists app_settings_select on public.app_settings;
create policy app_settings_select on public.app_settings
  for select to authenticated using (true);

drop policy if exists app_settings_admin_write on public.app_settings;
create policy app_settings_admin_write on public.app_settings
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- locations
-- ---------------------------------------------------------------------------
drop policy if exists locations_select on public.locations;
create policy locations_select on public.locations
  for select to authenticated using (true);

drop policy if exists locations_admin_write on public.locations;
create policy locations_admin_write on public.locations
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- users: employees read self; admins read/write all
-- ---------------------------------------------------------------------------
drop policy if exists users_select_self on public.users;
create policy users_select_self on public.users
  for select to authenticated using (id = auth.uid());

drop policy if exists users_admin_all on public.users;
create policy users_admin_all on public.users
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- geofences: employees see active geofences for their location or assigned
-- ---------------------------------------------------------------------------
drop policy if exists geofences_select on public.geofences;
create policy geofences_select on public.geofences
  for select to authenticated using (
    public.is_admin()
    or (
      active
      and (
        exists (select 1 from public.employee_geofences eg
                where eg.geofence_id = geofences.id and eg.user_id = auth.uid())
        or location_id is null
        or location_id = (select location_id from public.users where id = auth.uid())
      )
    )
  );

drop policy if exists geofences_admin_write on public.geofences;
create policy geofences_admin_write on public.geofences
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- employee_geofences
-- ---------------------------------------------------------------------------
drop policy if exists employee_geofences_select on public.employee_geofences;
create policy employee_geofences_select on public.employee_geofences
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists employee_geofences_admin_write on public.employee_geofences;
create policy employee_geofences_admin_write on public.employee_geofences
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- attendance: employees read own; admins read/write all.
-- Employee writes happen only through the security-definer engine functions.
-- ---------------------------------------------------------------------------
drop policy if exists attendance_select on public.attendance;
create policy attendance_select on public.attendance
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists attendance_admin_write on public.attendance;
create policy attendance_admin_write on public.attendance
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- location_events: employees read own; admins read all. Writes via engine only.
-- ---------------------------------------------------------------------------
drop policy if exists location_events_select on public.location_events;
create policy location_events_select on public.location_events
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- ---------------------------------------------------------------------------
-- holidays: readable by all authenticated; admins write
-- ---------------------------------------------------------------------------
drop policy if exists holidays_select on public.holidays;
create policy holidays_select on public.holidays
  for select to authenticated using (true);

drop policy if exists holidays_admin_write on public.holidays;
create policy holidays_admin_write on public.holidays
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- wfh_assignments: employees read own; admins write
-- ---------------------------------------------------------------------------
drop policy if exists wfh_select on public.wfh_assignments;
create policy wfh_select on public.wfh_assignments
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists wfh_admin_write on public.wfh_assignments;
create policy wfh_admin_write on public.wfh_assignments
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- attendance_corrections: employees read corrections for their own records
-- ---------------------------------------------------------------------------
drop policy if exists corrections_select on public.attendance_corrections;
create policy corrections_select on public.attendance_corrections
  for select to authenticated using (
    public.is_admin()
    or exists (
      select 1 from public.attendance a
      where a.id = attendance_corrections.attendance_id and a.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- audit_logs: admins only
-- ---------------------------------------------------------------------------
drop policy if exists audit_logs_select on public.audit_logs;
create policy audit_logs_select on public.audit_logs
  for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------------
-- Audit triggers for administrative tables
-- ---------------------------------------------------------------------------
create or replace function public.audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_action text := lower(tg_op);
  v_entity_id uuid;
begin
  if tg_op = 'DELETE' then
    v_entity_id := old.id;
  else
    v_entity_id := new.id;
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    v_action,
    tg_table_name,
    v_entity_id,
    jsonb_build_object(
      'old', case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
      'new', case when tg_op in ('UPDATE','INSERT') then to_jsonb(new) else null end
    )
  );
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['geofences', 'holidays', 'wfh_assignments', 'locations', 'users']
  loop
    execute format('drop trigger if exists trg_%s_audit on public.%I', t, t);
    execute format('create trigger trg_%s_audit after insert or update or delete on public.%I
                    for each row execute function public.audit_row()', t, t);
  end loop;
end $$;

-- >>> supabase/migrations/0003_attendance_engine.sql

-- ===========================================================================
-- 0003_attendance_engine.sql
-- The backend decides whether a geofence transition creates/updates attendance.
-- All writes run through SECURITY DEFINER functions; clients cannot write
-- attendance or raw events directly.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- record_location_event
-- Called by the mobile app (or the process-location-event Edge Function) with
-- an authenticated session. Idempotent on dedupe_key.
-- ---------------------------------------------------------------------------
create or replace function public.record_location_event(
  p_geofence_id     uuid,
  p_event_type      public.geofence_event_type,
  p_occurred_at     timestamptz,
  p_received_at     timestamptz   default now(),
  p_accuracy_meters double precision default null,
  p_dedupe_key      text          default null,
  p_source          text          default 'OS geofence',
  p_metadata        jsonb         default '{}'::jsonb
)
returns table (
  attendance_id uuid,
  status        public.attendance_status,
  check_in_at   timestamptz,
  check_out_at  timestamptz,
  business_date date,
  duplicate     boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid             uuid := auth.uid();
  v_tz              text;
  v_business_date   date;
  v_event_id        uuid;
  v_dedupe          text;
  v_geo             public.geofences%rowtype;
  v_att             public.attendance%rowtype;
  v_has_att         boolean := false;
  v_grace           integer;
  v_is_holiday      boolean;
  v_is_wfh          boolean;
  v_received        timestamptz := coalesce(p_received_at, now());
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if not public.is_active_user() then
    raise exception 'account inactive' using errcode = '28000';
  end if;

  select * into v_geo from public.geofences where id = p_geofence_id;
  if not found then
    raise exception 'geofence % not found', p_geofence_id using errcode = 'P0002';
  end if;
  if not v_geo.active then
    raise exception 'geofence % is inactive', p_geofence_id using errcode = 'P0001';
  end if;

  v_tz := public.app_timezone();
  v_business_date := (v_received at time zone v_tz)::date;

  v_dedupe := coalesce(
    p_dedupe_key,
    md5(concat_ws('|', v_uid, p_geofence_id, p_event_type, p_occurred_at, v_received))
  );

  -- Idempotency: a replayed event inserts nothing and never mutates attendance.
  insert into public.location_events (
    user_id, geofence_id, event_type, occurred_at, received_at,
    accuracy_meters, source, dedupe_key, metadata
  ) values (
    v_uid, p_geofence_id, p_event_type, p_occurred_at, v_received,
    p_accuracy_meters, p_source, v_dedupe, coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (dedupe_key) do nothing
  returning id into v_event_id;

  if v_event_id is null then
    select * into v_att from public.attendance
      where user_id = v_uid and date = v_business_date;
    return query
      select v_att.id, v_att.status, v_att.check_in_at, v_att.check_out_at,
             v_business_date, true;
    return;
  end if;

  -- Exceptions are evaluated before office attendance.
  select exists (
    select 1 from public.holidays h
    where h.date = v_business_date
      and (h.location_id is null
           or h.location_id = (select location_id from public.users where id = v_uid))
  ) into v_is_holiday;

  select exists (
    select 1 from public.wfh_assignments w
    where w.user_id = v_uid and w.date = v_business_date
  ) into v_is_wfh;

  if v_is_holiday then
    insert into public.attendance (user_id, date, status, source)
    values (v_uid, v_business_date, 'HOLIDAY', 'automatic')
    on conflict (user_id, date) do nothing;
  elsif v_is_wfh then
    insert into public.attendance (user_id, date, status, source)
    values (v_uid, v_business_date, 'WFH', 'automatic')
    on conflict (user_id, date) do nothing;
  else
    select * into v_att from public.attendance
      where user_id = v_uid and date = v_business_date;
    v_has_att := found;

    if p_event_type = 'ENTER' then
      if not v_has_att then
        insert into public.attendance (user_id, date, status, check_in_at, source)
        values (v_uid, v_business_date, 'PRESENT', p_occurred_at, 'automatic');
      elsif v_att.source = 'manual' then
        null; -- admin-corrected records are authoritative
      elsif v_att.check_out_at is not null then
        -- Re-entry within the grace window cancels a GPS-drift checkout.
        v_grace := (select exit_grace_seconds from public.app_settings where id = 1);
        if p_occurred_at - v_att.check_out_at <= make_interval(secs => v_grace) then
          update public.attendance
             set check_out_at = null,
                 status = 'PRESENT',
                 total_duration_seconds = null
           where id = v_att.id;
        end if;
      elsif v_att.check_in_at is null then
        -- First valid ENTER establishes check-in; later ENTERs do not overwrite.
        update public.attendance
           set check_in_at = p_occurred_at,
               status = 'PRESENT'
         where id = v_att.id;
      end if;
    else -- EXIT
      if v_has_att and v_att.source <> 'manual' and v_att.check_in_at is not null then
        if v_att.check_out_at is null or p_occurred_at > v_att.check_out_at then
          update public.attendance
             set check_out_at = p_occurred_at,
                 status = 'CHECKED_OUT',
                 total_duration_seconds =
                   greatest(0, extract(epoch from (p_occurred_at - v_att.check_in_at))::int)
           where id = v_att.id;
        end if;
      end if;
    end if;
  end if;

  update public.location_events set processed = true where id = v_event_id;

  select * into v_att from public.attendance
    where user_id = v_uid and date = v_business_date;

  return query
    select v_att.id, v_att.status, v_att.check_in_at, v_att.check_out_at,
           v_business_date, false;
end $$;

-- ---------------------------------------------------------------------------
-- finalize_absences — mark active employees ABSENT after the configured cutoff
-- ---------------------------------------------------------------------------
create or replace function public.finalize_absences(p_date date default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_date    date;
  v_tz      text;
  v_cutoff  time;
  v_count   integer := 0;
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;

  v_tz := public.app_timezone();
  v_date := coalesce(p_date, (now() at time zone v_tz)::date);
  select absence_cutoff into v_cutoff from public.app_settings where id = 1;

  if v_date = (now() at time zone v_tz)::date
     and (now() at time zone v_tz)::time < v_cutoff then
    raise exception 'absence cutoff (%) not reached for %', v_cutoff, v_date
      using errcode = 'P0001';
  end if;

  with candidates as (
    select u.id
    from public.users u
    where u.status = 'active'
      and u.role = 'employee'
      and not exists (select 1 from public.attendance a
                      where a.user_id = u.id and a.date = v_date)
      and not exists (select 1 from public.holidays h
                      where h.date = v_date
                        and (h.location_id is null or h.location_id = u.location_id))
      and not exists (select 1 from public.wfh_assignments w
                      where w.user_id = u.id and w.date = v_date)
  )
  insert into public.attendance (user_id, date, status, source)
  select id, v_date, 'ABSENT', 'automatic' from candidates
  on conflict (user_id, date) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- apply_manual_correction — auditable admin override
-- Retains old value, new value, actor, timestamp and reason.
-- ---------------------------------------------------------------------------
create or replace function public.apply_manual_correction(
  p_attendance_id uuid,
  p_new_status    public.attendance_status default null,
  p_check_in_at   timestamptz default null,
  p_check_out_at  timestamptz default null,
  p_reason        text default null
)
returns public.attendance
language plpgsql security definer set search_path = public as $$
declare
  v_old   public.attendance%rowtype;
  v_new   public.attendance%rowtype;
  v_admin uuid := auth.uid();
  v_in    timestamptz;
  v_out   timestamptz;
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'a correction reason is required' using errcode = '22023';
  end if;

  select * into v_old from public.attendance where id = p_attendance_id for update;
  if not found then
    raise exception 'attendance % not found', p_attendance_id using errcode = 'P0002';
  end if;

  v_in  := coalesce(p_check_in_at, v_old.check_in_at);
  v_out := coalesce(p_check_out_at, v_old.check_out_at);

  update public.attendance
     set status                 = coalesce(p_new_status, status),
         check_in_at            = v_in,
         check_out_at           = v_out,
         total_duration_seconds = case
           when v_in is not null and v_out is not null
           then greatest(0, extract(epoch from (v_out - v_in))::int)
           else total_duration_seconds
         end,
         source                 = 'manual'
   where id = p_attendance_id
   returning * into v_new;

  insert into public.attendance_corrections
    (attendance_id, admin_id, old_value, new_value, reason)
  values
    (p_attendance_id, v_admin, to_jsonb(v_old), to_jsonb(v_new), p_reason);

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (
    v_admin, 'correct', 'attendance', p_attendance_id,
    jsonb_build_object('old', to_jsonb(v_old), 'new', to_jsonb(v_new), 'reason', p_reason)
  );

  return v_new;
end $$;

-- ---------------------------------------------------------------------------
-- Privileges: engine functions are callable by authenticated users; the
-- functions themselves enforce role checks. Direct table writes stay blocked.
-- ---------------------------------------------------------------------------
revoke all on function public.record_location_event(
  uuid, public.geofence_event_type, timestamptz, timestamptz,
  double precision, text, text, jsonb) from public, anon;
grant execute on function public.record_location_event(
  uuid, public.geofence_event_type, timestamptz, timestamptz,
  double precision, text, text, jsonb) to authenticated;

revoke all on function public.finalize_absences(date) from public, anon;
grant execute on function public.finalize_absences(date) to authenticated;

revoke all on function public.apply_manual_correction(
  uuid, public.attendance_status, timestamptz, timestamptz, text) from public, anon;
grant execute on function public.apply_manual_correction(
  uuid, public.attendance_status, timestamptz, timestamptz, text) to authenticated;

-- >>> supabase/migrations/0004_work_summary.sql

-- ===========================================================================
-- 0004_work_summary.sql
-- Daily work summary captured at check-out, plus an explicit employee
-- check-out function.
-- ===========================================================================

alter table public.attendance add column if not exists work_summary text;

-- ---------------------------------------------------------------------------
-- Replace the engine so a drift-cancelled checkout also clears the summary.
-- ---------------------------------------------------------------------------
create or replace function public.record_location_event(
  p_geofence_id     uuid,
  p_event_type      public.geofence_event_type,
  p_occurred_at     timestamptz,
  p_received_at     timestamptz   default now(),
  p_accuracy_meters double precision default null,
  p_dedupe_key      text          default null,
  p_source          text          default 'OS geofence',
  p_metadata        jsonb         default '{}'::jsonb
)
returns table (
  attendance_id uuid,
  status        public.attendance_status,
  check_in_at   timestamptz,
  check_out_at  timestamptz,
  business_date date,
  duplicate     boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid             uuid := auth.uid();
  v_tz              text;
  v_business_date   date;
  v_event_id        uuid;
  v_dedupe          text;
  v_geo             public.geofences%rowtype;
  v_att             public.attendance%rowtype;
  v_has_att         boolean := false;
  v_grace           integer;
  v_is_holiday      boolean;
  v_is_wfh          boolean;
  v_received        timestamptz := coalesce(p_received_at, now());
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if not public.is_active_user() then
    raise exception 'account inactive' using errcode = '28000';
  end if;

  select * into v_geo from public.geofences where id = p_geofence_id;
  if not found then
    raise exception 'geofence % not found', p_geofence_id using errcode = 'P0002';
  end if;
  if not v_geo.active then
    raise exception 'geofence % is inactive', p_geofence_id using errcode = 'P0001';
  end if;

  v_tz := public.app_timezone();
  v_business_date := (v_received at time zone v_tz)::date;

  v_dedupe := coalesce(
    p_dedupe_key,
    md5(concat_ws('|', v_uid, p_geofence_id, p_event_type, p_occurred_at, v_received))
  );

  insert into public.location_events (
    user_id, geofence_id, event_type, occurred_at, received_at,
    accuracy_meters, source, dedupe_key, metadata
  ) values (
    v_uid, p_geofence_id, p_event_type, p_occurred_at, v_received,
    p_accuracy_meters, p_source, v_dedupe, coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (dedupe_key) do nothing
  returning id into v_event_id;

  if v_event_id is null then
    select * into v_att from public.attendance
      where user_id = v_uid and date = v_business_date;
    return query
      select v_att.id, v_att.status, v_att.check_in_at, v_att.check_out_at,
             v_business_date, true;
    return;
  end if;

  select exists (
    select 1 from public.holidays h
    where h.date = v_business_date
      and (h.location_id is null
           or h.location_id = (select location_id from public.users where id = v_uid))
  ) into v_is_holiday;

  select exists (
    select 1 from public.wfh_assignments w
    where w.user_id = v_uid and w.date = v_business_date
  ) into v_is_wfh;

  if v_is_holiday then
    insert into public.attendance (user_id, date, status, source)
    values (v_uid, v_business_date, 'HOLIDAY', 'automatic')
    on conflict (user_id, date) do nothing;
  elsif v_is_wfh then
    insert into public.attendance (user_id, date, status, source)
    values (v_uid, v_business_date, 'WFH', 'automatic')
    on conflict (user_id, date) do nothing;
  else
    select * into v_att from public.attendance
      where user_id = v_uid and date = v_business_date;
    v_has_att := found;

    if p_event_type = 'ENTER' then
      if not v_has_att then
        insert into public.attendance (user_id, date, status, check_in_at, source)
        values (v_uid, v_business_date, 'PRESENT', p_occurred_at, 'automatic');
      elsif v_att.source = 'manual' then
        null;
      elsif v_att.check_out_at is not null then
        v_grace := (select exit_grace_seconds from public.app_settings where id = 1);
        if p_occurred_at - v_att.check_out_at <= make_interval(secs => v_grace) then
          update public.attendance
             set check_out_at = null,
                 status = 'PRESENT',
                 total_duration_seconds = null,
                 work_summary = null
           where id = v_att.id;
        end if;
      elsif v_att.check_in_at is null then
        update public.attendance
           set check_in_at = p_occurred_at,
               status = 'PRESENT'
         where id = v_att.id;
      end if;
    else -- EXIT
      if v_has_att and v_att.source <> 'manual' and v_att.check_in_at is not null then
        if v_att.check_out_at is null or p_occurred_at > v_att.check_out_at then
          update public.attendance
             set check_out_at = p_occurred_at,
                 status = 'CHECKED_OUT',
                 total_duration_seconds =
                   greatest(0, extract(epoch from (p_occurred_at - v_att.check_in_at))::int)
           where id = v_att.id;
        end if;
      end if;
    end if;
  end if;

  update public.location_events set processed = true where id = v_event_id;

  select * into v_att from public.attendance
    where user_id = v_uid and date = v_business_date;

  return query
    select v_att.id, v_att.status, v_att.check_in_at, v_att.check_out_at,
           v_business_date, false;
end $$;

-- ---------------------------------------------------------------------------
-- employee_check_out — explicit check-out with a mandatory work summary.
-- If a checkout already exists (e.g. automatic), only the summary is stored
-- and the original checkout time is preserved.
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

  v_out := coalesce(v_att.check_out_at, coalesce(p_occurred_at, now()));

  update public.attendance
     set check_out_at = v_out,
         status = 'CHECKED_OUT',
         total_duration_seconds = greatest(0, extract(epoch from (v_out - v_att.check_in_at))::int),
         work_summary = trim(p_summary)
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

-- >>> supabase/seed.sql

-- ===========================================================================
-- seed.sql — local development data (safe to re-run)
-- Auth users are intentionally NOT seeded here: create them through the
-- Supabase Auth API / Studio so password hashing and identities stay correct.
-- After creating an auth user, set its profile with:
--
--   update public.users
--      set employee_id = 'EMP-0001', name = 'Admin User', role = 'admin'
--    where email = 'admin@example.com';
-- ===========================================================================

-- Company configuration
update public.app_settings
   set company_timezone   = 'Asia/Kolkata',
       workday_start      = '09:00',
       workday_end        = '18:00',
       absence_cutoff     = '12:00',
       exit_grace_seconds = 300
 where id = 1;

-- Offices
insert into public.locations (id, name, address, timezone)
values
  ('11111111-1111-1111-1111-111111111111', 'Delhi HQ', 'Connaught Place, New Delhi', 'Asia/Kolkata'),
  ('22222222-2222-2222-2222-222222222222', 'Bengaluru Office', 'Koramangala, Bengaluru', 'Asia/Kolkata')
on conflict (id) do nothing;

-- Geofences (~150m radius around each office)
insert into public.geofences (id, name, latitude, longitude, radius_meters, location_id, active)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Delhi HQ',        28.6304, 77.2177, 150,
     '11111111-1111-1111-1111-111111111111', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bengaluru Office', 12.9352, 77.6245, 150,
     '22222222-2222-2222-2222-222222222222', true)
on conflict (id) do nothing;

-- Company-wide holiday example
insert into public.holidays (name, date, location_id)
values ('Republic Day', '2026-01-26', null)
on conflict do nothing;
