# shellcheck shell=bash
# shellcheck disable=SC2154  # SUITE, PROJECT and DEFAULT_PORT are set by the suite that sources this
# Shared set-up for the smoke suites in tests/smoke/, which bin/smoke runs. A suite sets SUITE
# (its output prefix), PROJECT (its compose project) and DEFAULT_PORT, sources this file, builds
# its images, calls smoke_init, writes its .env with smoke_env, then runs its checks.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

FAIL_LOGS=app
cleanup_steps=()

# smoke_init: the port, the timeout and a work folder holding a copy of host/compose.yml.
smoke_init() {
  port=${SMOKE_PORT:-$DEFAULT_PORT}
  timeout=${SMOKE_TIMEOUT:-600}
  work=$(mktemp -d)
  mkdir "$work/config" "$work/backups"
  cp host/compose.yml "$work/"
  compose_files=(-f "$work/compose.yml")
  trap smoke_cleanup EXIT
}

# smoke_env [<line>…]: the site's .env, the lines every suite shares and then the suite's own.
smoke_env() {
  {
    printf '%s\n' SIS_ENV=local "WWWROOT=http://localhost:$port" "HTTP_PORT=$port" \
      "HTTPS_PORT=$((port + 1))" DB_PASS=smoke ADMIN_PASS=Smoke-Test-1 COMPOSE_PROFILES=db
    if (($#)); then printf '%s\n' "$@"; fi
  } > "$work/.env"
}

# smoke_compose <file>: add a compose override the suite has written.
smoke_compose() { compose_files+=(-f "$1"); }

# smoke_bind_hostmarker: bind the hostmarker volume to a folder the suite fills with marker.
smoke_bind_hostmarker() {
  mkdir "$work/hostmarker"
  cat > "$work/compose.hostmarker.yml" <<EOF
volumes:
  hostmarker:
    driver_opts: {type: none, o: bind, device: $work/hostmarker}
EOF
  smoke_compose "$work/compose.hostmarker.yml"
}

# smoke_on_cleanup <function>: run it at the end, before the stack comes down.
smoke_on_cleanup() { cleanup_steps+=("$1"); }

smoke_cleanup() {
  local step
  if [[ "${SMOKE_KEEP:-}" == 1 ]]; then
    echo "$SUITE: left running in $work; stop with: docker compose -p $PROJECT --project-directory $work ${compose_files[*]} down -v"
    return
  fi
  # The ${…+…} form keeps an empty list legal under set -u in bash 3.2 (macOS).
  for step in ${cleanup_steps[@]+"${cleanup_steps[@]}"}; do "$step"; done
  dc down -v --remove-orphans >/dev/null 2>&1 || true
  chmod -R u+rwx "$work" 2>/dev/null || true
  rm -rf "$work"
}

# Quiet builds: a failure still prints its error. <release> becomes SIS_RELEASE.
smoke_build_base() {
  local args=(-q -t "$1")
  if [[ -n "${2:-}" ]]; then args+=(--build-arg "SIS_RELEASE=$2"); fi
  docker build "${args[@]}" . >/dev/null
}
smoke_build_dbtools() {
  local args=(-q -t "$1")
  if [[ -n "${2:-}" ]]; then args+=(--build-arg "SIS_RELEASE=$2"); fi
  docker build "${args[@]}" dbtools >/dev/null
}
smoke_build_institution() {  # smoke_build_institution <inst> <base tag> <tag>
  docker build -q -f institutions/Dockerfile --build-arg BASE_IMAGE="$2" \
    --build-arg SIS_INSTITUTION="$1" -t "$3" "institutions/$1" >/dev/null
}

dc() { docker compose -p "$PROJECT" --project-directory "$work" "${compose_files[@]}" "$@"; }

fail() {
  local svc
  echo "$SUITE: FAIL $*" >&2
  for svc in $FAIL_LOGS; do dc logs --tail 40 "$svc" >&2 || true; done
  exit 1
}
pass() { echo "$SUITE: ok   $*"; }

# refused <text> <command…>: the command must fail and its output must contain the text.
refused() {
  local want=$1 out
  shift
  if out=$("$@" 2>&1); then fail "not refused: $*"; fi
  [[ "$out" == *"$want"* ]] || fail "refusal of '$*' lacks '$want'; got: $out"
}

wait_up() {
  local deadline=$((SECONDS + timeout))
  until curl -fsS -o /dev/null "http://localhost:$port/up"; do
    (( SECONDS < deadline )) || fail "/up not 200 after ${timeout}s"
    [[ "$(dc ps -a --format '{{.State}}' app)" != exited ]] || fail "app exited"
    sleep 5
  done
}

# setenv <key> [<value>]: set a .env line, or remove it when no value is given. dbtools reads
# .env on each run; setenv_up also recreates app with it.
setenv() {
  sed -i "/^$1=/d" "$work/.env"
  if [[ $# -gt 1 ]]; then echo "$1=$2" >> "$work/.env"; fi
}
setenv_up() { setenv "$@"; dc up -d app >/dev/null; wait_up; }

# marker [<name>]: leave only that marker in the host folder (none when no name is given).
marker() { rm -f "$work/hostmarker"/*; if [[ $# -gt 0 ]]; then touch "$work/hostmarker/$1"; fi; }

tools() { dc run --rm -T dbtools "$@"; }
sql() {
  # shellcheck disable=SC2016
  tools bash -c '. /usr/local/bin/sis-dbtools-lib.sh && sis_db_init && sis_sql -e "$1"' _ "$1"
}
moodle_php() { dc exec -T app php; }
