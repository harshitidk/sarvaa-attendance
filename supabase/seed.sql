-- ===========================================================================
-- seed.sql — local development data (safe to re-run)
-- Auth users are intentionally NOT seeded here: create them through the
-- Supabase Auth API / Studio so password hashing and identities stay correct.
-- After creating an auth user, set its profile with:
--
--   update public.users
--      set employee_id = 'EMP-0001', name = 'Admin User', role = 'admin'
--    where email = 'admin@example.com';
-- ===========================================================================

-- Company configuration
update public.app_settings
   set company_timezone   = 'Asia/Kolkata',
       workday_start      = '09:00',
       workday_end        = '18:00',
       exit_grace_seconds = 300
 where id = 1;

-- Offices
insert into public.locations (id, name, address, timezone)
values
  ('11111111-1111-1111-1111-111111111111', 'Delhi HQ', 'Connaught Place, New Delhi', 'Asia/Kolkata'),
  ('22222222-2222-2222-2222-222222222222', 'Bengaluru Office', 'Koramangala, Bengaluru', 'Asia/Kolkata')
on conflict (id) do nothing;

-- Geofences (~150m radius around each office)
insert into public.geofences (id, name, latitude, longitude, radius_meters, location_id, active)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Delhi HQ',        28.6304, 77.2177, 150,
     '11111111-1111-1111-1111-111111111111', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Bengaluru Office', 12.9352, 77.6245, 150,
     '22222222-2222-2222-2222-222222222222', true)
on conflict (id) do nothing;

-- Company-wide holiday example
insert into public.holidays (name, date, location_id)
values ('Republic Day', '2026-01-26', null)
on conflict do nothing;
