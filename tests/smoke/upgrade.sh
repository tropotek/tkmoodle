#!/usr/bin/env bash
# upgrade suite: build the base image and dbtools at test releases 0.0.0-1 to 0.0.0-4, then walk
# one throwaway site from host/compose.yml through install, restart, upgrades, a failed backup,
# the escape hatch, the app's own check and a TAG rolled back. Run it through bin/smoke.
SUITE=smoke-upgrade PROJECT=smokeup DEFAULT_PORT=8397
# shellcheck source=tests/smoke/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAIL_LOGS="preupgrade app"

# Only the release ENV layer differs between these, so the rebuilds are cached.
for n in 1 2 3 4; do
  smoke_build_base "moodle:smokeup-$n" "0.0.0-$n"
  smoke_build_dbtools "moodle-dbtools:smokeup-$n" "0.0.0-$n"
done

smoke_init
smoke_env INSTITUTION=base

db_release() { sql "SELECT value FROM mdl_config WHERE name = 'sis_release'"; }

# release <app n> [<dbtools n>]: point the site at the images of those test releases.
release() {
  sed -i '/^APP_IMAGE=/d; /^DBTOOLS_IMAGE=/d' "$work/.env"
  printf 'APP_IMAGE=moodle:smokeup-%s\nDBTOOLS_IMAGE=moodle-dbtools:smokeup-%s\n' "$1" "${2:-$1}" >> "$work/.env"
}
since() { date -u +%Y-%m-%dT%H:%M:%SZ; }
pre_log_since() { dc logs --no-log-prefix --since "$1" preupgrade 2>&1; }
app_log_since() { dc logs --no-log-prefix --since "$1" app 2>&1; }
container() { dc ps -a -q "$1"; }
up_site() { dc up -d app && wait_up && dc up -d cron; }
backups() { find "$work/backups" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | tr '\n' ' '; }

# ---- 1. first install ---------------------------------------------------------------
release 1
t=$(since)
up_site || fail "first install did not start"
[[ "$(pre_log_since "$t")" == *"no recorded release: nothing to back up"* ]] || fail "first install: $(pre_log_since "$t")"
[[ -z "$(backups)" ]] || fail "first install took a backup: $(backups)"
[[ "$(db_release)" == 0.0.0-1 ]] || fail "release after install: $(db_release)"
pass "first install: no backup"

# ---- 2. restart on the same release -------------------------------------------------
before=$(docker inspect -f '{{.State.FinishedAt}}' "$(container preupgrade)")
t=$(since)
dc up -d --force-recreate app
wait_up
pre=$(container preupgrade)
[[ "$(docker inspect -f '{{.State.FinishedAt}}' "$pre")" != "$before" ]] || fail "preupgrade did not run on restart"
[[ "$(pre_log_since "$t")" == *"release 0.0.0-1 unchanged: no backup needed"* ]] || fail "restart: $(pre_log_since "$t")"
[[ -z "$(backups)" ]] || fail "restart took a backup"
secs=$(( $(date -d "$(docker inspect -f '{{.State.FinishedAt}}' "$pre")" +%s) - $(date -d "$(docker inspect -f '{{.State.StartedAt}}' "$pre")" +%s) ))
(( secs < 10 )) || fail "preupgrade took ${secs}s on a restart"
pass "restart: preupgrade ran in ${secs}s, no backup"

# ---- 3. upgrade, then restore its backup and start the same release again -----------
release 2
t=$(since)
up_site || fail "upgrade to -2 did not start"
grep -qx 'sis_release=0.0.0-1' "$work/backups/pre-0.0.0-2/manifest.env" || fail "pre-0.0.0-2 missing or wrong"
[[ "$(sql "SELECT value FROM mdl_config WHERE name = 'sis_preupgrade_backup'")" == 0.0.0-2 ]] || fail "marker not stored"
[[ "$(db_release)" == 0.0.0-2 ]] || fail "release after upgrade: $(db_release)"
pass "upgrade to -2 took pre-0.0.0-2 first"

dc stop app cron
tools sis-restore pre-0.0.0-2 >/dev/null
[[ "$(db_release)" == 0.0.0-1 ]] || fail "restore did not bring back -1"
t=$(since)
up_site || fail "start after restore failed"
[[ "$(pre_log_since "$t")" == *"already holds this database's release 0.0.0-1"* ]] || fail "after restore: $(pre_log_since "$t")"
[[ "$(backups)" == "pre-0.0.0-2 " ]] || fail "a second backup was taken: $(backups)"
[[ "$(db_release)" == 0.0.0-2 ]] || fail "release after restore and restart: $(db_release)"
pass "restoring pre-0.0.0-2 and starting -2 again upgrades without a second backup"

# ---- 4. a failed backup stops the upgrade -------------------------------------------
release 3
mkdir "$work/backups/.pre-0.0.0-3.partial"
t=$(since)
if dc up -d app >/dev/null 2>&1; then fail "app started although the backup failed"; fi
[[ "$(pre_log_since "$t")" == *"pre-upgrade backup FAILED"* ]] || fail "failed backup: $(pre_log_since "$t")"
app=$(container app)
[[ -z "$app" || "$(docker inspect -f '{{.State.Status}}' "$app")" == created ]] || fail "the new app container ran"
[[ ! -e "$work/backups/pre-0.0.0-3" ]] || fail "a pre-0.0.0-3 backup exists"
[[ "$(db_release)" == 0.0.0-2 ]] || fail "release changed: $(db_release)"
pass "a failed backup stops the upgrade, and the log says why"

# ---- 5. the escape hatch ------------------------------------------------------------
echo "SKIP_PREUPGRADE_BACKUP=1" >> "$work/.env"
t=$(since)
up_site || fail "upgrade with SKIP_PREUPGRADE_BACKUP did not start"
[[ "$(pre_log_since "$t")" == *SKIPPING* ]] || fail "preupgrade did not log the skip"
[[ "$(db_release)" == 0.0.0-3 ]] || fail "release after skipped backup: $(db_release)"
sed -i '/^SKIP_PREUPGRADE_BACKUP=/d' "$work/.env"
rmdir "$work/backups/.pre-0.0.0-3.partial"
pass "SKIP_PREUPGRADE_BACKUP=1 lets the upgrade through, logged"

# ---- 5b. the app logged the skip too --------------------------------------------------
[[ "$(app_log_since "$t")" == *SKIPPING* ]] || fail "app did not log the skip"
pass "the app logs the skipped check too"

# ---- 6. app newer than dbtools: the app's own check refuses -------------------------
release 4 3
t=$(since)
dc up -d app >/dev/null 2>&1 || fail "preupgrade should pass when dbtools matches the database"
[[ "$(pre_log_since "$t")" == *"release 0.0.0-3 unchanged"* ]] || fail "preupgrade: $(pre_log_since "$t")"
deadline=$((SECONDS + 120))
until [[ "$(app_log_since "$t")" == *"UPGRADE REFUSED"* ]]; do
  (( SECONDS < deadline )) || fail "app did not refuse: $(app_log_since "$t" | tail -n 5)"
  sleep 3
done
[[ "$(app_log_since "$t")" == *"no pre-upgrade backup for release 0.0.0-4"* ]] || fail "refusal lacks its reason"
[[ "$(db_release)" == 0.0.0-3 ]] || fail "release changed: $(db_release)"
dc stop app >/dev/null
pass "an app newer than dbtools refuses to upgrade, and says why"

# The dev stack has no preupgrade: a dev image must not refuse a release database.
dc run --rm --no-deps -T -e SIS_RELEASE=dev app sis-db.php upgrade-allowed || fail "dev image refused a release database"
refused_rc=0
dc run --rm --no-deps -T app sis-db.php upgrade-allowed >/dev/null 2>&1 || refused_rc=$?
[[ "$refused_rc" == 1 ]] || fail "upgrade-allowed exit $refused_rc, expected 1"
pass "a dev image passes the check; a release image without a backup gets exit 1"

# ---- 7. a pre-<r> folder holding another release blocks the upgrade; removing it recovers
cp -a "$work/backups/pre-0.0.0-2" "$work/backups/pre-0.0.0-4"
release 4
t=$(since)
if dc up -d app >/dev/null 2>&1; then fail "app started although pre-0.0.0-4 holds another release"; fi
[[ "$(pre_log_since "$t")" == *"already exists"* ]] || fail "existing name: $(pre_log_since "$t")"
[[ "$(db_release)" == 0.0.0-3 ]] || fail "release changed: $(db_release)"
rm -rf "$work/backups/pre-0.0.0-4"
up_site || fail "upgrade to -4 did not start"
grep -qx 'sis_release=0.0.0-3' "$work/backups/pre-0.0.0-4/manifest.env" || fail "pre-0.0.0-4 missing or wrong"
[[ "$(db_release)" == 0.0.0-4 ]] || fail "release after upgrade: $(db_release)"
pass "a stale pre-0.0.0-4 blocks the upgrade; removing it upgrades to -4"

# ---- 8. rolling TAG back without a restore ------------------------------------------
had=$(backups)
release 3
t=$(since)
if dc up -d app >/dev/null 2>&1; then fail "app started on an older release"; fi
[[ "$(pre_log_since "$t")" == *"Moodle cannot downgrade"* ]] || fail "rollback: $(pre_log_since "$t")"
[[ "$(backups)" == "$had" ]] || fail "rollback wrote a backup: $(backups)"
[[ "$(db_release)" == 0.0.0-4 ]] || fail "release changed: $(db_release)"
pass "setting TAG back without a restore is refused: Moodle cannot downgrade"

echo "smoke-upgrade: PASS"
