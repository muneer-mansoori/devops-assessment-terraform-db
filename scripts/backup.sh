#!/usr/bin/env bash
# Create a timestamped, verified logical backup of the local database.
#
#   ./scripts/backup.sh                    # backs up $POSTGRES_DB (default hotel_db)
#   BACKUP_KEEP=14 ./scripts/backup.sh     # keep the 14 newest backups (default 7)
#
# Produces, in backups/:
#   hotel_db_20261110T101500Z.dump           pg_dump custom format (compressed, restorable with pg_restore)
#   hotel_db_20261110T101500Z.dump.sha256    checksum, checked by restore.sh before restoring
#   hotel_db_20261110T101500Z.manifest       data fingerprint at backup time, compared after restore
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BACKUP_KEEP="${BACKUP_KEEP:-7}"
[[ "$BACKUP_KEEP" =~ ^[1-9][0-9]*$ ]] || die "BACKUP_KEEP must be a positive integer"

require_db_running
mkdir -p "$BACKUP_DIR"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BASE="$BACKUP_DIR/${POSTGRES_DB}_${TS}"
DUMP="$BASE.dump"
TMP="$DUMP.partial"
[[ ! -e "$DUMP" ]] || die "${DUMP#"$ROOT"/} already exists (two backups in the same second?)"

# Never leave a half-written file that looks like a valid backup.
trap 'rm -f "$TMP"' EXIT

log "backing up database '$POSTGRES_DB' -> ${DUMP#"$ROOT"/}"
# Custom format: compressed, supports selective and parallel restore. --no-owner/--no-privileges make the
# dump restorable into any database regardless of role names. pg_dump reads from one consistent snapshot.
"${COMPOSE[@]}" exec -T "$DB_SERVICE" pg_dump \
  --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" \
  --format=custom --compress=6 --no-owner --no-privileges \
  >"$TMP"

[[ -s "$TMP" ]] || die "pg_dump produced an empty file"

# Prove the archive is readable before calling it a backup.
"${COMPOSE[@]}" exec -T "$DB_SERVICE" pg_restore --list <"$TMP" >/dev/null \
  || die "pg_restore cannot read the dump; backup is corrupt"

mv "$TMP" "$DUMP"
sha256_file "$DUMP" >"$DUMP.sha256"
fingerprint "$POSTGRES_DB" >"$BASE.manifest"

SIZE="$(du -h "$DUMP" | awk '{print $1}')"
log "backup OK: ${DUMP#"$ROOT"/} ($SIZE, sha256 $(cut -c1-12 "$DUMP.sha256")...)"
sed 's/^/           /' "$BASE.manifest" >&2

# Retention: keep the newest $BACKUP_KEEP dumps (and their sidecar files).
# Filenames embed a sortable UTC timestamp, so a reverse name sort is newest-first.
OLD="$(ls -1 "$BACKUP_DIR"/"${POSTGRES_DB}"_*.dump 2>/dev/null | sort -r | tail -n +"$((BACKUP_KEEP + 1))" || true)"
if [[ -n "$OLD" ]]; then
  while IFS= read -r f; do
    rm -f "$f" "$f.sha256" "${f%.dump}.manifest"
    log "retention: removed ${f#"$ROOT"/}"
  done <<<"$OLD"
fi

# Machine-readable result on stdout (logs go to stderr).
echo "$DUMP"
