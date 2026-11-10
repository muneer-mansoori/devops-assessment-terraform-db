#!/usr/bin/env bash
# Shared helpers for the database scripts. Sourced, not executed. Compatible with macOS bash 3.2.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

# Load .env if present so the scripts and docker compose agree on credentials.
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/.env"
  set +a
fi

POSTGRES_USER="${POSTGRES_USER:-hotel}"
POSTGRES_DB="${POSTGRES_DB:-hotel_db}"
DB_SERVICE="${DB_SERVICE:-db}"
BACKUP_DIR="${BACKUP_DIR:-$ROOT/backups}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  die "docker compose is not installed"
fi

# Run psql inside the db container. Extra args are passed through (stdin works with -T).
psql_in() {
  local db="$1"; shift
  "${COMPOSE[@]}" exec -T "$DB_SERVICE" psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" "$@"
}

# Single scalar query result, no headers or padding.
scalar() {
  local db="$1" sql="$2"
  psql_in "$db" -tA -c "$sql"
}

require_db_running() {
  local i
  for i in $(seq 1 60); do
    if "${COMPOSE[@]}" exec -T "$DB_SERVICE" pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
      return 0
    fi
    [[ "$i" == 1 ]] && log "waiting for database (run 'docker compose up -d' if it is not started)..."
    sleep 2
  done
  die "database service '$DB_SERVICE' is not ready"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Fingerprint of a database: per-table row counts plus a content md5 (rows hashed in primary-key order).
# Used to prove a restored database is identical to the source.
fingerprint() {
  local db="$1"
  # Explicit sort key: UNION ALL has no guaranteed output order, and the result is compared as text.
  scalar "$db" "
    SELECT line FROM (
      SELECT 1 AS k, 'hotel_bookings rows=' || count(*) || ' md5=' || md5(coalesce(string_agg(t::text, '|' ORDER BY t.id), '')) AS line
      FROM hotel_bookings t
      UNION ALL
      SELECT 2, 'booking_events rows=' || count(*) || ' md5=' || md5(coalesce(string_agg(t::text, '|' ORDER BY t.id), ''))
      FROM booking_events t
      UNION ALL
      SELECT 3, 'schema_migrations=' || string_agg(version, ',' ORDER BY version)
      FROM schema_migrations
      UNION ALL
      SELECT 4, 'indexes=' || string_agg(indexname, ',' ORDER BY indexname)
      FROM pg_indexes WHERE schemaname = 'public'
    ) f ORDER BY k;"
}
