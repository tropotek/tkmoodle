# Shared helpers for sis-backup and sis-restore. Sourced, never run.
# shellcheck shell=bash

# Kept as structure only: they hold nothing a restored site needs.
SIS_STRUCTURE_ONLY=(mdl_sessions mdl_cache_flags mdl_config_log)

log() { printf 'sis: %s\n' "$*"; }
die() { printf 'sis: %s\n' "$*" >&2; exit 1; }

sis_name_ok() { [[ "$1" =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]]; }

sis_check_name() {
  sis_name_ok "$1" || die "backups take a plain name (letters, digits, . _ -, not starting with .); they live in BACKUP_DIR (default ./backups)"
}

# 0: the target release can run the backup; 1: the backup is newer; 2: a dev backup
# can't be ordered against a release.
sis_release_allowed() {
  local backup=$1 target=$2
  [[ "$target" == dev ]] && return 0
  [[ "$backup" == dev ]] && return 2
  [[ "$backup" == "$target" ]] && return 0
  [[ "$(printf '%s\n%s\n' "$backup" "$target" | sort -V | tail -n1)" == "$target" ]] || return 1
}

# Reads key=value without sourcing: a manifest is data from the backup folder.
sis_manifest_get() {
  local line
  while IFS= read -r line; do
    if [[ "$line" == "$2="* ]]; then printf '%s\n' "${line#"$2="}"; return 0; fi
  done < "$1"
  return 0
}

sis_mycnf_quote() {
  local v=${1//\\/\\\\}
  printf '"%s"\n' "${v//\"/\\\"}"
}

# Credentials go in a defaults file so the password never shows in ps.
sis_db_init() {
  : "${DB_PASS:?DB_PASS is not set in .env}"
  DB_HOST=${DB_HOST:-db} DB_PORT=${DB_PORT:-3306} DB_NAME=${DB_NAME:-moodle} DB_USER=${DB_USER:-moodle}
  SIS_MYCNF=$(mktemp)
  {
    echo '[client]'
    echo "host=$(sis_mycnf_quote "$DB_HOST")"
    echo "port=$DB_PORT"
    echo "user=$(sis_mycnf_quote "$DB_USER")"
    echo "password=$(sis_mycnf_quote "$DB_PASS")"
    echo 'default-character-set=utf8mb4'
  } > "$SIS_MYCNF"
}

sis_sql() { mysql --defaults-extra-file="$SIS_MYCNF" --batch --skip-column-names "$@" "$DB_NAME"; }

sis_config() { sis_sql -e "SELECT value FROM mdl_config WHERE name = '$1'"; }

sis_lock() { printf "LEFT(CONCAT('sis:', DATABASE(), ':%s'), 64)" "$1"; }

sis_dump() {
  local opts=(--defaults-extra-file="$SIS_MYCNF" --single-transaction --no-tablespaces
              --set-gtid-purged=OFF --max-allowed-packet=256M)
  local ignore=() t
  for t in "${SIS_STRUCTURE_ONLY[@]}"; do ignore+=(--ignore-table="$DB_NAME.$t"); done
  mysqldump "${opts[@]}" "${ignore[@]}" "$DB_NAME"
  mysqldump "${opts[@]}" --no-data "$DB_NAME" "${SIS_STRUCTURE_ONLY[@]}"
}

# Exit 1 from GNU tar means files changed while being read, which a live site does;
# anything above that is a real failure.
sis_tar_moodledata() {
  local rc=0
  tar -C "${SIS_MOODLEDATA:-/moodledata}" --numeric-owner --anchored \
    --exclude=./cache --exclude=./localcache --exclude=./temp --exclude=./sessions \
    --exclude=./climaintenance.html \
    --warning=no-file-changed --warning=no-file-removed --ignore-failed-read \
    -cf - . || rc=$?
  ((rc <= 1)) || return "$rc"
}
