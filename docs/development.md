# Development

Everything runs in Docker. The host needs Docker, git and `jq`; `php` and `shellcheck` are only for
the test and lint commands below.

On macOS, the `bin/smoke` suites need GNU tools, because they use `sed -i`, `stat -c`,
`find -printf` and `date -d`. Run `brew install bash coreutils findutils gnu-sed`, then put
Homebrew's GNU tools first on `PATH`:
`PATH="$(brew --prefix)/opt/coreutils/libexec/gnubin:$(brew --prefix)/opt/findutils/libexec/gnubin:$(brew --prefix)/opt/gnu-sed/libexec/gnubin:$PATH"`.
The other `bin/` scripts run on macOS as they are.

## The local stack

```bash
bin/dev up                       # the base image on http://localhost:8300
INSTITUTION=demo bin/dev up      # an institution, built on the local base
```

`bin/dev up` builds the images and starts the app, cron, a MySQL container and Mailpit. The first start
installs Moodle. Log in as `admin` with `Dev-Admin-1`.

Mail the dev site sends lands in Mailpit, on http://localhost:8325 (`MAILPIT_PORT`).

Anything else after `bin/dev` goes to Docker Compose:

```bash
bin/dev logs -f app
bin/dev exec app php /app/moodle/admin/cli/purge_caches.php
bin/dev down        # stop; add -v to also delete the site's database and files
```

The dev stack is the repo's root `compose.yml`, so plain `docker compose …` at the root works
on it, as `bin/dev <args>` does. Copy `.env.example` to `.env` to change its ports or settings.
The host's compose file is `host/compose.yml`.

## Editing code

- **Internal plugins** (`plugins/`) are mounted into the running container, so an edit shows on
  the next page load. A new language string needs a cache purge; a version bump runs its upgrade
  on the next `bin/dev up`.
- **Harness files** (`docker/`, `Dockerfile`) are baked into the image. Run `bin/dev up` again: it
  rebuilds from cache in seconds and restarts.
- **Moodle core and third-party plugins** come from Composer, inside the image. Change them through
  an institution's `composer.json` ([Institutions and plugins](institutions.md)).

Inside the image, Moodle lives in `/app/moodle`: its command-line scripts are in
`/app/moodle/admin/cli`, and the web root and plugins are in `/app/moodle/public`.

## Checks

| Command | Checks | Time |
|---|---|---|
| `php tests/settings_test.php` | the settings renderer: validation, `${VAR}`, the rendered PHP, the command's exit codes | under a second |
| `bin/smoke [<institution>]` | the `install` suite: builds the images, installs a fresh site from `host/compose.yml`, then checks `/up`, the login page, cron, and that every locked plugin installed. Tears it all down after | about 2 minutes |
| `bin/smoke env` | runs the base image with Mailpit and Redis, and checks mail on `local` and `development`, curl on `local` and `production`, SMTP locking, and Redis sessions surviving a restart | about 3 minutes |
| `bin/smoke backup [<institution>]` | backs up a seeded site (default `demo`), checks every refusal, restores it | about 5 minutes |
| `bin/smoke upgrade` | walks one site through install, upgrades, a failed backup, the escape hatch, the app's own check and a rollback | about 4 minutes |
| `bin/smoke all [<institution>]` | the four in turn, stopping at the first failure | about 17 minutes |
| `bin/check-lock` | every institution pins the same Moodle core as the base | instant |
| `shellcheck -x docker/sis-entrypoint docker/sis-cron bin/* dbtools/sis-* tests/*.sh tests/smoke/*.sh` | the shell scripts, as lint runs it | instant |
| `bash tests/dbtools_test.sh` | the backup tools' helpers and `preupgrade`'s refusals, against a stub `mysql` | a few seconds |

Run `bin/smoke` before every release. Every suite takes `SMOKE_PORT` (each has its own default,
so suites can run side by side), `SMOKE_TIMEOUT` and `SMOKE_KEEP=1` (leave the site running and
print how to stop it; not with `all`). `install` also takes `SMOKE_ENV` (extra `.env` lines) and
`SMOKE_IMAGE` (an app image to use instead of building). The suites live in `tests/smoke/` and
share `tests/smoke/lib.sh`. Pull requests run only the lint checks in CI; tests and smoke runs
stay local.

## Layout of the harness

| File | Does |
|---|---|
| `docker/sis-entrypoint` | the container's start: settings, database wait, install or upgrade, serve |
| `docker/sis-cron` | the cron container's loop |
| `docker/sis-settings.php`, `sis-settings-lib.php` | renders `locked` settings, applies `defaults` |
| `docker/sis-db.php` | tells the entrypoint whether the database is reachable, and empty, installed or half-installed |
| `docker/config.php` | Moodle's config: reads `.env`, then the rendered locked settings |
| `docker/Caddyfile`, `php.ini` | the web server and PHP settings |
