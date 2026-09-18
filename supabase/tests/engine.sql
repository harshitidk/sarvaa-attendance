-- ===========================================================================
-- supabase/tests/engine.sql
-- Assertion-based tests for the attendance engine, RLS helpers and
-- employee check-out. Runs against a scratch database with an auth stub
-- (see scripts/test-engine.sh). Any failure raises an exception.
-- ===========================================================================

create or replace function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

do $$
declare
  v_emp   uuid := 'e0000000-0000-0000-0000-000000000001';
  v_admin uuid := 'a0000000-0000-0000-0000-000000000001';
  v_geo   uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_loc   uuid := '11111111-1111-1111-1111-111111111111';
  v_day   date := (now() at time zone 'Asia/Kolkata')::date;
  v_res   record;
  v_att   record;
  v_att_id uuid;
  v_summary text;
  v_cutoff time;
  v_cutoff_rejected boolean := false;
  v_cutoff_message text;
  v_missing_rejected boolean := false;
  v_inactive_rejected boolean := false;
  v_working_saved integer[];
begin
  delete from auth.users where id in (v_emp, v_admin);

  insert into auth.users (id, email, raw_user_meta_data) values
    (v_emp, 'emp@test.com', jsonb_build_object('employee_id','EMP-1024','name','Test Emp','role','employee')),
    (v_admin, 'admin@test.com', jsonb_build_object('employee_id','ADM-1','name','Test Admin','role','admin'));

  if not exists (select 1 from public.users where id = v_emp and employee_id = 'EMP-1024') then
    raise exception 'FAIL profile trigger did not create a profile';
  end if;

  update public.users set location_id = v_loc where id = v_emp;
  perform set_config('request.jwt.claim.sub', v_emp::text, false);

  -- 1. ENTER creates PRESENT
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    ((v_day + time '09:00') at time zone 'Asia/Kolkata'),
    ((v_day + time '09:00') at time zone 'Asia/Kolkata'),
    12, 'e1', 'OS geofence', '{}');
  if v_res.status <> 'PRESENT' or v_res.check_in_at is null then
    raise exception 'FAIL 1 ENTER: %', v_res;
  end if;

  -- 2. Duplicate event is idempotent
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    ((v_day + time '09:00') at time zone 'Asia/Kolkata'),
    ((v_day + time '09:00') at time zone 'Asia/Kolkata'),
    12, 'e1', 'OS geofence', '{}');
  if not v_res.duplicate then
    raise exception 'FAIL 2 duplicate not detected';
  end if;
  if (select count(*) from public.location_events
        where user_id = v_emp and dedupe_key = 'e1') <> 1 then
    raise exception 'FAIL 2 replayed event was inserted';
  end if;
  select * into v_att from public.attendance where user_id = v_emp and date = v_day;
  if v_att.check_in_at is distinct from ((v_day + time '09:00') at time zone 'Asia/Kolkata')
     or v_att.status is distinct from 'PRESENT' then
    raise exception 'FAIL 2 replay mutated attendance: %', v_att;
  end if;

  -- 3. Later ENTER does not overwrite first check-in
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    ((v_day + time '09:30') at time zone 'Asia/Kolkata'),
    ((v_day + time '09:30') at time zone 'Asia/Kolkata'),
    12, 'e2', 'OS geofence', '{}');
  if v_res.check_in_at is distinct from ((v_day + time '09:00') at time zone 'Asia/Kolkata') then
    raise exception 'FAIL 3 check-in overwritten: %', v_res.check_in_at;
  end if;

  -- 4. EXIT then re-ENTER within grace cancels checkout and clears summary
  select * into v_res from public.record_location_event(
    v_geo, 'EXIT',
    ((v_day + time '09:05') at time zone 'Asia/Kolkata'),
    ((v_day + time '09:05') at time zone 'Asia/Kolkata'),
    12, 'x1', 'OS geofence', '{}');
  if v_res.status <> 'CHECKED_OUT' then
    raise exception 'FAIL 4a EXIT: %', v_res.status;
  end if;
  update public.attendance set work_summary = 'stale summary'
   where user_id = v_emp and date = v_day;
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    ((v_day + time '09:08') at time zone 'Asia/Kolkata'),
    ((v_day + time '09:08') at time zone 'Asia/Kolkata'),
    12, 'e3', 'OS geofence', '{}');
  if v_res.status <> 'PRESENT' or v_res.check_out_at is not null then
    raise exception 'FAIL 4b grace revert: %', v_res;
  end if;
  select work_summary into v_summary from public.attendance where user_id = v_emp and date = v_day;
  if v_summary is not null then
    raise exception 'FAIL 4c summary not cleared on drift revert';
  end if;

  -- 5. Final EXIT records checkout and duration
  select * into v_res from public.record_location_event(
    v_geo, 'EXIT',
    ((v_day + time '17:00') at time zone 'Asia/Kolkata'),
    ((v_day + time '17:00') at time zone 'Asia/Kolkata'),
    12, 'x2', 'OS geofence', '{}');
  select * into v_att from public.attendance where user_id = v_emp and date = v_day;
  if v_att.status is distinct from 'CHECKED_OUT'
     or v_att.total_duration_seconds is distinct from 8 * 3600 then
    raise exception 'FAIL 5 checkout/duration: %', v_att;
  end if;

  -- 5b. ENTER after the grace window does not reopen a closed day
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    ((v_day + time '17:30') at time zone 'Asia/Kolkata'),
    ((v_day + time '17:30') at time zone 'Asia/Kolkata'),
    12, 'e5', 'OS geofence', '{}');
  select * into v_att from public.attendance where user_id = v_emp and date = v_day;
  if v_att.status is distinct from 'CHECKED_OUT'
     or v_att.check_out_at is distinct from ((v_day + time '17:00') at time zone 'Asia/Kolkata')
     or v_att.total_duration_seconds is distinct from 8 * 3600 then
    raise exception 'FAIL 5b late ENTER reopened checkout: %', v_att;
  end if;

  -- 6. WFH exception wins
  insert into public.wfh_assignments (user_id, date, reason) values (v_emp, v_day + 1, 'test');
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    (((v_day + 1) + time '09:00') at time zone 'Asia/Kolkata'),
    (((v_day + 1) + time '09:00') at time zone 'Asia/Kolkata'),
    12, 'w1', 'OS geofence', '{}');
  if v_res.status <> 'WFH' then
    raise exception 'FAIL 6 WFH: %', v_res.status;
  end if;

  -- 7. Holiday exception wins
  insert into public.holidays (name, date) values ('Test Holiday', v_day + 2);
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    (((v_day + 2) + time '09:00') at time zone 'Asia/Kolkata'),
    (((v_day + 2) + time '09:00') at time zone 'Asia/Kolkata'),
    12, 'h1', 'OS geofence', '{}');
  if v_res.status <> 'HOLIDAY' then
    raise exception 'FAIL 7 HOLIDAY: %', v_res.status;
  end if;

  -- 8. Employee check-out requires a summary
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    (((v_day + 4) + time '09:00') at time zone 'Asia/Kolkata'),
    (((v_day + 4) + time '09:00') at time zone 'Asia/Kolkata'),
    12, 'e4', 'OS geofence', '{}');
  select id into v_att_id from public.attendance where user_id = v_emp and date = v_day + 4;
  begin
    perform public.employee_check_out(v_att_id, '   ');
    raise exception 'FAIL 8a blank summary accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.employee_check_out(v_att_id, 'ab');
    raise exception 'FAIL 8b short summary accepted';
  exception when sqlstate '22023' then null;
  end;

  -- 9. Employee check-out stores summary, status and duration
  select * into v_att from public.employee_check_out(
    v_att_id, '  Built the attendance engine  ',
    ((v_day + 4) + time '17:30') at time zone 'Asia/Kolkata', 9, v_geo);
  if v_att.status is distinct from 'CHECKED_OUT'
     or v_att.work_summary is distinct from 'Built the attendance engine'
     or v_att.total_duration_seconds is distinct from 8 * 3600 + 1800 then
    raise exception 'FAIL 9 checkout: %', v_att;
  end if;

  -- 10. Re-submitting a summary keeps the original checkout time
  select * into v_att from public.employee_check_out(
    v_att_id, 'Updated summary',
    ((v_day + 4) + time '19:00') at time zone 'Asia/Kolkata', 9, v_geo);
  if v_att.check_out_at is distinct from ((v_day + 4) + time '17:30') at time zone 'Asia/Kolkata' then
    raise exception 'FAIL 10 checkout time moved: %', v_att.check_out_at;
  end if;

  -- 11. Employees cannot check out someone else's record
  insert into public.attendance (user_id, date, status, check_in_at, source)
  values (v_admin, v_day + 5, 'PRESENT',
          ((v_day + 5) + time '09:00') at time zone 'Asia/Kolkata', 'automatic')
  on conflict (user_id, date) do nothing;
  select id into v_att_id from public.attendance
   where user_id = v_admin and date = v_day + 5;
  begin
    perform public.employee_check_out(v_att_id, 'nope');
    raise exception 'FAIL 11 unauthorized checkout allowed';
  exception when sqlstate '42501' then null;
  end;

  -- 12. Admin correction is audited
  perform set_config('request.jwt.claim.sub', v_admin::text, false);
  select id into v_att_id from public.attendance where user_id = v_emp and date = v_day;
  select * into v_att from public.apply_manual_correction(
    v_att_id, 'MANUAL_OVERRIDE',
    ((v_day + time '10:00') at time zone 'Asia/Kolkata'),
    ((v_day + time '18:00') at time zone 'Asia/Kolkata'),
    'Device GPS failed');
  if v_att.source is distinct from 'manual'
     or v_att.total_duration_seconds is distinct from 8 * 3600 then
    raise exception 'FAIL 12a correction: %', v_att;
  end if;
  if (select count(*) from public.attendance_corrections where attendance_id = v_att_id) <> 1 then
    raise exception 'FAIL 12b correction not audited';
  end if;
  select * into v_res from public.attendance_corrections where attendance_id = v_att_id;
  if v_res.admin_id is distinct from v_admin
     or v_res.reason is distinct from 'Device GPS failed'
     or (v_res.old_value->>'check_in_at')::timestamptz
        is distinct from ((v_day + time '09:00') at time zone 'Asia/Kolkata')
     or (v_res.new_value->>'check_in_at')::timestamptz
        is distinct from ((v_day + time '10:00') at time zone 'Asia/Kolkata') then
    raise exception 'FAIL 12c correction audit contents: %', v_res;
  end if;
  if not exists (select 1 from public.audit_logs
                 where action = 'correct' and entity_id = v_att_id and actor_id = v_admin) then
    raise exception 'FAIL 12d audit_logs missing correction entry';
  end if;

  -- 12e. A manual correction is immune to later automatic events
  perform set_config('request.jwt.claim.sub', v_emp::text, false);
  perform public.record_location_event(
    v_geo, 'ENTER',
    ((v_day + time '09:30') at time zone 'Asia/Kolkata'),
    ((v_day + time '09:30') at time zone 'Asia/Kolkata'),
    12, 'e6', 'OS geofence', '{}');
  perform public.record_location_event(
    v_geo, 'EXIT',
    ((v_day + time '20:00') at time zone 'Asia/Kolkata'),
    ((v_day + time '20:00') at time zone 'Asia/Kolkata'),
    12, 'x6', 'OS geofence', '{}');
  select * into v_att from public.attendance where id = v_att_id;
  if v_att.source is distinct from 'manual'
     or v_att.check_in_at is distinct from ((v_day + time '10:00') at time zone 'Asia/Kolkata')
     or v_att.check_out_at is distinct from ((v_day + time '18:00') at time zone 'Asia/Kolkata')
     or v_att.total_duration_seconds is distinct from 8 * 3600 then
    raise exception 'FAIL 12e manual correction clobbered: %', v_att;
  end if;
  perform set_config('request.jwt.claim.sub', v_admin::text, false);

  -- 13. Absence finalization respects the cutoff and exception days
  select absence_cutoff, working_days into v_cutoff, v_working_saved
    from public.app_settings where id = 1;
  update public.app_settings
     set absence_cutoff = '23:59:59.999999',
         working_days = '{1,2,3,4,5,6,7}'
   where id = 1;
  begin
    perform public.finalize_absences(v_day);
  exception when sqlstate 'P0001' then
    v_cutoff_rejected := true;
    get stacked diagnostics v_cutoff_message = message_text;
  end;
  update public.app_settings set absence_cutoff = v_cutoff where id = 1;
  if not v_cutoff_rejected or v_cutoff_message not like '%cutoff%' then
    raise exception 'FAIL 13a absences finalized before cutoff';
  end if;

  -- 13b. A WFH assignment (with no attendance row) is not finalized as absent
  insert into public.wfh_assignments (user_id, date, reason)
  values (v_emp, v_day + 6, 'test') on conflict do nothing;
  if public.finalize_absences(v_day + 6) <> 0
     or exists (select 1 from public.attendance
                where user_id = v_emp and date = v_day + 6) then
    raise exception 'FAIL 13b WFH day finalized as absent';
  end if;

  -- 13c. A holiday (with no attendance row) is not finalized as absent
  insert into public.holidays (name, date) values ('Exclusion Test', v_day + 7)
  on conflict do nothing;
  if public.finalize_absences(v_day + 7) <> 0
     or exists (select 1 from public.attendance
                where user_id = v_emp and date = v_day + 7) then
    raise exception 'FAIL 13c holiday finalized as absent';
  end if;

  -- 13d. Absence is created for a plain working day after the cutoff
  perform public.finalize_absences(v_day + 3);
  if not exists (select 1 from public.attendance
                 where user_id = v_emp and date = v_day + 3 and status = 'ABSENT') then
    raise exception 'FAIL 13d absence not created';
  end if;

  -- 16. Non-working days are never finalized as absent
  update public.app_settings
     set working_days = array[((extract(isodow from (v_day + 9))::int % 7) + 1)]
   where id = 1;
  if public.finalize_absences(v_day + 9) <> 0
     or exists (select 1 from public.attendance
                where user_id = v_emp and date = v_day + 9 and status = 'ABSENT') then
    raise exception 'FAIL 16 non-working day finalized as absent';
  end if;
  update public.app_settings set working_days = v_working_saved where id = 1;

  -- 14. Non-admin cannot correct attendance
  perform set_config('request.jwt.claim.sub', v_emp::text, false);
  begin
    perform public.apply_manual_correction(v_att_id, 'PRESENT', null, null, 'nope');
    raise exception 'FAIL 14 non-admin correction allowed';
  exception when insufficient_privilege then null;
  end;

  -- 15. Missing and inactive geofences are rejected
  begin
    perform public.record_location_event(
      '00000000-0000-0000-0000-000000000000'::uuid, 'ENTER',
      ((v_day + 8) + time '09:00') at time zone 'Asia/Kolkata',
      ((v_day + 8) + time '09:00') at time zone 'Asia/Kolkata',
      12, 'e7', 'OS geofence', '{}');
  exception when sqlstate 'P0002' then v_missing_rejected := true;
  end;
  if not v_missing_rejected then
    raise exception 'FAIL 15a missing geofence accepted';
  end if;

  insert into public.geofences (id, name, latitude, longitude, radius_meters, active)
  values ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Inactive', 28.6304, 77.2177, 150, false)
  on conflict (id) do nothing;
  begin
    perform public.record_location_event(
      'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid, 'ENTER',
      ((v_day + 8) + time '09:00') at time zone 'Asia/Kolkata',
      ((v_day + 8) + time '09:00') at time zone 'Asia/Kolkata',
      12, 'e8', 'OS geofence', '{}');
  exception when sqlstate 'P0001' then v_inactive_rejected := true;
  end;
  if not v_inactive_rejected then
    raise exception 'FAIL 15b inactive geofence accepted';
  end if;

  raise notice 'ALL ENGINE TESTS PASSED (22 checks)';
end $$;
