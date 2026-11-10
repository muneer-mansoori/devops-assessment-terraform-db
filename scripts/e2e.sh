#!/usr/bin/env bash
# End-to-end check of the database tasks, exactly as a reviewer would run them, from a clean slate:
#   docker compose up  ->  backup.sh  ->  restore.sh (verified)  ->  explain.sh (index used)
#
#   ./scripts/e2e.sh          # WARNING: removes the local hotel-booking volume first
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "resetting local stack (docker compose down -v)"
"${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true

log "starting database (migrations + seed run on first start)"
"${COMPOSE[@]}" up -d --wait

require_db_running
log "seed check: $(scalar "$POSTGRES_DB" "SELECT count(*) FROM hotel_bookings") bookings"

"$ROOT/scripts/backup.sh" >/dev/null
"$ROOT/scripts/restore.sh" >/dev/null

PLAN="$("$ROOT/scripts/explain.sh")"
printf '%s\n' "$PLAN"
AFTER="${PLAN##*=== AFTER}"
grep -q "Index Only Scan using idx_hotel_bookings_city_created_at" <<<"$AFTER" \
  || die "expected an Index Only Scan on idx_hotel_bookings_city_created_at"

log "E2E PASSED: database seeded, backup verified, restore verified, index used"
