#!/usr/bin/env bash
# Tests for the dbtools helpers (dbtools/sis-dbtools-lib.sh). Run: bash tests/dbtools_test.sh
set -uo pipefail
# shellcheck source=dbtools/sis-dbtools-lib.sh
. "$(dirname "$0")/../dbtools/sis-dbtools-lib.sh"

failures=0
check() {
  local name=$1; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}
not() { ! "$@"; }
eq() { [[ "$1" == "$2" ]] || { echo "     got '$1', want '$2'"; return 1; }; }
status() { "$@" >/dev/null 2>&1; echo $?; }

check "name: plain" sis_name_ok first
check "name: timestamp" sis_name_ok 20261015-093000
check "name: release with dots" sis_name_ok pre-5.3.0-4
check "name: refuses .." not sis_name_ok ..
check "name: refuses ../x" not sis_name_ok ../x
check "name: refuses /x" not sis_name_ok /x
check "name: refuses a/b" not sis_name_ok a/b
check "name: refuses hidden" not sis_name_ok .hidden
check "name: refuses empty" not sis_name_ok ""
check "name: refuses spaces" not sis_name_ok "a b"
check "name: die names BACKUP_DIR" eq "$( (sis_check_name ../x) 2>&1)" \
  "sis: backups take a plain name (letters, digits, . _ -, not starting with .); they live in BACKUP_DIR (default ./backups)"

check "release: same" eq "$(status sis_release_allowed 5.3.0-2 5.3.0-2)" 0
check "release: older backup" eq "$(status sis_release_allowed 5.3.0-1 5.3.0-2)" 0
check "release: newer backup" eq "$(status sis_release_allowed 5.3.0-3 5.3.0-2)" 1
check "release: -10 is newer than -9" eq "$(status sis_release_allowed 5.3.0-10 5.3.0-9)" 1
check "release: -9 is older than -10" eq "$(status sis_release_allowed 5.3.0-9 5.3.0-10)" 0
check "release: newer moodle" eq "$(status sis_release_allowed 5.3.1-1 5.3.0-7)" 1
check "release: onto dev" eq "$(status sis_release_allowed 5.3.0-3 dev)" 0
check "release: dev onto dev" eq "$(status sis_release_allowed dev dev)" 0
check "release: dev onto release" eq "$(status sis_release_allowed dev 5.3.0-3)" 2

manifest=$(mktemp)
printf 'name=first\nsis_release=5.3.0-2\nsis_release_x=no\nmoodle_release=5.3 (Build: 20261005)\n' > "$manifest"
check "manifest: value" eq "$(sis_manifest_get "$manifest" sis_release)" 5.3.0-2
check "manifest: spaces kept" eq "$(sis_manifest_get "$manifest" moodle_release)" "5.3 (Build: 20261005)"
check "manifest: missing key" eq "$(sis_manifest_get "$manifest" sis_institution)" ""
rm -f "$manifest"

check "mycnf: plain" eq "$(sis_mycnf_quote secret)" '"secret"'
# shellcheck disable=SC2016 # a literal $ is the point
check "mycnf: quote, backslash, dollar, space" eq "$(sis_mycnf_quote 'a"b\c $d e')" '"a\"b\\c $d e"'

md=$(mktemp -d)
mkdir -p "$md"/{cache,localcache,temp,sessions,filedir/ab/cache,lang}
touch "$md"/cache/x "$md"/localcache/x "$md"/temp/x "$md"/sessions/x "$md"/climaintenance.html \
  "$md"/filedir/ab/cache/keep "$md"/filedir/ab/file "$md"/lang/en.txt
listing=$(SIS_MOODLEDATA="$md" sis_tar_moodledata | tar -t | sort)
has() { grep -qx -- "$1" <<<"$listing"; }
check "tar: keeps filedir" has ./filedir/ab/file
check "tar: keeps nested cache" has ./filedir/ab/cache/keep
check "tar: keeps lang" has ./lang/en.txt
check "tar: keeps the root entry" has ./
check "tar: skips cache" not has ./cache/x
check "tar: skips localcache" not has ./localcache/x
check "tar: skips temp" not has ./temp/x
check "tar: skips sessions" not has ./sessions/x
check "tar: skips the maintenance flag" not has ./climaintenance.html
rm -rf "$md"

# sis-preupgrade against a fake mysql: STUB_FAIL_ON makes the query containing it fail.
stub=$(mktemp -d)
cat > "$stub/mysql" <<'STUB'
#!/usr/bin/env bash
q=""
while (($#)); do if [[ "$1" == -e ]]; then q=$2; shift; fi; shift; done
if [[ -n "${STUB_FAIL_ON:-}" && "$q" == *"$STUB_FAIL_ON"* ]]; then echo "ERROR 1142: denied" >&2; exit 1; fi
if [[ "$q" == "SHOW TABLES"* ]]; then echo mdl_config; fi
exit 0
STUB
chmod +x "$stub/mysql"
preupgrade() {
  SIS_ENV=${SIS_ENV:-local} STUB_FAIL_ON=$1 SIS_RELEASE=0.0.0-2 DB_PASS=x PATH="$stub:$PATH" TMPDIR="$stub" \
    bash "$(dirname "$0")/../dbtools/sis-preupgrade" 2>&1
}
contains() { [[ "$1" == *"$2"* ]] || { echo "     got: $1"; return 1; }; }
check "preupgrade: unreadable tables fail loudly" \
  contains "$(preupgrade 'SHOW TABLES')" "pre-upgrade backup FAILED: cannot read database"
check "preupgrade: unreadable release fails loudly" \
  contains "$(preupgrade "name = 'sis_release'")" "pre-upgrade backup FAILED: cannot read sis_release"
# Every query fails here, so any database access before the check would print FAILED.
refusal=$(SIS_ENV=bogus preupgrade 'S')
lacks() { [[ "$1" != *"$2"* ]] || { echo "     got: $1"; return 1; }; }
check "preupgrade: refuses a bad SIS_ENV" contains "$refusal" "SIS_ENV must be one of"
check "preupgrade: refuses it before touching the database" lacks "$refusal" "FAILED"
rm -rf "$stub"

# sis-host-check against a folder standing in for /sis/host.
hc="$(dirname "$0")/../dbtools/sis-host-check"
hm=$(mktemp -d)
marks() { rm -rf "$hm"; mkdir "$hm"; local m; for m in "$@"; do touch "$hm/$m"; done; }
hostcheck() { SIS_ENV=$1 sh "$hc" "${2:-$hm}" 2>&1; }
hcstatus() { SIS_ENV=$1 sh "$hc" "${2:-$hm}" >/dev/null 2>&1; echo $?; }

marks
check "host: local, no marker" eq "$(hcstatus local)" 0
check "host: local, no folder" eq "$(hcstatus local "$hm/none")" 0
marks devserver
check "host: development on devserver" eq "$(hcstatus development)" 0
marks uat
check "host: uat on uat" eq "$(hcstatus uat)" 0
marks production README
check "host: production on production, other files ignored" eq "$(hcstatus production)" 0
marks README
check "host: local ignores other files" eq "$(hcstatus local)" 0

marks
out=$(hostcheck production)
check "host: production, no marker" contains "$out" "SIS_ENV=production, but this host has no environment marker"
check "host: says which marker to make" contains "$out" "sudo touch /etc/tkmoodle/production"
check "host: says to uncomment the line" contains "$out" "uncomment the hostmarker driver_opts line"
check "host: says to drop a volume left from before" contains "$out" "docker volume rm <project>_hostmarker"
check "host: never names the container path" lacks "$out" "$hm"
check "host: refusal exits 1" eq "$(hcstatus production)" 1
check "host: development wants devserver" contains "$(hostcheck development)" "sudo touch /etc/tkmoodle/devserver"
check "host: production, no folder" contains "$(hostcheck production "$hm/none")" "has no environment marker"
marks development
check "host: a file named development isn't a marker" contains "$(hostcheck development)" "has no environment marker"

marks uat
check "host: production on a uat host" contains "$(hostcheck production)" \
  "SIS_ENV=production expects /etc/tkmoodle/production, but this host is marked /etc/tkmoodle/uat"
check "host: wrong marker exits 1" eq "$(hcstatus production)" 1
marks uat production
check "host: two markers" contains "$(hostcheck uat)" "/etc/tkmoodle has more than one environment marker (uat production)"
marks
mkdir "$hm/uat"
check "host: a folder isn't a marker" contains "$(hostcheck uat)" "/etc/tkmoodle/uat is not a regular file"
marks production
check "host: local on a server" contains "$(hostcheck local)" \
  "SIS_ENV=local, but this host is marked as a server by /etc/tkmoodle/production"
check "host: refuses an unknown SIS_ENV" contains "$(hostcheck bogus)" "SIS_ENV must be one of"

# Root reads any folder, so the unreadable case only shows for an ordinary user.
if ((EUID != 0)); then
  marks production
  chmod 000 "$hm"
  check "host: unreadable folder" contains "$(hostcheck production)" "/etc/tkmoodle is not readable by the site"
  chmod 755 "$hm"
fi
rm -rf "$hm"

echo
if ((failures)); then echo "$failures failed"; exit 1; fi
echo "all passed"
