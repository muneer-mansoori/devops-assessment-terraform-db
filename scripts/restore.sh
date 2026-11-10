#!/usr/bin/env bash
# Restore a backup into a FRESH local database and verify it matches the backup's manifest.
#
#   ./scripts/restore.sh                                  # newest backup -> hotel_db_restore
#   ./scripts/restore.sh backups/hotel_db_<ts>.dump       # a specific backup
#   RESTORE_DB=hotel_db_copy ./scripts/restore.sh         # choose the target database name
#
# Safety: the target is dropped and recreated so the restore always starts from an empty database,
# and the script refuses to use the source database ($POSTGRES_DB) as the target.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

RESTORE_DB="${RESTORE_DB:-${POSTGRES_DB}_restore}"
[[ "$RESTORE_DB" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || die "RESTORE_DB must be a lower-case identifier"
[[ "$RESTORE_DB" != "$POSTGRES_DB" ]] || die "refusing to restore over the source database '$POSTGRES_DB'"
[[ "$RESTORE_DB" != "postgres" && "$RESTORE_DB" != template* ]] || die "refusing to use system database '$RESTORE_DB'"

DUMP="${1:-}"
if [[ -z "$DUMP" ]]; then
  DUMP="$(ls -1 "$BACKUP_DIR"/"${POSTGRES_DB}"_*.dump 2>/dev/null | sort -r | head -n 1 || true)"
  [[ -n "$DUMP" ]] || die "no backups found in ${BACKUP_DIR#"$ROOT"/}/ - run ./scripts/backup.sh first"
fi
[[ -f "$DUMP" ]] || die "backup file not found: $DUMP"
MANIFEST="${DUMP%.dump}.manifest"

require_db_running

# 1. Integrity: the file must match the checksum written at backup time.
if [[ -f "$DUMP.sha256" ]]; then
  [[ "$(sha256_file "$DUMP")" == "$(cat "$DUMP.sha256")" ]] || die "checksum mismatch: ${DUMP#"$ROOT"/} is corrupt or was modified"
  log "checksum OK"
else
  log "WARNING: no .sha256 next to the dump, skipping integrity check"
fi

# 2. Fresh target database.
log "recreating empty database '$RESTORE_DB'"
psql_in postgres -q -c "SET client_min_messages = warning" -c "DROP DATABASE IF EXISTS \"$RESTORE_DB\" WITH (FORCE)"
psql_in postgres -q -c "CREATE DATABASE \"$RESTORE_DB\" TEMPLATE template0 ENCODING 'UTF8'"

# 3. Restore. --single-transaction + --exit-on-error: either everything restores or nothing does.
log "restoring ${DUMP#"$ROOT"/} -> '$RESTORE_DB'"
"${COMPOSE[@]}" exec -T "$DB_SERVICE" pg_restore \
  --username="$POSTGRES_USER" --dbname="$RESTORE_DB" \
  --no-owner --no-privileges --exit-on-error --single-transaction \
  <"$DUMP"

# Statistics are not part of a dump; refresh them so the restored DB plans queries like the source.
psql_in "$RESTORE_DB" -q -c "VACUUM (ANALYZE)"

# 4. Verification: the restored data must match the fingerprint taken when the backup was made.
log "verifying restored database"
ACTUAL="$(fingerprint "$RESTORE_DB")"
printf '%s\n' "$ACTUAL" | sed 's/^/           /' >&2

if [[ -f "$MANIFEST" ]]; then
  if [[ "$ACTUAL" == "$(cat "$MANIFEST")" ]]; then
    log "RESTORE VERIFIED: row counts, content checksums, migrations and indexes match the backup manifest"
  else
    log "expected (from ${MANIFEST#"$ROOT"/}):"
    sed 's/^/           /' "$MANIFEST" >&2
    die "restored database does NOT match the backup manifest"
  fi
else
  log "WARNING: no manifest for this backup; showing restored fingerprint only"
fi

echo "$RESTORE_DB"
