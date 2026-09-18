-- ===========================================================================
-- 0002_rls.sql — Row Level Security & helpers
-- Authorization is enforced database-side, never only in the UI.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and role = 'admin' and status = 'active'
  );
$$;

create or replace function public.is_active_user()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and status = 'active'
  );
$$;

create or replace function public.app_timezone()
returns text
language sql stable security definer set search_path = public as $$
  select company_timezone from public.app_settings where id = 1;
$$;

grant execute on function public.is_admin()      to authenticated;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.app_timezone()  to authenticated;

-- ---------------------------------------------------------------------------
-- Enable RLS
-- ---------------------------------------------------------------------------
alter table public.app_settings          enable row level security;
alter table public.locations             enable row level security;
alter table public.users                 enable row level security;
alter table public.geofences             enable row level security;
alter table public.employee_geofences    enable row level security;
alter table public.attendance            enable row level security;
alter table public.location_events       enable row level security;
alter table public.holidays              enable row level security;
alter table public.wfh_assignments       enable row level security;
alter table public.attendance_corrections enable row level security;
alter table public.audit_logs            enable row level security;

-- ---------------------------------------------------------------------------
-- app_settings: readable by authenticated, writable by admins only
-- ---------------------------------------------------------------------------
drop policy if exists app_settings_select on public.app_settings;
create policy app_settings_select on public.app_settings
  for select to authenticated using (true);

drop policy if exists app_settings_admin_write on public.app_settings;
create policy app_settings_admin_write on public.app_settings
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- locations
-- ---------------------------------------------------------------------------
drop policy if exists locations_select on public.locations;
create policy locations_select on public.locations
  for select to authenticated using (true);

drop policy if exists locations_admin_write on public.locations;
create policy locations_admin_write on public.locations
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- users: employees read self; admins read/write all
-- ---------------------------------------------------------------------------
drop policy if exists users_select_self on public.users;
create policy users_select_self on public.users
  for select to authenticated using (id = auth.uid());

drop policy if exists users_admin_all on public.users;
create policy users_admin_all on public.users
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- geofences: employees see active geofences for their location or assigned
-- ---------------------------------------------------------------------------
drop policy if exists geofences_select on public.geofences;
create policy geofences_select on public.geofences
  for select to authenticated using (
    public.is_admin()
    or (
      active
      and (
        exists (select 1 from public.employee_geofences eg
                where eg.geofence_id = geofences.id and eg.user_id = auth.uid())
        or location_id is null
        or location_id = (select location_id from public.users where id = auth.uid())
      )
    )
  );

drop policy if exists geofences_admin_write on public.geofences;
create policy geofences_admin_write on public.geofences
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- employee_geofences
-- ---------------------------------------------------------------------------
drop policy if exists employee_geofences_select on public.employee_geofences;
create policy employee_geofences_select on public.employee_geofences
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists employee_geofences_admin_write on public.employee_geofences;
create policy employee_geofences_admin_write on public.employee_geofences
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- attendance: employees read own; admins read/write all.
-- Employee writes happen only through the security-definer engine functions.
-- ---------------------------------------------------------------------------
drop policy if exists attendance_select on public.attendance;
create policy attendance_select on public.attendance
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists attendance_admin_write on public.attendance;
create policy attendance_admin_write on public.attendance
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- location_events: employees read own; admins read all. Writes via engine only.
-- ---------------------------------------------------------------------------
drop policy if exists location_events_select on public.location_events;
create policy location_events_select on public.location_events
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- ---------------------------------------------------------------------------
-- holidays: readable by all authenticated; admins write
-- ---------------------------------------------------------------------------
drop policy if exists holidays_select on public.holidays;
create policy holidays_select on public.holidays
  for select to authenticated using (true);

drop policy if exists holidays_admin_write on public.holidays;
create policy holidays_admin_write on public.holidays
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- wfh_assignments: employees read own; admins write
-- ---------------------------------------------------------------------------
drop policy if exists wfh_select on public.wfh_assignments;
create policy wfh_select on public.wfh_assignments
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists wfh_admin_write on public.wfh_assignments;
create policy wfh_admin_write on public.wfh_assignments
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- attendance_corrections: employees read corrections for their own records
-- ---------------------------------------------------------------------------
drop policy if exists corrections_select on public.attendance_corrections;
create policy corrections_select on public.attendance_corrections
  for select to authenticated using (
    public.is_admin()
    or exists (
      select 1 from public.attendance a
      where a.id = attendance_corrections.attendance_id and a.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- audit_logs: admins only
-- ---------------------------------------------------------------------------
drop policy if exists audit_logs_select on public.audit_logs;
create policy audit_logs_select on public.audit_logs
  for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------------
-- Audit triggers for administrative tables
-- ---------------------------------------------------------------------------
create or replace function public.audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_action text := lower(tg_op);
  v_entity_id uuid;
begin
  if tg_op = 'DELETE' then
    v_entity_id := old.id;
  else
    v_entity_id := new.id;
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    v_action,
    tg_table_name,
    v_entity_id,
    jsonb_build_object(
      'old', case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
      'new', case when tg_op in ('UPDATE','INSERT') then to_jsonb(new) else null end
    )
  );
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['geofences', 'holidays', 'wfh_assignments', 'locations', 'users']
  loop
    execute format('drop trigger if exists trg_%s_audit on public.%I', t, t);
    execute format('create trigger trg_%s_audit after insert or update or delete on public.%I
                    for each row execute function public.audit_row()', t, t);
  end loop;
end $$;
