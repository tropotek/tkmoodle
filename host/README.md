# Running a tkmoodle image

Copy `compose.yml`, `.env.example` (as `.env`) and the `config/` and `backups/` folders to the
server, fill in `.env`, then:

    docker compose pull && docker compose up -d

Never edit `compose.yml`: every choice is in `.env`, so a release can replace the file.

On a server, first create `/etc/tkmoodle` with its environment marker and set
`SIS_HOST_DIR=/etc/tkmoodle` in `.env`: https://tropotek.github.io/tkmoodle/configuration/#host-markers

Installation, upgrades, backups and every setting:
https://tropotek.github.io/tkmoodle/installation/
