# Development

Everything runs in Docker. The host needs Docker, git and `jq`; `php` and `shellcheck` are only for
the test and lint commands below.

## The local stack

```bash
bin/dev up                       # the base image on http://localhost:8300
INSTITUTION=demo bin/dev up      # an institution, built on the local base
```

`bin/dev up` builds the images and starts the app, cron and a MySQL container. The first start
installs Moodle. Log in as `admin` with `Dev-Admin-1`.

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
| `bin/smoke [<institution>]` | builds the images, installs a fresh site from `host/compose.yml`, then checks `/up`, the login page, cron, and that every locked plugin installed. Tears it all down after | about 2 minutes |
| `bin/check-lock` | every institution pins the same Moodle core as the base | instant |
| `shellcheck docker/sis-entrypoint docker/sis-cron bin/*` | the shell scripts | instant |

Run `bin/smoke` before every release. It takes `SMOKE_PORT` (default 8399), `SMOKE_KEEP=1` (leave
the site running and print how to stop it) and `SMOKE_ENV` (extra `.env` lines). Pull requests run
only the lint checks in CI; tests and smoke runs stay local.

## Layout of the harness

| File | Does |
|---|---|
| `docker/sis-entrypoint` | the container's start: settings, database wait, install or upgrade, serve |
| `docker/sis-cron` | the cron container's loop |
| `docker/sis-settings.php`, `sis-settings-lib.php` | renders `locked` settings, applies `defaults` |
| `docker/sis-db.php` | tells the entrypoint whether the database is reachable, and empty, installed or half-installed |
| `docker/config.php` | Moodle's config: reads `.env`, then the rendered locked settings |
| `docker/Caddyfile`, `php.ini` | the web server and PHP settings |
