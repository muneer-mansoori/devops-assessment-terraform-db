#!/bin/sh
# Load deterministic seed data, then refresh planner statistics and the visibility map
# (VACUUM is what lets the covering index answer the report query as an Index Only Scan).
#
#   usage: seed.sh [database]
set -eu

DB="${1:-$POSTGRES_DB}"
BOOKINGS="${SEED_BOOKINGS:-50000}"

echo "seed: loading $BOOKINGS hotel bookings into $DB"
psql -v ON_ERROR_STOP=1 -X -q --username="$POSTGRES_USER" --dbname="$DB" \
  -v booking_count="$BOOKINGS" \
  --single-transaction -f "${DB_DIR:-/db}/seed/seed.sql"

psql -v ON_ERROR_STOP=1 -X -q --username="$POSTGRES_USER" --dbname="$DB" \
  -c "VACUUM (ANALYZE) hotel_bookings" \
  -c "VACUUM (ANALYZE) booking_events"

psql -X -tA --username="$POSTGRES_USER" --dbname="$DB" -c "
  SELECT 'seed: ' || (SELECT count(*) FROM hotel_bookings) || ' bookings, '
              || (SELECT count(*) FROM booking_events) || ' events, '
              || (SELECT count(DISTINCT city) FROM hotel_bookings) || ' cities, '
              || (SELECT count(DISTINCT org_id) FROM hotel_bookings) || ' orgs, '
              || (SELECT count(DISTINCT status) FROM hotel_bookings) || ' statuses'"
