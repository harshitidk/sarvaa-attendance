-- ===========================================================================
-- 0009_manual_checkout_only.sql
--
-- Two policy changes:
--
--   1. Check-out is always manual. The EXIT event is still recorded for audit,
--      but it no longer closes the open session. Only employee_check_out (with
--      a work summary) ends a visit, so nobody is checked out just for leaving
--      the geofence or after office hours.
--
--   2. There is no absence cutoff and no automatic absence marking. Attendance
--      is reported as recorded; the admin reviews the month's CSV by hand.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- record_location_event — check-in stays automatic, check-out is manual.
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
  v_is_holiday      boolean;
  v_is_wfh          boolean;
  v_received        timestamptz := coalesce(p_received_at, now());
  v_open            public.attendance_sessions%rowtype;
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
  elsif p_event_type = 'ENTER' then
    select * into v_att from public.attendance
      where user_id = v_uid and date = v_business_date;
    v_has_att := found;

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
        null; -- already inside; a new visit only starts after a manual check-out
      else
        insert into public.attendance_sessions (attendance_id, user_id, check_in_at)
        values (v_att.id, v_uid, p_occurred_at);
        perform public.refresh_attendance_totals(v_att.id);
      end if;
    end if;
  else
    -- EXIT: recorded for audit only. Check-out is always manual.
    null;
  end if;

  update public.location_events set processed = true where id = v_event_id;

  select * into v_att from public.attendance
    where user_id = v_uid and date = v_business_date;

  return query
    select v_att.id, v_att.status, v_att.check_in_at, v_att.check_out_at,
           v_business_date, false;
end $$;

-- ---------------------------------------------------------------------------
-- No automatic absence: drop the finalizer and the cutoff setting.
-- ---------------------------------------------------------------------------
drop function if exists public.finalize_absences(date);

alter table public.app_settings drop column if exists absence_cutoff;

revoke all on function public.record_location_event(
  uuid, public.geofence_event_type, timestamptz, timestamptz,
  double precision, text, text, jsonb) from public, anon;
grant execute on function public.record_location_event(
  uuid, public.geofence_event_type, timestamptz, timestamptz,
  double precision, text, text, jsonb) to authenticated;
