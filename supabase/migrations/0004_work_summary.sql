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
