-- ===========================================================================
-- 0011_attendance_opt_in.sql
--
-- Admins may track their own attendance too. Employees are tracked by default;
-- admins opt in from Settings and can opt out again. The flag lives on the
-- user row, so it is backend state shared by every app.
-- ===========================================================================

alter table public.users
  add column if not exists attendance_enabled boolean not null default false;

-- Existing employees are tracked; existing admins are not (until they opt in).
update public.users
   set attendance_enabled = true
 where role = 'employee' and attendance_enabled = false;

-- New users inherit the rule: employees on, admins off, unless metadata says
-- otherwise (`attendance_enabled` in raw_user_meta_data).
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_role public.user_role :=
    coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'employee');
begin
  insert into public.users
    (id, employee_id, name, email, role, department, location_id, attendance_enabled)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'employee_id', 'EMP-' || left(new.id::text, 8)),
    coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)),
    new.email,
    v_role,
    new.raw_user_meta_data ->> 'department',
    nullif(new.raw_user_meta_data ->> 'location_id', '')::uuid,
    coalesce(
      (new.raw_user_meta_data ->> 'attendance_enabled')::boolean,
      v_role <> 'admin'
    )
  )
  on conflict (id) do nothing;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- set_my_attendance_enabled — any user may toggle their own tracking flag.
-- (Admins can already write all users; this keeps the self-service path simple
-- and works regardless of role.)
-- ---------------------------------------------------------------------------
create or replace function public.set_my_attendance_enabled(p_enabled boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  update public.users
     set attendance_enabled = coalesce(p_enabled, false)
   where id = v_uid;

  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;

  return coalesce(p_enabled, false);
end $$;

revoke all on function public.set_my_attendance_enabled(boolean) from public, anon;
grant execute on function public.set_my_attendance_enabled(boolean) to authenticated;
