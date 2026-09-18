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
