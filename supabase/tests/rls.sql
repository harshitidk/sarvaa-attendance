-- ===========================================================================
-- supabase/tests/rls.sql
-- Row Level Security isolation checks. Runs after engine.sql against the same
-- scratch database, as the non-owner `authenticated` role so policies actually
-- apply. All statements run in a transaction that is rolled back.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
-- Employee: sees only self and their own rows.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_emp   uuid := 'e0000000-0000-0000-0000-000000000001';
  v_admin uuid := 'a0000000-0000-0000-0000-000000000001';
  v_count integer;
begin
  select count(*) into v_count from public.users;
  if v_count <> 1 then
    raise exception 'FAIL RLS employee sees % users (expected 1)', v_count;
  end if;
  if not exists (select 1 from public.users where id = v_emp) then
    raise exception 'FAIL RLS employee cannot see own profile';
  end if;

  if exists (select 1 from public.attendance where user_id <> v_emp) then
    raise exception 'FAIL RLS employee sees another employee attendance';
  end if;
  select count(*) into v_count from public.attendance where user_id = v_admin;
  if v_count <> 0 then
    raise exception 'FAIL RLS employee read % admin attendance rows', v_count;
  end if;

  select count(*) into v_count from public.geofences;
  if v_count <> 1 then
    raise exception 'FAIL RLS employee sees % geofences (expected 1 for their location)', v_count;
  end if;

  begin
    perform public.apply_manual_correction(
      (select id from public.attendance limit 1), 'PRESENT', null, null, 'nope');
    raise exception 'FAIL RLS employee corrected attendance';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;

-- ---------------------------------------------------------------------------
-- Admin: sees all rows.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.users;
  if v_count <> 2 then
    raise exception 'FAIL RLS admin sees % users (expected 2)', v_count;
  end if;
  select count(*) into v_count from public.geofences;
  if v_count < 2 then
    raise exception 'FAIL RLS admin sees % geofences (expected at least 2)', v_count;
  end if;
  select count(*) into v_count from public.attendance;
  if v_count < 1 then
    raise exception 'FAIL RLS admin sees no attendance';
  end if;
end $$;

reset role;

rollback;

\echo ALL RLS TESTS PASSED
