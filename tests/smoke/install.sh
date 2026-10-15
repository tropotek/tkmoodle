#!/usr/bin/env bash
# install suite: build the base (and optionally one institution on it), install a fresh site
# from host/compose.yml, check it serves, then tear down. Run it through bin/smoke.
SUITE=smoke PROJECT=smoke DEFAULT_PORT=8399
# shellcheck source=tests/smoke/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

inst="${1:-}"
image="${SMOKE_IMAGE:-}"
if [[ -z "$image" ]]; then
  smoke_build_base moodle:smoke
  image=moodle:smoke
  if [[ -n "$inst" ]]; then
    smoke_build_institution "$inst" moodle:smoke "moodle-$inst:smoke"
    image="moodle-$inst:smoke"
  fi
fi
smoke_build_dbtools moodle-dbtools:smoke

smoke_init
smoke_env "APP_IMAGE=$image" DBTOOLS_IMAGE=moodle-dbtools:smoke ${SMOKE_ENV:+"$SMOKE_ENV"}
stop_hostcheck() { docker compose -p smokehost --project-directory "$work/hostcheck" down -v >/dev/null 2>&1 || true; }
smoke_on_cleanup stop_hostcheck

# SIS_ENV is checked before anything else, in the app image and in preupgrade.
for value in "" bogus Production; do
  if out=$(docker run --rm -e SIS_ENV="$value" "$image" true 2>&1); then fail "SIS_ENV='$value' was accepted"; fi
  [[ "$out" == *"SIS_ENV must be one of local, development, uat, production (got '$value')"* ]] || fail "SIS_ENV='$value': $out"
done
docker run --rm -e SIS_ENV=local "$image" true >/dev/null || fail "SIS_ENV=local was refused"
if out=$(docker run --rm -e SIS_ENV=bogus moodle-dbtools:smoke sis-preupgrade 2>&1); then fail "preupgrade accepted SIS_ENV=bogus"; fi
[[ "$out" == *"SIS_ENV must be one of"* ]] || fail "preupgrade: $out"
echo "smoke: SIS_ENV is checked"

# Host markers: each case mounts a folder at /sis/host, as the hostmarker volume does.
hm="$work/hm"
marks() { rm -rf "$hm"; mkdir "$hm"; local m; for m in "$@"; do touch "$hm/$m"; done; }
in_host() { local env=$1; shift; docker run --rm -e SIS_ENV="$env" -v "$hm:/sis/host:ro" "$@" 2>&1; }
refused_by() {  # refused_by <text> <SIS_ENV> <docker run args…>
  local want=$1 out
  shift
  if out=$(in_host "$@"); then fail "not refused: $*"; fi
  [[ "$out" == *"$want"* ]] || fail "refusal of '$*' lacks '$want'; got: $out"
}
wrong="SIS_ENV=production expects /etc/tkmoodle/production, but this host is marked /etc/tkmoodle/uat"
marks uat
refused_by "$wrong" production "$image" true
marks
refused_by "has no environment marker" production "$image" true
marks uat production
refused_by "has more than one environment marker" production "$image" true
marks
mkdir "$hm/uat"
refused_by "/etc/tkmoodle/uat is not a regular file" uat "$image" true
marks uat
refused_by "$wrong" production -e SKIP_PREUPGRADE_BACKUP=1 moodle-dbtools:smoke sis-preupgrade
refused_by "$wrong" production moodle-dbtools:smoke sis-restore first
refused_by "SIS_ENV must be one of" bogus moodle-dbtools:smoke sis-restore first
marks production
refused_by "SIS_ENV=local, but this host is marked as a server" local "$image" true
chmod 000 "$hm"
refused_by "is not readable by the site" production "$image" true
chmod 755 "$hm"
marks devserver
in_host development "$image" true >/dev/null || fail "app refused development on a devserver host"
in_host development -e SKIP_PREUPGRADE_BACKUP=1 moodle-dbtools:smoke sis-preupgrade >/dev/null \
  || fail "preupgrade refused development on a devserver host"
rc=0
in_host development moodle-dbtools:smoke sis-restore >/dev/null || rc=$?
[[ "$rc" == 64 ]] || fail "sis-restore did not reach its usage check on a devserver host (exit $rc)"
echo "smoke: host markers are checked in both images"

# The documented switch: uncomment the hostmarker line, here pointed at a test folder. Its own
# project, so the main run's plain volume is never reused.
hw="$work/hostcheck"
mkdir -p "$hw/config" "$hw/backups"
cp "$work/.env" "$hw/"
sed -e 's|^    # driver_opts:|    driver_opts:|' -e "s|device: /etc/tkmoodle}|device: $hw/marker}|" \
  host/compose.yml > "$hw/compose.yml"
grep -qF "    driver_opts: {type: none, o: bind, device: $hw/marker}" "$hw/compose.yml" \
  || fail "the documented hostmarker edit did not apply to host/compose.yml"
hdc() { docker compose -p smokehost --project-directory "$hw" "$@"; }
mkdir "$hw/marker"
touch "$hw/marker/production"
out=$(hdc run --rm --no-deps -T -e SIS_ENV=production app true 2>&1) \
  || fail "with the hostmarker line uncommented, a production host marked production was refused: $out"
hdc down -v >/dev/null 2>&1 || true
rm -rf "$hw/marker"
if out=$(hdc run --rm --no-deps -T app true 2>&1); then fail "started with the marker folder missing"; fi
[[ "$out" == *"no such file or directory"* ]] || fail "missing marker folder: $out"
hdc down -v >/dev/null 2>&1 || true
echo "smoke: the hostmarker line binds the host folder, and a missing one stops the site"

# Unedited compose.yml: the hostmarker volume is empty, so only local starts.
if out=$(dc run --rm --no-deps -T -e SIS_ENV=production app true 2>&1); then
  fail "production started with the hostmarker line commented"
fi
[[ "$out" == *"has no environment marker"* ]] || fail "unedited compose.yml, production: $out"
echo "smoke: an unedited compose.yml refuses a server SIS_ENV"

dc up -d db app
deadline=$((SECONDS + timeout))
until curl -fsS -o /dev/null "http://localhost:$port/up"; do
  (( SECONDS < deadline )) || fail "/up not 200 after ${timeout}s"
  [[ "$(dc ps -a --format '{{.State}}' app)" != exited ]] || fail "app exited"
  sleep 5
done
echo "smoke: /up 200"

code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/login/index.php")
[[ "$code" == 200 ]] || fail "login page returned $code"
echo "smoke: login page 200"

[[ "$(dc ps -a --format '{{.ExitCode}}' preupgrade)" == 0 ]] || fail "preupgrade did not exit 0"
[[ "$(dc logs --no-log-prefix preupgrade)" == *"no recorded release: nothing to back up"* ]] || fail "preupgrade: $(dc logs preupgrade)"
echo "smoke: preupgrade passed a first install through"

dc up -d cron
sleep 15
[[ "$(dc ps -a --format '{{.State}}' cron)" == running ]] || fail "cron not running"
[[ "$(dc logs cron)" == *"sis-cron: running"* ]] || fail "cron did not start"
echo "smoke: cron running"

mysql_smoke() { dc exec -T db mysql -umoodle -psmoke -N moodle -e "$1" 2>/dev/null; }

want_inst="${inst:-base}"
release=$(mysql_smoke "select value from mdl_config where name='sis_release'")
institution=$(mysql_smoke "select value from mdl_config where name='sis_institution'")
if [[ -n "${SMOKE_IMAGE:-}" ]]; then
  [[ -n "$release" && -n "$institution" ]] || fail "identity not recorded: release='$release' institution='$institution'"
else
  [[ "$release" == dev ]] || fail "sis_release is '$release', expected dev"
  [[ "$institution" == "$want_inst" ]] || fail "sis_institution is '$institution', expected $want_inst"
fi
echo "smoke: identity $institution $release"

for role in app cron; do
  held=$(mysql_smoke "select IS_USED_LOCK(LEFT(CONCAT('sis:', DATABASE(), ':$role'), 64)) is not null")
  [[ "$held" == 1 ]] || fail "$role does not hold its running lock"
done
echo "smoke: app and cron hold their locks"

if [[ -n "$inst" ]]; then
  for component in $(jq -r '.locked.plugins // {} | keys[]' "institutions/$inst/settings.json"); do
    n=$(mysql_smoke "select count(*) from mdl_config_plugins where plugin='$component' and name='version'")
    [[ "$n" -ge 1 ]] || fail "$component is not installed"
    echo "smoke: $component installed"
  done
fi
echo "smoke: PASS"
