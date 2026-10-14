# One-shot database and file tools for a tkmoodle host: sis-backup and sis-restore.
# Oracle's MySQL image, so the client matches the server and builds for every platform.
FROM mysql:8.4
LABEL org.opencontainers.image.source=https://github.com/tropotek/tkmoodle
COPY --chmod=0755 sis-backup sis-restore /usr/local/bin/
COPY --chmod=0644 sis-dbtools-lib.sh /usr/local/bin/
ARG SIS_RELEASE=dev
ENV SIS_RELEASE=${SIS_RELEASE}
ENTRYPOINT []
CMD ["sh", "-c", "echo 'usage: docker compose run --rm dbtools sis-backup [--maintenance] [<name>] | sis-restore <name>'"]
