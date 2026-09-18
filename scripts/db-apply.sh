#!/usr/bin/env bash
# Apply migrations + seed to a hosted (or any remote) Postgres without Docker.
#
#   cp .env.example .env      # set SUPABASE_DB_URL (Project Settings -> Database)
#   ./scripts/db-apply.sh
#
# Uses psql directly, so no Supabase CLI / Docker is required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/.env"
  set +a
fi

: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL in .env (Project Settings -> Database -> Connection string -> URI)}"

command -v psql >/dev/null 2>&1 || { echo "psql not found (install libpq / postgresql)"; exit 1; }

echo "Applying migrations to the remote database..."
for file in "$ROOT"/supabase/migrations/*.sql; do
  echo "  -> $(basename "$file")"
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -q -f "$file"
done

echo "  -> seed.sql"
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -q -f "$ROOT/supabase/seed.sql"

echo "Done. Migrations and seed applied."
echo "Note: this bootstraps the schema directly; it is not recorded in supabase_migrations."
