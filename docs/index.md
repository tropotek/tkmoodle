# tkmoodle

tkmoodle ships Moodle as Docker images. CI builds a base image with Moodle core, then one image
per institution with that institution's plugins installed by Composer. A server runs an image with
a `compose.yml` and an `.env`, and never builds anything. Installing, upgrading Moodle or its
plugins, and removing a plugin are all the same two commands:

```bash
docker compose pull && docker compose up -d
```

!!! note "Proof of concept"
    tkmoodle is a proof of concept on Moodle 5.3. It runs on amd64, publishes public images, and
    has no backup tooling of its own yet.

## How a change reaches a site

1. A developer changes an institution's plugins (`composer.json` and its lock) or settings
   (`settings.json`), and opens a pull request. Lint checks it in about 10 seconds.
2. Tagging a release (`v5.3.0-2`) makes CI build the base image, then each institution's image on
   that exact base, and push them to GitHub's registry.
3. A server sets `TAG=5.3.0-2` in its `.env` and runs `pull` and `up`.
4. On start, the app container writes the institution's locked settings into Moodle's config, then
   installs Moodle or upgrades it, uninstalling any plugin the new image no longer carries. A second
   container from the same image runs Moodle's cron.

## What is in the repository

| Path | What it is |
|---|---|
| `Dockerfile`, `composer.json` | the base image: FrankenPHP, PHP extensions and Moodle core |
| `docker/` | the entrypoint, the settings renderer, web server and PHP config |
| `plugins/` | internal plugins, baked into every image |
| `institutions/<name>/` | one institution, data only: `composer.json`, its lock, `settings.json` |
| `institutions/Dockerfile` | builds any institution on the base image |
| `host/` | what a server needs: `compose.yml` and `.env.example` |
| `bin/` | developer commands: `dev`, `smoke`, `composer`, `plugin`, `check-lock` |

## Guides

| Guide | For |
|---|---|
| [Server installation](installation.md) | putting a site on a server |
| [Upgrading and recovery](upgrading.md) | moving a site to a new release, backups, a failed upgrade, rolling back |
| [Configuration](configuration.md) | every `.env` setting, and the `defaults` and `locked` site settings |
| [Development](development.md) | the local stack, live plugin edits, tests |
| [Institutions and plugins](institutions.md) | adding an institution, adding or updating its plugins |
| [Releasing](releasing.md) | tagging a release, and moving to a new Moodle version |
| [Plugin provisioning](provisioning.md) | how a plugin sets up its own services, tokens and SSO |
