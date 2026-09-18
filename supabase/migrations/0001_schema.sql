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
