-- ===========================================================================
-- supabase/tests/wfh.sql
-- Work-from-home requests and company WFH days (migration 0006).
-- Runs against the same scratch database as engine.sql. Any failure raises.
--
-- The point of these checks: approval must be the *only* path from a request
-- to a real WFH day, and an employee must never be able to grant themselves
-- one by writing the table directly.
-- ===========================================================================

do $$
declare
  v_emp    uuid := 'e0000000-0000-0000-0000-000000000001';
  v_emp2   uuid := 'e0000000-0000-0000-0000-000000000002';
  v_admin  uuid := 'a0000000-0000-0000-0000-000000000001';
  v_future date := (now() at time zone 'Asia/Kolkata')::date + 7;
  v_past   date := (now() at time zone 'Asia/Kolkata')::date - 3;
  v_req    public.wfh_requests;
  v_day    public.company_wfh_days;
  v_id     uuid;
  v_count  integer;
  v_blocked boolean;
begin
  -- A second employee, so company-wide actions have more than one target.
  delete from auth.users where id = v_emp2;
  insert into auth.users (id, email, raw_user_meta_data) values
    (v_emp2, 'emp2@test.com',
     jsonb_build_object('employee_id','EMP-2048','name','Second Emp','role','employee'));

  delete from public.wfh_requests where user_id in (v_emp, v_emp2);
  delete from public.wfh_assignments where user_id in (v_emp, v_emp2);
  delete from public.company_wfh_days where date in (v_future, v_past);

  -- ==================================================================== 1
  -- An employee files a request for themselves.
  -- ==================================================================== 
  perform set_config('request.jwt.claim.sub', v_emp::text, false);
  insert into public.wfh_requests (user_id, date, reason)
  values (v_emp, v_future, 'Plumber coming')
  returning * into v_req;

  if v_req.status <> 'pending' then
    raise exception 'FAIL 1 new request should be pending, got %', v_req.status;
  end if;

  -- ==================================================================== 2
  -- Filing does NOT itself create a WFH day.
  -- ====================================================================
  if exists (select 1 from public.wfh_assignments
             where user_id = v_emp and date = v_future) then
    raise exception 'FAIL 2 a pending request must not grant WFH';
  end if;

  -- ==================================================================== 3
  -- A non-admin cannot review — not even their own request.
  -- ====================================================================
  v_blocked := false;
  begin
    perform public.review_wfh_request(v_req.id, true, 'self-approved');
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL 3 an employee approved their own request';
  end if;

  -- ==================================================================== 4
  -- Admin approval materialises the WFH day the engine reads.
  -- ====================================================================
  perform set_config('request.jwt.claim.sub', v_admin::text, false);
  select * into v_req from public.review_wfh_request(v_req.id, true, 'Fine');

  if v_req.status <> 'approved' or v_req.reviewed_by <> v_admin
     or v_req.reviewed_at is null then
    raise exception 'FAIL 4 approval did not record the decision: %', v_req;
  end if;
  if not exists (select 1 from public.wfh_assignments
                 where user_id = v_emp and date = v_future
                   and request_id = v_req.id) then
    raise exception 'FAIL 4 approval did not create the WFH assignment';
  end if;

  -- ==================================================================== 5
  -- A decided request cannot be decided again.
  -- ====================================================================
  v_blocked := false;
  begin
    perform public.review_wfh_request(v_req.id, false, 'changed my mind');
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL 5 an approved request was reviewed twice';
  end if;

  -- ==================================================================== 6
  -- Rejection leaves no WFH day behind.
  -- ====================================================================
  perform set_config('request.jwt.claim.sub', v_emp2::text, false);
  insert into public.wfh_requests (user_id, date, reason)
  values (v_emp2, v_future, 'Also plumber')
  returning * into v_req;

  perform set_config('request.jwt.claim.sub', v_admin::text, false);
  select * into v_req from public.review_wfh_request(v_req.id, false, 'Need you on site');

  if v_req.status <> 'rejected' then
    raise exception 'FAIL 6 rejection did not set the status, got %', v_req.status;
  end if;
  if exists (select 1 from public.wfh_assignments
             where user_id = v_emp2 and date = v_future) then
    raise exception 'FAIL 6 a rejected request granted WFH';
  end if;

  -- ==================================================================== 7
  -- Both decisions are auditable.
  -- ====================================================================
  select count(*) into v_count from public.audit_logs
   where entity_type = 'wfh_requests'
     and action in ('wfh_request_approved', 'wfh_request_rejected');
  if v_count < 2 then
    raise exception 'FAIL 7 expected approve+reject in the audit log, got %', v_count;
  end if;

  -- ==================================================================== 8
  -- A company WFH day covers the whole active roster.
  -- ====================================================================
  delete from public.wfh_assignments where date = v_past;
  select * into v_day from public.set_company_wfh_day(v_past, 'Office fumigation');

  select count(*) into v_count from public.wfh_assignments
   where date = v_past and company_day_id = v_day.id;
  if v_count < 2 then
    raise exception 'FAIL 8 company day covered % employees (expected >= 2)', v_count;
  end if;

  -- ==================================================================== 9
  -- Clearing it removes only what it created.
  -- ====================================================================
  insert into public.wfh_assignments (user_id, date, reason, created_by)
  values (v_emp, v_past + 1, 'Granted individually', v_admin);

  perform public.clear_company_wfh_day(v_day.id);

  if exists (select 1 from public.wfh_assignments where company_day_id = v_day.id) then
    raise exception 'FAIL 9 clearing left its own assignments behind';
  end if;
  if exists (select 1 from public.company_wfh_days where id = v_day.id) then
    raise exception 'FAIL 9 the company day row survived';
  end if;
  if not exists (select 1 from public.wfh_assignments
                 where user_id = v_emp and date = v_past + 1) then
    raise exception 'FAIL 9 clearing destroyed an individually granted WFH day';
  end if;

  -- ==================================================================== 10
  -- Only an admin may set or clear a company day.
  -- ====================================================================
  perform set_config('request.jwt.claim.sub', v_emp::text, false);
  v_blocked := false;
  begin
    perform public.set_company_wfh_day(v_future + 1, 'nice try');
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL 10 an employee declared a company WFH day';
  end if;

  raise notice 'wfh: all assertions passed';
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
  v_future date := (now() at time zone 'Asia/Kolkata')::date + 14;
  v_past   date := (now() at time zone 'Asia/Kolkata')::date - 5;
  v_blocked boolean;
begin
  -- Self-approval by direct write is the attack this policy exists to stop.
  v_blocked := false;
  begin
    insert into public.wfh_requests (user_id, date, status)
    values (v_emp, v_future, 'approved');
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL RLS employee inserted an approved request';
  end if;

  -- Nor may they file on someone else's behalf.
  v_blocked := false;
  begin
    insert into public.wfh_requests (user_id, date) values (v_emp2, v_future);
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL RLS employee filed a request for another user';
  end if;

  -- Backdating would retroactively excuse an absence.
  v_blocked := false;
  begin
    insert into public.wfh_requests (user_id, date) values (v_emp, v_past);
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL RLS employee backdated a request';
  end if;

  -- A plain pending request for themselves is allowed.
  insert into public.wfh_requests (user_id, date, reason)
  values (v_emp, v_future, 'Legitimate');

  -- They must not see other people's requests.
  if exists (select 1 from public.wfh_requests where user_id <> v_emp) then
    raise exception 'FAIL RLS employee can read other requests';
  end if;

  -- Writing wfh_assignments directly stays admin-only.
  v_blocked := false;
  begin
    insert into public.wfh_assignments (user_id, date) values (v_emp, v_future);
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'FAIL RLS employee granted themselves a WFH assignment';
  end if;

  raise notice 'wfh rls: all assertions passed';
end $$;

rollback;

select 'ALL WFH TESTS PASSED' as result;
