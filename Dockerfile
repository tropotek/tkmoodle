# syntax=docker/dockerfile:1
FROM composer:2 AS composer

# runtime: PHP extensions, Caddy and Composer. No Moodle code. Git and unzip are not
# here: sis-composer-install adds them for the one RUN that needs them.
FROM dunglas/frankenphp:1.13-php8.4-trixie AS runtime
LABEL org.opencontainers.image.source=https://github.com/tropotek/tkmoodle
WORKDIR /app

# en_AU is the locale Moodle's English language pack asks for.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates locales aspell ghostscript \
    && localedef -i en_AU -c -f UTF-8 -A /usr/share/locale/locale.alias en_AU.UTF-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN install-php-extensions intl zip soap gd mysqli pdo_mysql exif xsl opcache sockets tidy redis
COPY --from=composer /usr/bin/composer /usr/local/bin/composer

ARG APP_UID=1000
# The base image already lets frankenphp bind ports 80 and 443; setting the capability
# again would copy the 59 MB binary into another layer.
RUN useradd -m -u ${APP_UID} -g www-data moodle \
    && mkdir -p /moodledata /sis/bin /sis/www /sis/run /sis/institution /sis/config /sis/host \
    && echo '{}' > /sis/institution/settings.json \
    && chown -R moodle:www-data /app /config /data/caddy /moodledata /sis
ENV PATH="/sis/bin:${PATH}"
COPY --chmod=0755 docker/sis-composer-install /sis/bin/
USER moodle

# core: Moodle from the root lock.
FROM runtime AS core
COPY --chown=moodle:www-data composer.json composer.lock /app/
USER root
RUN --mount=type=cache,id=composer,target=/var/cache/composer sis-composer-install
USER moodle

# release: config, harness and internal plugins. All of it comes after composer install,
# so editing any of it reuses the Moodle layer, and no institution lock can remove the
# internal plugins.
FROM core AS release
COPY --link docker/php.ini /usr/local/etc/php/conf.d/zz-sis.ini
COPY --link docker/Caddyfile /etc/caddy/Caddyfile
COPY --chown=moodle:www-data --chmod=0755 docker/sis-entrypoint docker/sis-cron docker/sis-settings.php docker/sis-db.php dbtools/sis-host-check /sis/bin/
COPY --chown=moodle:www-data docker/sis-settings-lib.php /sis/bin/
COPY --chown=moodle:www-data docker/up.php /sis/www/up.php
COPY --chown=moodle:www-data docker/config.php /app/moodle/config.php
COPY --chown=moodle:www-data plugins/local/ /app/moodle/public/local/
# Which release this image is; the entrypoint records it in the database. Last in the
# stage so a new release number invalidates no cached layer. Institution images add
# SIS_INSTITUTION; without one the site records "base".
ARG SIS_RELEASE=dev
ENV SIS_RELEASE=${SIS_RELEASE}
EXPOSE 80 443
ENTRYPOINT ["sis-entrypoint"]
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

# dev: release plus an editor, for bin/dev, and git and unzip, for bin/composer.
FROM release AS dev
USER root
RUN apt-get update && apt-get install -y --no-install-recommends vim-nox git unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
USER moodle

FROM release
