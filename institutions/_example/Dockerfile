# An institution: the base image plus this folder's plugins and settings.
ARG BASE_IMAGE=ghcr.io/tropotek/moodle:5.3.0-1
FROM ${BASE_IMAGE}
COPY --chown=moodle:www-data composer.json composer.lock /app/
COPY --chown=moodle:www-data settings.json /sis/institution/settings.json
RUN composer install --no-dev --no-interaction --prefer-dist && composer clear-cache
