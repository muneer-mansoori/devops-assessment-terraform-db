#!/bin/sh
# Apply pending SQL migrations from /db/migrations in filename order. Runs inside the db container.
# Each migration runs in its own transaction and is recorded in schema_migrations, so re-running is safe.
#
#   usage: migrate.sh [database]
set -eu

DB="${1:-$POSTGRES_DB}"
DIR="${DB_DIR:-/db}/migrations"
PSQL="psql -v ON_ERROR_STOP=1 -X -q --username=$POSTGRES_USER --dbname=$DB"

$PSQL <<'SQL'
SET client_min_messages = warning;
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

for file in "$DIR"/*.sql; do
  version="$(basename "$file" .sql)"
  applied="$($PSQL -tA -c "SELECT 1 FROM schema_migrations WHERE version = '$version'")"
  if [ "$applied" = "1" ]; then
    echo "migrate: $version already applied"
    continue
  fi
  echo "migrate: applying $version"
  $PSQL --single-transaction \
    -f "$file" \
    -c "INSERT INTO schema_migrations (version) VALUES ('$version')"
done
