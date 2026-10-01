-- ===========================================================================
-- 0008_attendance_sessions.sql
--
-- Multiple office visits per day. Every ENTER/EXIT pair is stored as its own
-- session, so an employee who leaves and comes back is checked in twice and
-- each visit is visible. The daily attendance row stays the single source of
-- truth for reports: it keeps the first check-in, the last check-out and the
-- summed duration of every visit.
--
-- Flow: entering the geofence auto-opens a session (auto check-in). The
-- employee ends a session by checking out with a work summary. The EXIT event
-- is a safety net: if a session is still open when they leave, it is closed
-- automatically so the time is never lost.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- attendance_sessions
-- ---------------------------------------------------------------------------
create table if not exists public.attendance_sessions (
  id               uuid primary key default gen_random_uuid(),
  attendance_id    uuid not null references public.attendance (id) on delete cascade,
  user_id          uuid not null references public.users (id) on delete cascade,
  check_in_at      timestamptz not null,
  check_out_at     timestamptz,
  duration_seconds integer,
  closed_by        text check (closed_by in ('manual', 'auto')),
  summary          text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists attendance_sessions_att_idx
  on public.attendance_sessions (attendance_id);
create index if not exists attendance_sessions_user_idx
  on public.attendance_sessions (user_id, check_in_at desc);

-- At most one open session per day.
create unique index if not exists attendance_sessions_open_idx
  on public.attendance_sessions (attendance_id)
  where check_out_at is null;

drop trigger if exists trg_attendance_sessions_touch on public.attendance_sessions;
create trigger trg_attendance_sessions_touch
  before update on public.attendance_sessions
  for each row execute function public.touch_updated_at();

alter table public.attendance_sessions enable row level security;

drop policy if exists attendance_sessions_select on public.attendance_sessions;
create policy attendance_sessions_select on public.attendance_sessions
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- Clients never write sessions directly; the SECURITY DEFINER engine does.
grant select on public.attendance_sessions to authenticated;

-- ---------------------------------------------------------------------------
-- refresh_attendance_totals — recompute the day from its sessions.
-- First in, last out, summed duration; status is PRESENT while a session is
-- still open, otherwise CHECKED_OUT. Manual rows are authoritative and skipped.
-- ---------------------------------------------------------------------------
create or replace function public.refresh_attendance_totals(p_attendance_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_source public.attendance_source;
  v_exists boolean;
begin
  select source into v_source from public.attendance where id = p_attendance_id;
  if v_source is distinct from 'automatic' then
    return;
  end if;

  select exists (select 1 from public.attendance_sessions where attendance_id = p_attendance_id)
    into v_exists;
  if not v_exists then
    return;
  end if;

  update public.attendance a
     set check_in_at            = s.first_in,
         check_out_at           = s.last_out,
         total_duration_seconds = coalesce(s.total, 0),
         status                 = case
           when s.open_count > 0 then 'PRESENT'::public.attendance_status
           when s.last_out is not null then 'CHECKED_OUT'::public.attendance_status
           else a.status
         end
    from (
      select min(check_in_at)                         as first_in,
             max(check_out_at)                         as last_out,
             sum(duration_seconds)                     as total,
             count(*) filter (where check_out_at is null) as open_count
        from public.attendance_sessions
       where attendance_id = p_attendance_id
    ) s
   where a.id = p_attendance_id;
end $$;

-- ---------------------------------------------------------------------------
-- record_location_event — now session-aware.
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
  v_open            public.attendance_sessions%rowtype;
  v_last            public.attendance_sessions%rowtype;
  v_out             timestamptz;
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
        values (v_uid, v_business_date, 'PRESENT', p_occurred_at, 'automatic')
        returning * into v_att;
        insert into public.attendance_sessions (attendance_id, user_id, check_in_at)
        values (v_att.id, v_uid, p_occurred_at);
      elsif v_att.source = 'manual' then
        null; -- admin-corrected records are authoritative
      else
        select * into v_open from public.attendance_sessions s
          where s.attendance_id = v_att.id and s.check_out_at is null
          order by s.check_in_at desc limit 1;

        if found then
          null; -- already inside; nothing to do
        else
          select * into v_last from public.attendance_sessions s
            where s.attendance_id = v_att.id
            order by s.check_in_at desc limit 1;
          v_grace := (select exit_grace_seconds from public.app_settings where id = 1);

          if found
             and v_last.check_out_at is not null
             and p_occurred_at - v_last.check_out_at <= make_interval(secs => v_grace) then
            -- GPS-drift re-entry: reopen the session that was just closed.
            update public.attendance_sessions
               set check_out_at       = null,
                   duration_seconds   = null,
                   closed_by          = null,
                   summary            = null,
                   updated_at         = now()
             where id = v_last.id;
            update public.attendance set work_summary = null where id = v_att.id;
          else
            -- A genuine new visit: open another session.
            insert into public.attendance_sessions (attendance_id, user_id, check_in_at)
            values (v_att.id, v_uid, p_occurred_at);
          end if;
        end if;

        perform public.refresh_attendance_totals(v_att.id);
      end if;
    else -- EXIT: safety-net auto-close of the open session
      if v_has_att and v_att.source <> 'manual' then
        select * into v_open from public.attendance_sessions s
          where s.attendance_id = v_att.id and s.check_out_at is null
          order by s.check_in_at desc limit 1;
        if found then
          v_out := greatest(p_occurred_at, v_open.check_in_at);
          update public.attendance_sessions
             set check_out_at       = v_out,
                 duration_seconds   = greatest(0, extract(epoch from (v_out - v_open.check_in_at))::int),
                 closed_by          = 'auto',
                 updated_at         = now()
           where id = v_open.id;
          perform public.refresh_attendance_totals(v_att.id);
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
-- employee_check_out — manual check-out. Ends the open session (with summary)
-- and refreshes the day. If the EXIT safety net already closed it, only the
-- summary is stored and the recorded check-out time is preserved.
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
  v_open public.attendance_sessions%rowtype;
  v_has_session boolean;
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

  if v_att.work_summary is not null
     and v_att.work_summary_at is not null
     and v_att.user_id = v_uid
     and not public.is_admin()
     and now() > v_att.work_summary_at + interval '40 minutes'
     and v_att.work_summary is distinct from trim(p_summary) then
    raise exception 'the work summary can no longer be edited'
      using errcode = 'P0001';
  end if;

  select exists (select 1 from public.attendance_sessions where attendance_id = p_attendance_id)
    into v_has_session;

  if v_has_session then
    select * into v_open from public.attendance_sessions
      where attendance_id = p_attendance_id and check_out_at is null
      order by check_in_at desc limit 1;
    if found then
      v_out := coalesce(p_occurred_at, now());
      if v_out < v_open.check_in_at then
        v_out := now();
      end if;
      update public.attendance_sessions
         set check_out_at     = v_out,
             duration_seconds = greatest(0, extract(epoch from (v_out - v_open.check_in_at))::int),
             closed_by        = 'manual',
             summary          = trim(p_summary),
             updated_at       = now()
       where id = v_open.id;
    end if;
    perform public.refresh_attendance_totals(p_attendance_id);
  else
    -- Legacy/manual day without sessions: preserve the original behaviour.
    v_out := coalesce(v_att.check_out_at, coalesce(p_occurred_at, now()));
    update public.attendance
       set check_out_at           = v_out,
           total_duration_seconds = greatest(0, extract(epoch from (v_out - v_att.check_in_at))::int)
     where id = p_attendance_id;
  end if;

  update public.attendance
     set status          = 'CHECKED_OUT',
         work_summary    = trim(p_summary),
         work_summary_at = case
           when work_summary is null then now()
           else work_summary_at
         end
   where id = p_attendance_id
   returning * into v_att;

  insert into public.location_events (
    user_id, geofence_id, event_type, occurred_at, accuracy_meters,
    source, dedupe_key, metadata, processed
  ) values (
    v_uid, p_geofence_id, 'EXIT', v_att.check_out_at, p_accuracy_meters,
    'Browser geolocation',
    md5(concat_ws('|', 'checkout', p_attendance_id, v_att.check_out_at::text)),
    jsonb_build_object('note', 'explicit checkout', 'work_summary', trim(p_summary)),
    true
  )
  on conflict (dedupe_key) do nothing;

  return v_att;
end $$;

-- ---------------------------------------------------------------------------
-- apply_manual_correction — a manual override replaces the sessions with the
-- corrected in/out pair, so reports stay consistent.
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

  delete from public.attendance_sessions where attendance_id = p_attendance_id;

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
-- Backfill: one session per existing attendance row that has a check-in.
-- ---------------------------------------------------------------------------
insert into public.attendance_sessions
  (attendance_id, user_id, check_in_at, check_out_at, duration_seconds, closed_by, summary)
select a.id, a.user_id, a.check_in_at, a.check_out_at, a.total_duration_seconds,
       case when a.check_out_at is not null then 'auto' else null end,
       a.work_summary
  from public.attendance a
 where a.check_in_at is not null
   and not exists (select 1 from public.attendance_sessions s where s.attendance_id = a.id);

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
revoke all on function public.refresh_attendance_totals(uuid) from public, anon;
grant execute on function public.refresh_attendance_totals(uuid) to authenticated;

revoke all on function public.record_location_event(
  uuid, public.geofence_event_type, timestamptz, timestamptz,
  double precision, text, text, jsonb) from public, anon;
grant execute on function public.record_location_event(
  uuid, public.geofence_event_type, timestamptz, timestamptz,
  double precision, text, text, jsonb) to authenticated;

revoke all on function public.employee_check_out(
  uuid, text, timestamptz, double precision, uuid) from public, anon;
grant execute on function public.employee_check_out(
  uuid, text, timestamptz, double precision, uuid) to authenticated;

revoke all on function public.apply_manual_correction(
  uuid, public.attendance_status, timestamptz, timestamptz, text) from public, anon;
grant execute on function public.apply_manual_correction(
  uuid, public.attendance_status, timestamptz, timestamptz, text) to authenticated;
