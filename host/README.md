# Running an image

1. Copy this folder to the server. Copy `.env.example` to `.env`, then set
   `INSTITUTION`, `TAG`, `WWWROOT`, `SERVER_NAME` and every password.
2. Run `docker compose pull && docker compose up -d`.
3. Watch the first install with `docker compose logs -f app` until `sis: boot done`.

## Upgrading

Change `TAG`, then run `docker compose pull && docker compose up -d`. The app
container upgrades Moodle and its plugins on start. A plugin missing from the new
image is uninstalled.

**Take a database backup before every upgrade.** Moving back to an older `TAG`
without restoring the database from before the upgrade is not supported, because
Moodle cannot downgrade a schema.

## Settings

The institution's `settings.json` is baked into the image. To override it on this
host, put a `settings.json` with the same shape in `config/`:

- `defaults` are applied once, on the first install, and stay editable in the
  admin UI.
- `locked` keys are applied on every start and show read-only in the admin UI.

A `${VAR}` value is read from `.env`. When the variable is empty, the key is
skipped.

## External database

Delete the `db` service, its `depends_on` under `app`, and the `db` volume from
`compose.yml`, then point the `DB_*` values in `.env` at the server.

## Health

`/up` returns 200 once the site has booted, and 503 while it installs or upgrades.
