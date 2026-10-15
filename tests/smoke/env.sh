#!/usr/bin/env bash
# env suite: run the base image from host/compose.yml with Mailpit and Redis beside it, then
# check that local mails and reaches any port, development never mails, production blocks
# private hosts, SMTP_* locks the SMTP settings, and REDIS_HOST moves sessions into Redis.
# Run it through bin/smoke.
SUITE=smoke-env PROJECT=smokeenv DEFAULT_PORT=8393
# shellcheck source=tests/smoke/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

smoke_build_base moodle:smokeenv
smoke_build_dbtools moodle-dbtools:smokeenv

smoke_init
mailport=$((port + 2))
cat > "$work/compose.test.yml" <<YML
services:
  mailpit:
    image: axllent/mailpit:v1.21.8
    ports: ["$mailport:8025"]
  redis:
    image: redis:7.4.1-alpine
YML
smoke_compose "$work/compose.test.yml"
smoke_env INSTITUTION=base APP_IMAGE=moodle:smokeenv DBTOOLS_IMAGE=moodle-dbtools:smokeenv \
  SMTP_HOSTS=mailpit:1025 \
  "# Moodle's default no-reply address, noreply@localhost here, is not a valid address." \
  SMTP_NOREPLY=noreply@example.com REDIS_HOST=redis
smoke_bind_hostmarker

mail_count() { curl -fsS "http://localhost:$mailport/api/v1/messages" | jq -r .total; }
send_mail() {
  moodle_php <<'PHP'
<?php
define('CLI_SCRIPT', true);
require '/app/moodle/config.php';
$admin = get_admin();
email_to_user($admin, $admin, 'smoke-env', 'smoke-env body');
PHP
}
curl_mailpit() {
  moodle_php <<'PHP'
<?php
define('CLI_SCRIPT', true);
require '/app/moodle/config.php';
require_once($CFG->libdir . '/filelib.php');
$c = new curl();
$c->get('http://mailpit:8025/api/v1/info');
echo (($c->get_info()['http_code'] ?? 0) == 200) ? "reached\n" : "blocked\n";
PHP
}
smtp_forced() {
  moodle_php <<'PHP'
<?php
define('CLI_SCRIPT', true);
require '/app/moodle/config.php';
echo array_key_exists('smtphosts', $CFG->config_php_settings) ? "forced\n" : "free\n";
PHP
}

dc up -d mailpit redis app
wait_up

# ---- local --------------------------------------------------------------------------
send_mail
[[ "$(mail_count)" == 1 ]] || fail "local: the email did not reach Mailpit ($(mail_count))"
[[ "$(curl_mailpit)" == reached ]] || fail "local: curl could not reach mailpit:8025"
pass "local: mail reaches Mailpit, curl reaches any host and port"

# ---- development ----------------------------------------------------------------------
marker devserver
setenv_up SIS_ENV development
send_mail
[[ "$(mail_count)" == 1 ]] || fail "development sent mail ($(mail_count))"
pass "development: no mail sent"

# ---- production -------------------------------------------------------------------------
marker production
setenv_up SIS_ENV production
[[ "$(curl_mailpit)" == blocked ]] || fail "production: curl reached a private host and port"
[[ "$(smtp_forced)" == forced ]] || fail "production: SMTP_HOSTS set but smtphosts not forced"
pass "production: curl blocks private hosts; SMTP from .env is read-only"

# ---- Redis sessions ------------------------------------------------------------------
jar="$work/cookies"
token=$(curl -fsS -c "$jar" "http://localhost:$port/login/index.php" \
  | grep -o 'name="logintoken" value="[^"]*"' | sed 's/.*value="//; s/"$//') || true
[[ -n "$token" ]] || fail "no logintoken on the login page"
curl -fsS -b "$jar" -c "$jar" -o /dev/null --data-urlencode "logintoken=$token" \
  -d username=admin --data-urlencode "password=Smoke-Test-1" "http://localhost:$port/login/index.php"
profile_code() { curl -s -b "$jar" -o /dev/null -w '%{http_code}' "http://localhost:$port/user/profile.php"; }
[[ "$(profile_code)" == 200 ]] || fail "login did not stick ($(profile_code))"
keys=$(dc exec -T redis redis-cli --scan --pattern '*session_*' | wc -l)
(( keys > 0 )) || fail "no session keys in Redis"
files=$(dc exec -T app sh -c 'ls /moodledata/sessions 2>/dev/null | grep -c "^sess_" || true')
[[ "$files" == 0 ]] || fail "$files session files in moodledata"
pass "REDIS_HOST: sessions live in Redis ($keys keys), none in moodledata"
dc restart app >/dev/null
wait_up
[[ "$(profile_code)" == 200 ]] || fail "login lost across an app restart ($(profile_code))"
pass "a login survives an app restart"

# ---- no SMTP_HOSTS ----------------------------------------------------------------------
setenv_up SMTP_HOSTS
[[ "$(smtp_forced)" == free ]] || fail "smtphosts still forced with SMTP_HOSTS empty"
pass "without SMTP_HOSTS the admin sets SMTP"

echo "smoke-env: PASS"
