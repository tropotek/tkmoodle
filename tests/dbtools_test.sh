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

echo
if ((failures)); then echo "$failures failed"; exit 1; fi
echo "all passed"
