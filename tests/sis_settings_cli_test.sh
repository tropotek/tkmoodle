#!/usr/bin/env bash
# Behaviour tests for docker/sis-settings.php. Run: tests/sis_settings_cli_test.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0
expect() {  # expect <name> <command...>: ok when the command succeeds
  local name="$1"; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi
}

cat > "$tmp/inst.json" <<'JSON'
{"locked": {"core": {"authpreventaccountcreation": "1"},
            "plugins": {"local_sisexample": {"remoteurl": "${SISEXAMPLE_REMOTE_URL}", "mode": "inst"}}}}
JSON
echo '{"locked": {"plugins": {"local_sisexample": {"mode": "override"}}}}' > "$tmp/override.json"

run() { SIS_INSTITUTION_SETTINGS="$tmp/inst.json" SIS_OVERRIDE_SETTINGS="$tmp/override.json" php docker/sis-settings.php "$@"; }

expect "render exits 0" env SISEXAMPLE_REMOTE_URL=https://remote.test \
  SIS_INSTITUTION_SETTINGS="$tmp/inst.json" SIS_OVERRIDE_SETTINGS="$tmp/override.json" \
  php docker/sis-settings.php render "$tmp/locked.php"
expect "output is valid PHP" php -l "$tmp/locked.php"
expect "env interpolated" grep -q "\['local_sisexample'\]\['remoteurl'\] = 'https://remote.test'" "$tmp/locked.php"
expect "override wins" grep -q "\['mode'\] = 'override'" "$tmp/locked.php"

run render "$tmp/locked2.php" >/dev/null
expect "unset var skips key" bash -c "! grep -q remoteurl '$tmp/locked2.php'"

run nonsense 2>/dev/null
rc=$?
expect "unknown command exits 64 (rc=$rc)" test "$rc" -eq 64

echo '{bad' > "$tmp/override.json"
run render "$tmp/locked3.php" 2>"$tmp/err"
rc=$?
expect "invalid override exits 1 (rc=$rc)" test "$rc" -eq 1
expect "invalid override names the problem" grep -q "invalid JSON" "$tmp/err"
expect "no output on error" test ! -e "$tmp/locked3.php"

run nonsense 2>/dev/null
rc=$?
expect "unknown command exits 64 before reading settings (rc=$rc)" test "$rc" -eq 64
exit $fail
