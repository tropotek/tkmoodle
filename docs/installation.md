# Server installation

A server needs Docker and two files. It pulls a published image and never builds or checks out
any code.

## Requirements

- Docker Engine with the Compose plugin.
- About 3 GB of disk for the image, plus the site's files and database.
- Ports 80 and 443 reachable, for a site with a real hostname.

## Install

1. Make a folder for the site and fetch the compose file and the settings template:

    ```bash
    mkdir moodle && cd moodle
    curl -fsSLO https://raw.githubusercontent.com/tropotek/tkmoodle/main/host/compose.yml
    curl -fsSL https://raw.githubusercontent.com/tropotek/tkmoodle/main/host/.env.example -o .env
    mkdir config backups
    ```

2. Edit `.env`. At least set:

    | Setting | Example |
    |---|---|
    | `INSTITUTION` | `demo` (the image is `ghcr.io/tropotek/moodle-demo`) |
    | `TAG` | `5.3.0-3`. Pin a release; avoid `latest` on a real site |
    | `WWWROOT` | `https://moodle.example.com` |
    | `DB_PASS` | a long random password |
    | `ADMIN_PASS` | the first admin's password. Use a strong one: the installer doesn't check it against Moodle's password policy |
    | `ADMIN_EMAIL` | the first admin's email |

    [Configuration](configuration.md) lists every setting.

3. Start it:

    ```bash
    docker compose pull && docker compose up -d
    docker compose logs -f app
    ```

    The first start installs Moodle and every plugin, which takes about two minutes. It is done when
    the log shows `sis: boot done`. Then `https://moodle.example.com/up` answers `ok`.

4. Log in as `admin` with `ADMIN_PASS`. That account is created once. Changing `ADMIN_PASS`
   later has no effect; change the password in Moodle.

## HTTPS

When `WWWROOT` starts with `https://`, the web server gets a Let's Encrypt certificate for its
hostname on the first request. The hostname's DNS must already point at the server, with ports 80
and 443 open (`HTTP_PORT=80`, `HTTPS_PORT=443`). An `http://` address serves plain HTTP, which suits
local testing.

## What runs

| Service | Does |
|---|---|
| `app` | installs or upgrades Moodle on start, then serves it. It reports healthy once booted |
| `cron` | runs Moodle's cron every minute, from the same image |
| `db` | MySQL 8.4. Optional; see below |
| `preupgrade` | runs before `app` on each start, and backs up before a release upgrade ([Upgrading](upgrading.md#automatic-backup-before-an-upgrade)) |
| `dbtools` | backup and restore, run by hand ([Upgrading](upgrading.md#back-up)). `up` skips it |

The site's data lives in Docker volumes named after the folder's project: `moodle_moodledata`
(uploaded files) and `moodle_db` (the database). `moodle_caddy_data` holds the certificates.

## An external database

The bundled `db` service suits a single server. To use an existing MySQL 8.4 server instead:

1. In `compose.yml`, delete the `db` service, the `db` entry under `app`'s `depends_on` (keep
   `preupgrade`), the `depends_on` block under `preupgrade`, and the `db` volume.
2. In `.env`, set `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` and `DB_PASS`.

The database must be empty for the first start and use `utf8mb4` with `utf8mb4_unicode_ci`.

## Overriding the institution's settings

The image carries its institution's `settings.json`. A server can override any of it with its own
`config/settings.json` in the same shape: see [Configuration](configuration.md#site-settings).
