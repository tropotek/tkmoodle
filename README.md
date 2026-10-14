# tkmoodle

Moodle shipped as images. The repo builds a base image (FrankenPHP and Moodle
core), then one image per institution with that institution's plugins
installed by Composer. A host runs a published image with `host/compose.yml`
and an `.env`. It never builds anything.

| Path | What it is |
|---|---|
| `Dockerfile`, `composer.json` | the base image |
| `docker/` | entrypoint, settings renderer, web and PHP config |
| `plugins/` | internal plugins, baked into every image |
| `institutions/<name>/` | one institution: plugins (`composer.json`/lock) and `settings.json`; `_`-prefixed folders are templates |
| `host/` | what a server needs to run an image |
| `bin/` | `dev`, `smoke`, `composer`, `check-lock` |

## Local development

    bin/dev up                      # base image on http://localhost:8300
    INSTITUTION=demo bin/dev up     # an institution on the dev base
    bin/smoke demo                  # build, install, check, tear down

## Releasing

Tag `v<moodle>-<n>` (for example `v5.3.0-1`). CI publishes the base image, then
every institution.
