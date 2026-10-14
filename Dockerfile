# syntax=docker/dockerfile:1
FROM composer:2 AS composer

# runtime: PHP extensions, Caddy and Composer. No Moodle code.
FROM dunglas/frankenphp:1.13-php8.4-trixie AS runtime
LABEL org.opencontainers.image.source=https://github.com/tropotek/tkmoodle
WORKDIR /app

# en_AU is the locale Moodle's English language pack asks for.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl git unzip ca-certificates locales aspell ghostscript \
    && localedef -i en_AU -c -f UTF-8 -A /usr/share/locale/locale.alias en_AU.UTF-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN install-php-extensions intl zip soap gd mysqli pdo_mysql exif xsl opcache sockets tidy
COPY --from=composer /usr/bin/composer /usr/local/bin/composer

ARG APP_UID=1000
RUN useradd -m -u ${APP_UID} -g www-data moodle \
    && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    && mkdir -p /moodledata /sis/bin /sis/www /sis/run /sis/institution /sis/config \
    && echo '{}' > /sis/institution/settings.json \
    && chown -R moodle:www-data /app /config /data/caddy /moodledata /sis
ENV PATH="/sis/bin:${PATH}"
COPY docker/php.ini /usr/local/etc/php/conf.d/zz-sis.ini
COPY docker/Caddyfile /etc/caddy/Caddyfile
USER moodle

# core: Moodle from the root lock.
FROM runtime AS core
COPY --chown=moodle:www-data composer.json composer.lock /app/
RUN composer install --no-dev --no-interaction --prefer-dist && composer clear-cache

# release: harness and internal plugins. Internal plugins are copied after
# composer install, so no institution lock can remove them.
FROM core AS release
COPY --chown=moodle:www-data --chmod=0755 docker/sis-entrypoint docker/sis-cron docker/sis-settings.php docker/sis-db.php /sis/bin/
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

# dev: release plus an editor, for bin/dev.
FROM release AS dev
USER root
RUN apt-get update && apt-get install -y --no-install-recommends vim-nox \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
USER moodle

FROM release
