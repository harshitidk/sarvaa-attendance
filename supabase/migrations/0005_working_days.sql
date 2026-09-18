-- ===========================================================================
-- 0005_working_days.sql
-- Configurable working days (ISO weekday numbers: 1=Mon .. 7=Sun). Absence
-- finalization must never mark a non-working day as ABSENT.
-- ===========================================================================

alter table public.app_settings
  add column if not exists working_days integer[] not null default '{1,2,3,4,5,6}';

-- ---------------------------------------------------------------------------
-- finalize_absences — skip days that are not configured as working days.
-- ---------------------------------------------------------------------------
create or replace function public.finalize_absences(p_date date default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_date    date;
  v_tz      text;
  v_cutoff  time;
  v_working integer[];
  v_count   integer := 0;
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;

  v_tz := public.app_timezone();
  v_date := coalesce(p_date, (now() at time zone v_tz)::date);
  select absence_cutoff, working_days into v_cutoff, v_working
    from public.app_settings where id = 1;

  if v_date = (now() at time zone v_tz)::date
     and (now() at time zone v_tz)::time < v_cutoff then
    raise exception 'absence cutoff (%) not reached for %', v_cutoff, v_date
      using errcode = 'P0001';
  end if;

  if not (extract(isodow from v_date)::int = any(v_working)) then
    return 0;
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

revoke all on function public.finalize_absences(date) from public, anon;
grant execute on function public.finalize_absences(date) to authenticated;
