#!/bin/sh
# Executed by the postgres image on first start (empty data volume) via /docker-entrypoint-initdb.d.
# Applies every migration in order, then the seed data. Any SQL error aborts container init.
set -eu

"${DB_DIR:-/db}/migrate.sh" "$POSTGRES_DB"
"${DB_DIR:-/db}/seed.sh" "$POSTGRES_DB"
