#!/usr/bin/env bash
# Runs the attendance engine tests against a throwaway local Postgres database.
# No Docker or Supabase CLI required — only psql and a running Postgres.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="geo_engine_test"

command -v psql >/dev/null 2>&1 || { echo "psql not found"; exit 1; }
pg_isready >/dev/null 2>&1 || { echo "No local Postgres available on :5432"; exit 1; }

cleanup() { dropdb --if-exists "$DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
createdb "$DB"

echo "Creating auth stubs..."
psql -q -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'
create extension if not exists pgcrypto;
create schema if not exists auth;
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'create role authenticated';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'create role anon';
  end if;
end $$;
create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  raw_user_meta_data jsonb default '{}'::jsonb
);
create or replace function auth.uid() returns uuid language sql stable as
$$ select null::uuid $$;
SQL

echo "Applying migrations..."
for file in "$ROOT"/supabase/migrations/*.sql; do
  echo "  -> $(basename "$file")"
  psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$file" >/dev/null
done

echo "Seeding..."
psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$ROOT/supabase/seed.sql" >/dev/null

# Supabase grants these to `authenticated` at bootstrap; the scratch database
# needs them too so RLS policies are reachable by a non-owner role.
echo "Granting client privileges..."
psql -q -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'
grant usage on schema public, auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant select on all tables in schema public to authenticated;
SQL

run_suite() {
  local file="$1" sentinel="$2" label="$3"
  echo "Running $label..."
  if ! out="$(psql -d "$DB" -v ON_ERROR_STOP=1 -f "$file" 2>&1)"; then
    echo "$out" >&2
    exit 1
  fi
  echo "$out"
  if ! grep -q "$sentinel" <<<"$out"; then
    echo "$label sentinel missing — the assertion block did not run to completion" >&2
    exit 1
  fi
}

run_suite "$ROOT/supabase/tests/engine.sql" 'ALL ENGINE TESTS PASSED' "engine tests"
run_suite "$ROOT/supabase/tests/rls.sql" 'ALL RLS TESTS PASSED' "RLS tests"
run_suite "$ROOT/supabase/tests/wfh.sql" 'ALL WFH TESTS PASSED' "WFH request tests"
run_suite "$ROOT/supabase/tests/leave.sql" 'ALL LEAVE TESTS PASSED' "leave request tests"

echo "Engine tests passed."
