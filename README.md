# tkmoodle

Moodle shipped as images. CI builds a base image (FrankenPHP and Moodle core), then one image per
institution with its plugins installed by Composer. A server runs an image with `host/compose.yml`
and an `.env`, and never builds anything.

**Documentation: https://tropotek.github.io/tkmoodle/** (sources in `docs/`).

    bin/dev up                      # local stack on http://localhost:8300
    bin/smoke demo                  # build, install, check, tear down
