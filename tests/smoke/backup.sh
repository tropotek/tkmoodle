#!/usr/bin/env bash
# backup suite: build the base, one institution and dbtools with a test release, run a
# throwaway site from host/compose.yml, then back it up, restore it and check every refusal.
# Run it through bin/smoke.
SUITE=smoke-backup PROJECT=smokebk DEFAULT_PORT=8398
# shellcheck source=tests/smoke/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

inst="${1:-demo}"
rel=0.0.0-1
smoke_build_base moodle:smokebk "$rel"
smoke_build_institution "$inst" moodle:smokebk "moodle-$inst:smokebk"
smoke_build_dbtools moodle-dbtools:smokebk "$rel"

smoke_init
smoke_bind_hostmarker
smoke_env "INSTITUTION=$inst" "APP_IMAGE=moodle-$inst:smokebk" DBTOOLS_IMAGE=moodle-dbtools:smokebk
# The outside BACKUP_DIR check leaves a folder owned by another uid; a container clears it.
remove_outside() {
  [[ -n "${outside:-}" ]] || return 0
  docker run --rm -v "$outside:/o" mysql:8.4 sh -c "rm -rf /o/* /o/.[!.]*; chown $(id -u):$(id -g) /o" >/dev/null 2>&1 || true
  rmdir "$outside" 2>/dev/null || true
}
smoke_on_cleanup remove_outside

start_site() {
  dc up -d --wait db
  dc up -d app
  wait_up
  dc up -d cron
}

# ---- a running, seeded site -------------------------------------------------------
start_site
[[ "$(sql "SELECT value FROM mdl_config WHERE name = 'sis_release'")" == "$rel" ]] || fail "sis_release not recorded"
[[ "$(sql "SELECT value FROM mdl_config WHERE name = 'sis_institution'")" == "$inst" ]] || fail "sis_institution not recorded"
pass "site up, identity $inst $rel"

moodle_php <<'PHP'
<?php
define('CLI_SCRIPT', true);
require '/app/moodle/config.php';
require_once($CFG->dirroot . '/user/lib.php');
require_once($CFG->dirroot . '/course/lib.php');
$userid = user_create_user((object)[
    'username' => 'smoke_before', 'password' => 'Smoke-Pass-1!', 'auth' => 'manual',
    'firstname' => 'Smoke', 'lastname' => 'Before', 'email' => 'smoke@example.com',
    'confirmed' => 1, 'mnethostid' => $CFG->mnet_localhost_id,
]);
create_course((object)['fullname' => 'Smoke course', 'shortname' => 'SMOKE101',
    'category' => core_course_category::get_default()->id]);
get_file_storage()->create_file_from_string([
    'contextid' => context_user::instance($userid)->id, 'component' => 'user',
    'filearea' => 'private', 'itemid' => 0, 'filepath' => '/', 'filename' => 'smoke.txt',
], 'smoke-file-content');
echo "seeded\n";
PHP
pass "seeded a user, a course and a file"

# ---- backup with the site up, under --maintenance ---------------------------------
seen="$work/flag-seen"
(
  while [[ ! -e "$work/backup-done" ]]; do
    if dc exec -T app test -f /moodledata/climaintenance.html 2>/dev/null; then touch "$seen"; fi
    sleep 0.2
  done
) &
watcher=$!
out=$(tools sis-backup --maintenance first) || { touch "$work/backup-done"; fail "sis-backup failed: $out"; }
touch "$work/backup-done"
wait "$watcher"
echo "$out"
[[ -e "$seen" ]] || fail "maintenance flag never seen during the backup"
dc exec -T app test ! -f /moodledata/climaintenance.html || fail "maintenance flag left behind"
pass "--maintenance set the flag during the run and cleared it"

b="$work/backups/first"
for f in manifest.env db.sql.zst moodledata.tar.zst; do [[ -s "$b/$f" ]] || fail "bundle lacks $f"; done
grep -qx "sis_release=$rel" "$b/manifest.env" || fail "manifest release: $(cat "$b/manifest.env")"
grep -qx "sis_institution=$inst" "$b/manifest.env" || fail "manifest institution"
grep -q '^moodle_version=[0-9]' "$b/manifest.env" || fail "manifest moodle_version"
[[ "$(stat -c %u:%g "$b" "$b/db.sql.zst" | sort -u)" == "$(stat -c %u:%g "$work/backups")" ]] || fail "bundle not owned like the folder"
[[ -z "$(find "$work/backups" -maxdepth 1 -name '.*partial')" ]] || fail "partial folder left behind"
[[ "$out" == *"sis-restore first"* ]] || fail "restore command not printed"
[[ "$(stat -c %a "$b") $(stat -c %a "$b/db.sql.zst")" == "700 600" ]] || fail "bundle readable by others: $(stat -c '%a %n' "$b" "$b"/*)"
pass "bundle complete, owned like the folder, private to its owner"

listing=$(tools bash -c 'zstd -dcq /backups/first/moodledata.tar.zst | tar -t')
grep -q '^\./filedir/' <<<"$listing" || fail "moodledata archive has no filedir"
! grep -qE '^\./(cache|localcache|temp|sessions)/' <<<"$listing" || fail "moodledata archive has cache folders"
tools zstd -dcq /backups/first/db.sql.zst > "$work/dump.sql"
grep -qF "CREATE TABLE \`mdl_sessions\`" "$work/dump.sql" || fail "mdl_sessions structure missing"
! grep -qF "INSERT INTO \`mdl_sessions\`" "$work/dump.sql" || fail "mdl_sessions has data"
rm "$work/dump.sql"
pass "archive skips caches; sessions are structure only"

# ---- backup refusals --------------------------------------------------------------
sums=$(sha256sum "$b"/*)
refused "already exists" tools sis-backup first
[[ "$(sha256sum "$b"/*)" == "$sums" ]] || fail "existing backup changed"
pass "a second backup to an existing name is refused, the first untouched"

for bad in ../x /x .hidden; do refused "BACKUP_DIR" tools sis-backup "$bad"; done
pass "path-like names refused"

# A backup killed outright leaves its .partial folder: the refusal names it, and the
# backup folder's owner can remove it.
tools sis-backup killed >/dev/null 2>&1 &
runner=$!
deadline=$((SECONDS + 60))
until [[ -e "$work/backups/.killed.partial/db.sql.zst" ]]; do
  (( SECONDS < deadline )) || fail "the backup to kill never started its dump"
  sleep 0.1
done
container=$(docker ps -q --filter label=com.docker.compose.project=smokebk --filter label=com.docker.compose.oneoff=True)
docker kill "$container" >/dev/null
wait "$runner" || true
refused "BACKUP_DIR/.killed.partial" tools sis-backup killed
[[ -d "$work/backups/.killed.partial" ]] || fail "the interrupted backup's folder was removed"
rm -rf "$work/backups/.killed.partial" 2>/dev/null || fail "the folder's owner cannot remove an interrupted backup"
pass "an interrupted backup blocks its name, and the folder's owner can remove it"

sql "CREATE TABLE mdl_smoke_tmp (id INT); CREATE VIEW mdl_smoke_broken AS SELECT id FROM mdl_smoke_tmp; DROP TABLE mdl_smoke_tmp;"
refused "mysqldump" tools sis-backup --maintenance broken
sql "DROP VIEW mdl_smoke_broken"
[[ ! -e "$work/backups/broken" && ! -e "$work/backups/.broken.partial" ]] || fail "failed backup left files"
dc exec -T app test ! -f /moodledata/climaintenance.html || fail "failed backup left the maintenance flag"
pass "a failed backup leaves nothing behind and clears the flag"

dc exec -T app sh -c 'echo held > /moodledata/climaintenance.html'
tools sis-backup --maintenance keepflag >/dev/null
dc exec -T app test -f /moodledata/climaintenance.html || fail "an existing maintenance flag was removed"
dc exec -T app rm /moodledata/climaintenance.html
rm -rf "$work/backups/keepflag"
pass "an existing maintenance flag is left alone"

sql "DELETE FROM mdl_config WHERE name = 'sis_release'"
refused "start the site once" tools sis-backup norelease
sql "INSERT INTO mdl_config (name, value) VALUES ('sis_release', '$rel')"
pass "a site with no recorded release is refused"

# ---- restore refusals; each must leave the site as it is -------------------------
moodle_php <<'PHP'
<?php
define('CLI_SCRIPT', true);
require '/app/moodle/config.php';
require_once($CFG->dirroot . '/user/lib.php');
user_create_user((object)[
    'username' => 'smoke_after', 'password' => 'Smoke-Pass-1!', 'auth' => 'manual',
    'firstname' => 'Smoke', 'lastname' => 'After', 'email' => 'after@example.com',
    'confirmed' => 1, 'mnethostid' => $CFG->mnet_localhost_id,
]);
PHP
tools touch /moodledata/smoke-marker
unchanged() {
  [[ "$(sql "SELECT COUNT(*) FROM mdl_user WHERE username = 'smoke_after'")" == 1 ]] || fail "$1: the database changed"
  tools test -f /moodledata/smoke-marker || fail "$1: moodledata changed"
}

refused "stop the site first" tools sis-restore first
unchanged "restore while running"
dc stop app
refused "cron" tools sis-restore first
unchanged "restore while cron runs"
dc stop cron
pass "restore refused while app or cron runs"

copy_with() {  # copy_with <new name> <key> <value>
  cp -a "$b" "$work/backups/$1"
  sed -i "s/^$2=.*/$2=$3/" "$work/backups/$1/manifest.env"
}
copy_with elsewhere sis_institution elsewhere
refused "elsewhere" tools sis-restore elsewhere
unchanged "another institution"
pass "another institution's backup refused"

copy_with newer sis_release 0.0.0-2
refused "TAG=0.0.0-2" tools sis-restore newer
out=$(tools sis-restore newer 2>&1 || true)
[[ "$out" != *"pull skips it"* ]] || fail "sis-restore still says pull skips dbtools"
unchanged "newer release"
pass "a newer release's backup refused, naming the TAG"

cp -a "$b" "$work/backups/damaged"
truncate -s 1000 "$work/backups/damaged/moodledata.tar.zst"
refused "damaged" tools sis-restore damaged
unchanged "damaged archive"
refused "no backup" tools sis-restore missing
refused "BACKUP_DIR" tools sis-restore ../first
pass "damaged, missing and path-like backups refused"

# ---- a mis-marked host: backups still run, restores don't ----------------------------
marker uat
setenv SIS_ENV production
tools sis-backup mismarked >/dev/null || fail "sis-backup refused on a mis-marked host"
refused "SIS_ENV=production expects /etc/tkmoodle/production, but this host is marked /etc/tkmoodle/uat" \
  tools sis-restore first
unchanged "restore on a mis-marked host"
pass "a mis-marked host can back up but not restore"

# ---- --any-institution: only local and development may cross institutions --------
marker production
setenv SIS_ENV production
refused "only works with SIS_ENV local or development" tools sis-restore --any-institution elsewhere
unchanged "--any-institution on production"
marker devserver
setenv SIS_ENV development
out=$(tools sis-restore --any-institution elsewhere 2>&1) || fail "--any-institution on development: $out"
[[ "$out" == *"restoring elsewhere onto $inst (--any-institution)"* ]] || fail "no --any-institution log line: $out"
marker
setenv SIS_ENV local
pass "--any-institution is refused on production and restores on development"

# ---- wipe and restore ---------------------------------------------------------------
dc down -v
dc up -d --wait db
tools sis-restore first
dc up -d app
wait_up
dc up -d cron

moodle_php <<'PHP'
<?php
define('CLI_SCRIPT', true);
require '/app/moodle/config.php';
$fail = function (string $msg) { fwrite(STDERR, "$msg\n"); exit(1); };
$user = $DB->get_record('user', ['username' => 'smoke_before']) ?: $fail('smoke_before missing');
$DB->record_exists('course', ['shortname' => 'SMOKE101']) || $fail('SMOKE101 missing');
$ctx = context_user::instance($user->id);
$fs = get_file_storage();
$file = $fs->get_file($ctx->id, 'user', 'private', 0, '/', 'smoke.txt');
($file && $file->get_content() === 'smoke-file-content') || $fail('smoke.txt missing or wrong');
$DB->record_exists('user', ['username' => 'smoke_after']) && $fail('smoke_after survived the restore');
$fs->create_file_from_string(['contextid' => $ctx->id, 'component' => 'user', 'filearea' => 'private',
    'itemid' => 0, 'filepath' => '/', 'filename' => 'after-restore.txt'], 'written after restore');
echo "restored site checks out\n";
PHP
tools test ! -e /moodledata/smoke-marker || fail "moodledata not replaced"
pass "restored: same user, course and file; later changes gone; moodledata writable"

# ---- a backup folder outside the project, owned by someone else ------------------
outside="$(mktemp -d)"
docker run --rm -v "$outside:/o" mysql:8.4 sh -c 'chown 4321:4321 /o && chmod 755 /o'
echo "BACKUP_DIR=$outside" >> "$work/.env"
tools sis-backup outside >/dev/null
[[ "$(stat -c %u:%g "$outside/outside" "$outside/outside/manifest.env" | sort -u)" == 4321:4321 ]] || fail "outside backup not owned like its folder"
pass "BACKUP_DIR outside the project works, owned like the folder"

echo "smoke-backup: PASS"
