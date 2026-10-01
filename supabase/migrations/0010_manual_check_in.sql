-- ===========================================================================
-- 0010_manual_check_in.sql
--
-- Fallback check-in for when the device cannot get a location fix (indoors,
-- GPS off, permission pending). The employee taps "Check in manually" and a
-- visit opens at the current time, exactly as an automatic ENTER would.
--
-- It is deliberately still a check-in only: check-out remains manual and there
-- is still no automatic check-out.
-- ===========================================================================

create or replace function public.employee_manual_check_in(
  p_occurred_at timestamptz default now(),
  p_note        text        default null
)
returns public.attendance
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_tz   text;
  v_date date;
  v_att  public.attendance%rowtype;
  v_open public.attendance_sessions%rowtype;
  v_at   timestamptz := coalesce(p_occurred_at, now());
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.is_active_user() then
    raise exception 'account inactive' using errcode = '28000';
  end if;

  v_tz := public.app_timezone();
  v_date := (v_at at time zone v_tz)::date;

  select * into v_att from public.attendance
    where user_id = v_uid and date = v_date
    for update;

  if not found then
    insert into public.attendance (user_id, date, status, check_in_at, source)
    values (v_uid, v_date, 'PRESENT', v_at, 'automatic')
    returning * into v_att;
  elsif v_att.source = 'manual' then
    -- An admin-corrected day is authoritative; do not touch it.
    return v_att;
  end if;

  select * into v_open from public.attendance_sessions s
    where s.attendance_id = v_att.id and s.check_out_at is null
    order by s.check_in_at desc limit 1;

  if not found then
    insert into public.attendance_sessions (attendance_id, user_id, check_in_at)
    values (v_att.id, v_uid, v_at);
    perform public.refresh_attendance_totals(v_att.id);
  end if;

  insert into public.location_events (
    user_id, geofence_id, event_type, occurred_at, source, dedupe_key, metadata, processed
  ) values (
    v_uid, null, 'ENTER', v_at, 'Manual check-in',
    md5(concat_ws('|', 'manual-checkin', v_uid, v_at::text)),
    jsonb_build_object('note', coalesce(p_note, 'manual check-in')), true
  )
  on conflict (dedupe_key) do nothing;

  select * into v_att from public.attendance where id = v_att.id;
  return v_att;
end $$;

revoke all on function public.employee_manual_check_in(timestamptz, text) from public, anon;
grant execute on function public.employee_manual_check_in(timestamptz, text) to authenticated;
