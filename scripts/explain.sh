#!/usr/bin/env bash
# Show the report query's execution plan WITHOUT and WITH the index, on the same data.
#
#   ./scripts/explain.sh
#
# "Without" drops the index inside a transaction that is rolled back, so nothing is changed permanently.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DB="${1:-$POSTGRES_DB}"
require_db_running

QUERY="SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status"

echo "=== Query result (first rows) ==="
psql_in "$DB" -c "$QUERY ORDER BY org_id, status LIMIT 12;"

echo "=== BEFORE: without idx_hotel_bookings_city_created_at (dropped in a rolled-back transaction) ==="
psql_in "$DB" <<SQL
BEGIN;
DROP INDEX idx_hotel_bookings_city_created_at;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON) $QUERY;
ROLLBACK;
SQL

echo "=== AFTER: with the covering index ==="
psql_in "$DB" -c "EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON) $QUERY;"
