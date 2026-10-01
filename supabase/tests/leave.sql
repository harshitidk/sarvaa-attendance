-- ===========================================================================
-- supabase/tests/leave.sql
-- Leave requests (migration 0007) and the work-summary edit window.
-- Runs against the same scratch database as engine.sql. Any failure raises.
--
-- The point of these checks: approval must be the *only* path from a request
-- to a real LEAVE day, and an employee must never grant themselves one by
-- writing the table directly. The summary, once written, freezes on schedule.
-- ===========================================================================

do $$
declare
  v_emp    uuid := 'e0000000-0000-0000-0000-000000000001';
  v_admin  uuid := 'a0000000-0000-0000-0000-000000000001';
  v_future date := (now() at time zone 'Asia/Kolkata')::date + 7;
  v_req    public.leave_requests;
  v_count  integer;
  v_blocked boolean;
begin
  delete from public.leave_requests where user_id = v_emp;
  delete from public.attendance where user_id = v_emp and date in (v_future, v_future + 1);

  -- ==================================================================== 1
  -- An employee files a request for themselves.
  -- ====================================================================
  perform set_config('request.jwt.claim.sub', v_emp::text, false);
  insert into public.leave_requests (user_id, date, leave_type, reason)
  values (v_emp, v_future, 'sick', 'Down with fever')
  returning * into v_req;

  if v_req.status <> 'pending' then
    raise exception 'FAIL 1 new request should be pending, got %', v_req.status;
  end if;

  -- ==================================================================== 2
  -- Filing does NOT itself create a LEAVE day.
  -- ====================================================================
  if exists (select 1 from public.attendance
             where user_id = v_emp and date = v_future) then
    raise exception 'FAIL 2 a pending request must not grant leave';
  end if;

  -- ==================================================================== 3
  -- A non-admin cannot review — not even their own request.
  -- ====================================================================
  v_blocked := false;
  begin
    perform public.review_leave_request(v_req.id, true, 'self-approved');
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL 3 an employee approved their own leave';
  end if;

  -- ==================================================================== 4
  -- Admin approval materialises the LEAVE row the finalizer reads.
  -- ====================================================================
  perform set_config('request.jwt.claim.sub', v_admin::text, false);
  select * into v_req from public.review_leave_request(v_req.id, true, 'Rest up');

  if v_req.status <> 'approved' or v_req.reviewed_by <> v_admin
     or v_req.reviewed_at is null then
    raise exception 'FAIL 4 approval did not record the decision: %', v_req;
  end if;
  if not exists (select 1 from public.attendance
                 where user_id = v_emp and date = v_future
                   and status = 'LEAVE' and leave_request_id = v_req.id) then
    raise exception 'FAIL 4 approval did not create the LEAVE day';
  end if;

  -- ==================================================================== 5
  -- A decided request cannot be decided again.
  -- ====================================================================
  v_blocked := false;
  begin
    perform public.review_leave_request(v_req.id, false, 'changed my mind');
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL 5 an approved request was reviewed twice';
  end if;

  -- ==================================================================== 6
  -- Rejection leaves no leave day behind.
  -- ====================================================================
  perform set_config('request.jwt.claim.sub', v_emp::text, false);
  insert into public.leave_requests (user_id, date, leave_type, reason)
  values (v_emp, v_future + 1, 'paid', 'Family function')
  returning * into v_req;

  perform set_config('request.jwt.claim.sub', v_admin::text, false);
  select * into v_req from public.review_leave_request(v_req.id, false, 'Need you on site');

  if v_req.status <> 'rejected' then
    raise exception 'FAIL 6 rejection did not set the status, got %', v_req.status;
  end if;
  if exists (select 1 from public.attendance
             where user_id = v_emp and date = v_future + 1) then
    raise exception 'FAIL 6 a rejected request granted leave';
  end if;

  -- ==================================================================== 7
  -- Both decisions are auditable.
  -- ====================================================================
  select count(*) into v_count from public.audit_logs
   where entity_type = 'leave_requests'
     and action in ('leave_request_approved', 'leave_request_rejected');
  if v_count < 2 then
    raise exception 'FAIL 7 expected approve+reject in the audit log, got %', v_count;
  end if;

  -- ==================================================================== 8
  -- A reason is mandatory and must be meaningful.
  -- ====================================================================
  perform set_config('request.jwt.claim.sub', v_emp::text, false);
  v_blocked := false;
  begin
    insert into public.leave_requests (user_id, date, leave_type, reason)
    values (v_emp, v_future + 2, 'sick', 'ab');
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL 8 a too-short reason was accepted';
  end if;

  -- ==================================================================== 9
  -- An approved leave is immune to automatic geofence events.
  -- ====================================================================
  perform public.record_location_event(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'ENTER',
    ((v_future + time '09:00') at time zone 'Asia/Kolkata'),
    ((v_future + time '09:00') at time zone 'Asia/Kolkata'),
    12, 'leave-e1', 'OS geofence', '{}');
  if (select status from public.attendance
        where user_id = v_emp and date = v_future) is distinct from 'LEAVE' then
    raise exception 'FAIL 9 automatic event overwrote an approved leave';
  end if;

  raise notice 'leave: all assertions passed';
end $$;

-- ---------------------------------------------------------------------------
-- The work-summary edit window: open just after check-out, frozen later.
-- ---------------------------------------------------------------------------
do $$
declare
  v_emp   uuid := 'e0000000-0000-0000-0000-000000000001';
  v_day   date := (now() at time zone 'Asia/Kolkata')::date - 20;
  v_att_id uuid;
  v_att   public.attendance;
  v_blocked boolean;
begin
  insert into public.attendance
    (user_id, date, status, check_in_at, check_out_at, work_summary, work_summary_at, source)
  values
    (v_emp, v_day, 'CHECKED_OUT',
     ((v_day + time '09:00') at time zone 'Asia/Kolkata'),
     ((v_day + time '17:00') at time zone 'Asia/Kolkata'),
     'Original summary', now() - interval '50 minutes', 'automatic')
  on conflict (user_id, date) do update
    set status = excluded.status,
        check_in_at = excluded.check_in_at,
        check_out_at = excluded.check_out_at,
        work_summary = excluded.work_summary,
        work_summary_at = excluded.work_summary_at,
        source = excluded.source
  returning id into v_att_id;

  perform set_config('request.jwt.claim.sub', v_emp::text, false);

  -- 10. Editing after the window is refused.
  v_blocked := false;
  begin
    perform public.employee_check_out(v_att_id, 'Changed my story');
  exception when sqlstate 'P0001' then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL 10 summary edited after the window closed';
  end if;

  -- 11. Re-submitting the same text is a harmless no-op.
  select * into v_att from public.employee_check_out(v_att_id, 'Original summary');
  if v_att.work_summary is distinct from 'Original summary' then
    raise exception 'FAIL 11 identical resubmit changed the summary';
  end if;

  -- 12. A fresh summary (window open) can be revised.
  update public.attendance set work_summary_at = now() - interval '5 minutes'
   where id = v_att_id;
  select * into v_att from public.employee_check_out(v_att_id, 'Revised summary');
  if v_att.work_summary is distinct from 'Revised summary' then
    raise exception 'FAIL 12 an in-window edit was refused';
  end if;

  -- 13. Editing does not restart the clock.
  if v_att.work_summary_at > now() - interval '4 minutes' then
    raise exception 'FAIL 13 editing restarted the summary window';
  end if;

  raise notice 'summary window: all assertions passed';
end $$;

-- ---------------------------------------------------------------------------
-- RLS: the same rules, enforced against the non-owner `authenticated` role.
-- ---------------------------------------------------------------------------
begin;

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_emp    uuid := 'e0000000-0000-0000-0000-000000000001';
  v_emp2   uuid := 'e0000000-0000-0000-0000-000000000002';
  v_future date := (now() at time zone 'Asia/Kolkata')::date + 21;
  v_past   date := (now() at time zone 'Asia/Kolkata')::date - 5;
  v_blocked boolean;
begin
  -- Self-approval by direct write is the attack this policy exists to stop.
  v_blocked := false;
  begin
    insert into public.leave_requests (user_id, date, leave_type, reason, status)
    values (v_emp, v_future, 'sick', 'Because', 'approved');
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL RLS employee inserted an approved leave request';
  end if;

  -- Nor may they file on someone else's behalf.
  v_blocked := false;
  begin
    insert into public.leave_requests (user_id, date, leave_type, reason)
    values (v_emp2, v_future, 'sick', 'For a friend');
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL RLS employee filed leave for another user';
  end if;

  -- Backdating would retroactively excuse an absence.
  v_blocked := false;
  begin
    insert into public.leave_requests (user_id, date, leave_type, reason)
    values (v_emp, v_past, 'unpaid', 'Wishful thinking');
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL RLS employee backdated a leave request';
  end if;

  -- A plain pending request for themselves is allowed.
  insert into public.leave_requests (user_id, date, leave_type, reason)
  values (v_emp, v_future, 'unpaid', 'Personal');

  -- They must not see other people's requests.
  if exists (select 1 from public.leave_requests where user_id <> v_emp) then
    raise exception 'FAIL RLS employee can read other leave requests';
  end if;

  raise notice 'leave rls: all assertions passed';
end $$;

rollback;

select 'ALL LEAVE TESTS PASSED' as result;
