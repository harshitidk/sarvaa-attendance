#!/usr/bin/env bash
# Regenerates supabase/bootstrap.sql from the migrations + seed.
# Keep this the single source of truth: run it after adding a migration.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/supabase/bootstrap.sql"

{
  printf '%s\n' \
    '-- ===========================================================================' \
    '-- bootstrap.sql — schema + RLS + attendance engine + seed (generated)' \
    '-- Paste into the Supabase SQL Editor and Run, or apply via scripts/db-apply.sh' \
    '-- ===========================================================================' \
    '' ''

  for file in "$ROOT"/supabase/migrations/*.sql; do
    printf '\n-- >>> supabase/migrations/%s\n\n' "$(basename "$file")"
    cat "$file"
  done

  printf '\n-- >>> supabase/seed.sql\n\n'
  cat "$ROOT/supabase/seed.sql"
} >"$OUT"

echo "Wrote $OUT"
