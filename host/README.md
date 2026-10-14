# Running a tkmoodle image

Copy `compose.yml`, `.env.example` (as `.env`) and the `config/` and `backups/` folders to the
server, fill in `.env`, then:

    docker compose pull && docker compose up -d

Installation, upgrades, backups and every setting:
https://tropotek.github.io/tkmoodle/installation/
