-- ===========================================================================
-- supabase/tests/engine.sql
-- Assertion-based tests for the attendance engine, RLS helpers and
-- employee check-out. Runs against a scratch database with an auth stub
-- (see scripts/test-engine.sh). Any failure raises an exception.
--
-- Policy under test (migration 0009): check-in is automatic, check-out is
-- always manual, and there is no automatic absence.
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
  v_missing_rejected boolean := false;
  v_inactive_rejected boolean := false;
  v_outside_rejected boolean := false;
  v_nocoord_rejected boolean := false;
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

  -- 1. ENTER creates PRESENT and opens a session
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    ((v_day + time '09:00') at time zone 'Asia/Kolkata'),
    ((v_day + time '09:00') at time zone 'Asia/Kolkata'),
    12, 'e1', 'OS geofence', '{}', 28.6304, 77.2177);
  if v_res.status <> 'PRESENT' or v_res.check_in_at is null then
    raise exception 'FAIL 1 ENTER: %', v_res;
  end if;
  if (select count(*) from public.attendance_sessions
       where attendance_id = v_res.attendance_id and check_out_at is null) <> 1 then
    raise exception 'FAIL 1b ENTER did not open a session';
  end if;

  -- 2. Duplicate event is idempotent
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    ((v_day + time '09:00') at time zone 'Asia/Kolkata'),
    ((v_day + time '09:00') at time zone 'Asia/Kolkata'),
    12, 'e1', 'OS geofence', '{}', 28.6304, 77.2177);
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

  -- 3. A later ENTER while a session is open does not start a second one
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    ((v_day + time '09:30') at time zone 'Asia/Kolkata'),
    ((v_day + time '09:30') at time zone 'Asia/Kolkata'),
    12, 'e2', 'OS geofence', '{}', 28.6304, 77.2177);
  if v_res.check_in_at is distinct from ((v_day + time '09:00') at time zone 'Asia/Kolkata') then
    raise exception 'FAIL 3 check-in overwritten: %', v_res.check_in_at;
  end if;
  if (select count(*) from public.attendance_sessions
       where attendance_id = v_res.attendance_id) <> 1 then
    raise exception 'FAIL 3 open session duplicated';
  end if;

  -- 4. EXIT does not check out: the visit stays open until a manual check-out
  select * into v_res from public.record_location_event(
    v_geo, 'EXIT',
    ((v_day + time '12:00') at time zone 'Asia/Kolkata'),
    ((v_day + time '12:00') at time zone 'Asia/Kolkata'),
    12, 'x1', 'OS geofence', '{}', 28.6304, 77.2177);
  if v_res.status <> 'PRESENT' or v_res.check_out_at is not null then
    raise exception 'FAIL 4 EXIT auto-checked-out: %', v_res;
  end if;

  -- 5. Manual check-out ends the session, stores the summary and the duration
  select id into v_att_id from public.attendance where user_id = v_emp and date = v_day;
  select * into v_att from public.employee_check_out(
    v_att_id, '  First visit summary  ',
    ((v_day + time '13:00') at time zone 'Asia/Kolkata'), 9, v_geo);
  if v_att.status is distinct from 'CHECKED_OUT'
     or v_att.work_summary is distinct from 'First visit summary'
     or v_att.total_duration_seconds is distinct from 4 * 3600 then
    raise exception 'FAIL 5 manual checkout: %', v_att;
  end if;
  if not exists (
    select 1 from public.attendance_sessions
    where attendance_id = v_att_id and closed_by = 'manual'
      and summary = 'First visit summary' and duration_seconds = 4 * 3600) then
    raise exception 'FAIL 5b session not closed manually';
  end if;

  -- 6. Re-entering after a manual check-out starts a second visit
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    ((v_day + time '14:00') at time zone 'Asia/Kolkata'),
    ((v_day + time '14:00') at time zone 'Asia/Kolkata'),
    12, 'e3', 'OS geofence', '{}', 28.6304, 77.2177);
  if v_res.status <> 'PRESENT' then
    raise exception 'FAIL 6 second visit status: %', v_res;
  end if;
  if (select count(*) from public.attendance_sessions where attendance_id = v_att_id) <> 2 then
    raise exception 'FAIL 6 second visit not recorded';
  end if;

  -- 7. The second visit closes manually and the day total is the sum of visits
  select * into v_att from public.employee_check_out(
    v_att_id, 'Second visit summary',
    ((v_day + time '16:00') at time zone 'Asia/Kolkata'), 9, v_geo);
  if v_att.total_duration_seconds is distinct from 6 * 3600
     or v_att.check_in_at is distinct from ((v_day + time '09:00') at time zone 'Asia/Kolkata')
     or v_att.check_out_at is distinct from ((v_day + time '16:00') at time zone 'Asia/Kolkata') then
    raise exception 'FAIL 7 summed duration: %', v_att;
  end if;

  -- 8. WFH exception wins
  insert into public.wfh_assignments (user_id, date, reason) values (v_emp, v_day + 1, 'test');
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    (((v_day + 1) + time '09:00') at time zone 'Asia/Kolkata'),
    (((v_day + 1) + time '09:00') at time zone 'Asia/Kolkata'),
    12, 'w1', 'OS geofence', '{}', 28.6304, 77.2177);
  if v_res.status <> 'WFH' then
    raise exception 'FAIL 8 WFH: %', v_res.status;
  end if;

  -- 9. Holiday exception wins
  insert into public.holidays (name, date) values ('Test Holiday', v_day + 2);
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    (((v_day + 2) + time '09:00') at time zone 'Asia/Kolkata'),
    (((v_day + 2) + time '09:00') at time zone 'Asia/Kolkata'),
    12, 'h1', 'OS geofence', '{}', 28.6304, 77.2177);
  if v_res.status <> 'HOLIDAY' then
    raise exception 'FAIL 9 HOLIDAY: %', v_res.status;
  end if;

  -- 10. Check-out requires a summary
  select * into v_res from public.record_location_event(
    v_geo, 'ENTER',
    (((v_day + 4) + time '09:00') at time zone 'Asia/Kolkata'),
    (((v_day + 4) + time '09:00') at time zone 'Asia/Kolkata'),
    12, 'e4', 'OS geofence', '{}', 28.6304, 77.2177);
  select id into v_att_id from public.attendance where user_id = v_emp and date = v_day + 4;
  begin
    perform public.employee_check_out(v_att_id, '   ');
    raise exception 'FAIL 10a blank summary accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.employee_check_out(v_att_id, 'ab');
    raise exception 'FAIL 10b short summary accepted';
  exception when sqlstate '22023' then null;
  end;

  -- 11. Check-out stores summary, status and duration
  select * into v_att from public.employee_check_out(
    v_att_id, '  Built the attendance engine  ',
    ((v_day + 4) + time '17:30') at time zone 'Asia/Kolkata', 9, v_geo);
  if v_att.status is distinct from 'CHECKED_OUT'
     or v_att.work_summary is distinct from 'Built the attendance engine'
     or v_att.total_duration_seconds is distinct from 8 * 3600 + 1800 then
    raise exception 'FAIL 11 checkout: %', v_att;
  end if;

  -- 12. Re-submitting a summary keeps the original checkout time
  select * into v_att from public.employee_check_out(
    v_att_id, 'Updated summary',
    ((v_day + 4) + time '19:00') at time zone 'Asia/Kolkata', 9, v_geo);
  if v_att.check_out_at is distinct from ((v_day + 4) + time '17:30') at time zone 'Asia/Kolkata' then
    raise exception 'FAIL 12 checkout time moved: %', v_att.check_out_at;
  end if;

  -- 13. Employees cannot check out someone else's record
  insert into public.attendance (user_id, date, status, check_in_at, source)
  values (v_admin, v_day + 5, 'PRESENT',
          ((v_day + 5) + time '09:00') at time zone 'Asia/Kolkata', 'automatic')
  on conflict (user_id, date) do nothing;
  select id into v_att_id from public.attendance
   where user_id = v_admin and date = v_day + 5;
  begin
    perform public.employee_check_out(v_att_id, 'nope');
    raise exception 'FAIL 13 unauthorized checkout allowed';
  exception when sqlstate '42501' then null;
  end;

  -- 14. Admin correction is audited and replaces the day's sessions
  perform set_config('request.jwt.claim.sub', v_admin::text, false);
  select id into v_att_id from public.attendance where user_id = v_emp and date = v_day;
  select * into v_att from public.apply_manual_correction(
    v_att_id, 'MANUAL_OVERRIDE',
    ((v_day + time '10:00') at time zone 'Asia/Kolkata'),
    ((v_day + time '18:00') at time zone 'Asia/Kolkata'),
    'Device GPS failed');
  if v_att.source is distinct from 'manual'
     or v_att.total_duration_seconds is distinct from 8 * 3600 then
    raise exception 'FAIL 14a correction: %', v_att;
  end if;
  if (select count(*) from public.attendance_corrections where attendance_id = v_att_id) <> 1 then
    raise exception 'FAIL 14b correction not audited';
  end if;
  if exists (select 1 from public.attendance_sessions where attendance_id = v_att_id) then
    raise exception 'FAIL 14c correction left sessions behind';
  end if;
  select * into v_res from public.attendance_corrections where attendance_id = v_att_id;
  if v_res.admin_id is distinct from v_admin
     or v_res.reason is distinct from 'Device GPS failed'
     or (v_res.old_value->>'check_in_at')::timestamptz
        is distinct from ((v_day + time '09:00') at time zone 'Asia/Kolkata')
     or (v_res.new_value->>'check_in_at')::timestamptz
        is distinct from ((v_day + time '10:00') at time zone 'Asia/Kolkata') then
    raise exception 'FAIL 14d correction audit contents: %', v_res;
  end if;
  if not exists (select 1 from public.audit_logs
                 where action = 'correct' and entity_id = v_att_id and actor_id = v_admin) then
    raise exception 'FAIL 14e audit_logs missing correction entry';
  end if;

  -- 14f. A manual correction is immune to later automatic events
  perform set_config('request.jwt.claim.sub', v_emp::text, false);
  perform public.record_location_event(
    v_geo, 'ENTER',
    ((v_day + time '10:30') at time zone 'Asia/Kolkata'),
    ((v_day + time '10:30') at time zone 'Asia/Kolkata'),
    12, 'e6', 'OS geofence', '{}', 28.6304, 77.2177);
  perform public.record_location_event(
    v_geo, 'EXIT',
    ((v_day + time '20:00') at time zone 'Asia/Kolkata'),
    ((v_day + time '20:00') at time zone 'Asia/Kolkata'),
    12, 'x6', 'OS geofence', '{}', 28.6304, 77.2177);
  select * into v_att from public.attendance where id = v_att_id;
  if v_att.source is distinct from 'manual'
     or v_att.check_in_at is distinct from ((v_day + time '10:00') at time zone 'Asia/Kolkata')
     or v_att.check_out_at is distinct from ((v_day + time '18:00') at time zone 'Asia/Kolkata')
     or v_att.total_duration_seconds is distinct from 8 * 3600 then
    raise exception 'FAIL 14f manual correction clobbered: %', v_att;
  end if;

  -- 15. Non-admin cannot correct attendance
  begin
    perform public.apply_manual_correction(v_att_id, 'PRESENT', null, null, 'nope');
    raise exception 'FAIL 15 non-admin correction allowed';
  exception when insufficient_privilege then null;
  end;

  -- 16. Missing and inactive geofences are rejected
  begin
    perform public.record_location_event(
      '00000000-0000-0000-0000-000000000000'::uuid, 'ENTER',
      ((v_day + 8) + time '09:00') at time zone 'Asia/Kolkata',
      ((v_day + 8) + time '09:00') at time zone 'Asia/Kolkata',
      12, 'e7', 'OS geofence', '{}', 28.6304, 77.2177);
  exception when sqlstate 'P0002' then v_missing_rejected := true;
  end;
  if not v_missing_rejected then
    raise exception 'FAIL 16a missing geofence accepted';
  end if;

  insert into public.geofences (id, name, latitude, longitude, radius_meters, active)
  values ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Inactive', 28.6304, 77.2177, 150, false)
  on conflict (id) do nothing;
  begin
    perform public.record_location_event(
      'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid, 'ENTER',
      ((v_day + 8) + time '09:00') at time zone 'Asia/Kolkata',
      ((v_day + 8) + time '09:00') at time zone 'Asia/Kolkata',
      12, 'e8', 'OS geofence', '{}', 28.6304, 77.2177);
  exception when sqlstate 'P0001' then v_inactive_rejected := true;
  end;
  if not v_inactive_rejected then
    raise exception 'FAIL 16b inactive geofence accepted';
  end if;

  -- 17. A check-in from outside the geofence is rejected server-side
  begin
    perform public.record_location_event(
      v_geo, 'ENTER',
      ((v_day + 11) + time '09:00') at time zone 'Asia/Kolkata',
      ((v_day + 11) + time '09:00') at time zone 'Asia/Kolkata',
      12, 'e9', 'OS geofence', '{}', 28.7000, 77.3000);
  exception when sqlstate '22023' then v_outside_rejected := true;
  end;
  if not v_outside_rejected then
    raise exception 'FAIL 17 outside check-in accepted';
  end if;
  if exists (select 1 from public.attendance where user_id = v_emp and date = v_day + 11) then
    raise exception 'FAIL 17b outside check-in created attendance';
  end if;

  -- 18. A check-in without coordinates is rejected
  begin
    perform public.record_location_event(
      v_geo, 'ENTER',
      ((v_day + 12) + time '09:00') at time zone 'Asia/Kolkata',
      ((v_day + 12) + time '09:00') at time zone 'Asia/Kolkata',
      12, 'e10', 'OS geofence', '{}');
  exception when sqlstate '22023' then v_nocoord_rejected := true;
  end;
  if not v_nocoord_rejected then
    raise exception 'FAIL 18 check-in without coordinates accepted';
  end if;

  raise notice 'ALL ENGINE TESTS PASSED (26 checks)';
end $$;
