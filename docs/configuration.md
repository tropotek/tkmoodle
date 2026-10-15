# Configuration

A site is configured in two places: the server's `.env`, for how the site runs, and
`settings.json`, for Moodle's own settings.

## .env

| Setting | Default | What it does |
|---|---|---|
| `INSTITUTION` | `demo` | which institution image to run: `ghcr.io/tropotek/moodle-<INSTITUTION>` |
| `TAG` | `latest` | which release of it. Pin one on a real site |
| `WWWROOT` | `http://localhost` | the site's address. `https://` also makes the web server fetch a certificate for its hostname |
| `HTTP_PORT`, `HTTPS_PORT` | `80`, `443` | the ports published on the server |
| `DB_HOST` | `db` | `db` is the bundled MySQL container; anything else is an external server |
| `DB_PORT`, `DB_NAME`, `DB_USER` | `3306`, `moodle`, `moodle` | the database to use |
| `DB_PASS` | none (required) | the database password; also creates the bundled database's user |
| `SITE_FULLNAME` | `Moodle` | the site name. First install only |
| `ADMIN_PASS` | none (required for the first install) | the first admin's password. First install only |
| `ADMIN_EMAIL` | `admin@example.com` | the first admin's email. First install only |
| `SISEXAMPLE_*` | empty | read by the example plugin; see [Plugin provisioning](provisioning.md) |

These have working defaults and are left out of `.env.example`:

| Setting | Default | What it does |
|---|---|---|
| `SITE_SHORTNAME` | `moodle` | the site's short name. First install only |
| `ADMIN_USER` | `admin` | the first admin's username. First install only |
| `DB_WAIT_TIMEOUT` | `120` | seconds to wait for the database on start before giving up |
| `SERVER_NAME` | from `WWWROOT` | the web server's site address, when it must differ |
| `CADDY_GLOBAL_OPTIONS` | empty | extra web server options |
| `APP_IMAGE` | from `INSTITUTION` and `TAG` | run any image instead, e.g. a local build |
| `BACKUP_DIR` | `./backups` | where `sis-backup` writes and `sis-restore` reads. The folder must exist; see [Backups](#backups) |
| `DBTOOLS_IMAGE` | `ghcr.io/tropotek/moodle-dbtools:<TAG>` | run any backup tools image instead, e.g. a local build |
| `SKIP_PREUPGRADE_BACKUP` | unset | `1` lets one upgrade start without its automatic backup ([Upgrading](upgrading.md#automatic-backup-before-an-upgrade)). Remove it afterwards |

Fixed in the image: MySQL through `mysqli`, table prefix `mdl_`, data in `/moodledata`. Installing
and updating plugins from Moodle's admin pages is turned off: plugins come only with an image.

## Backups

`sis-backup` and `sis-restore` ([Upgrading](upgrading.md#back-up)) use the folder in
`BACKUP_DIR`, `backups/` next to `compose.yml` by default. It must already exist, for every `docker compose up`, since upgrades back up into it: Docker would
otherwise create it owned by root, so compose stops with `bind source path does not exist`
instead. Each backup gets the same owner as the folder.

To keep backups elsewhere, say on a separate disk:

```bash
mkdir -p /srv/moodle-backups
echo BACKUP_DIR=/srv/moodle-backups >> .env
```

- **Docker Desktop** (macOS, Windows) only mounts folders it shares. Add the folder under
  Settings → Resources → File sharing.
- **SELinux** (Fedora, RHEL) blocks containers from a folder without the container label:
  `sudo chcon -Rt container_file_t /srv/moodle-backups`.

## Site settings

Each institution's `settings.json` holds Moodle settings in two sections:

```json
{
    "defaults": {
        "core": { "timezone": "Australia/Brisbane", "theme": "boost_union" },
        "plugins": { "local_sisexample": { "greeting": "Hello" } }
    },
    "locked": {
        "core": { "authpreventaccountcreation": true },
        "plugins": { "tool_objectfs": { "s3_bucket": "${S3_BUCKET}" } }
    }
}
```

| Section | Applied | In the admin pages |
|---|---|---|
| `defaults` | once, on the first install | editable; admins' changes are kept from then on |
| `locked` | on every start | read-only, marked "defined in config.php" |

- `core` holds Moodle's own settings by name; `plugins` holds each plugin's, by component.
- Values are stored as text: `true` becomes `"1"` and `false` becomes `""`.
- `${NAME}` is replaced with the server's `.env` value of `NAME`. When that is empty or missing, the
  setting is skipped, not set to empty. Keep secrets in `.env`, never in `settings.json`.
- Removing a key from `locked` hands the setting back to the admin pages on the next start.
- Connection settings (`wwwroot`, anything starting `db`, `prefix`, `admin`, `dataroot`) can't be
  locked; they come from `.env`. A key that isn't a valid setting name stops the start with an
  error naming it.
- Locking a setting skips the admin page's save action. Most settings need none, and the start
  clears Moodle's caches, but a setting that relies on its save action won't take effect when
  locked.

### Overriding on one server

A server can override its institution's settings by putting a `settings.json` in its `config/`
folder, in the same shape. Its keys win over the institution's; everything else stays as the image
has it. Changes take effect on the next start (`docker compose restart app`), with `defaults`
still applied only on the first install.
