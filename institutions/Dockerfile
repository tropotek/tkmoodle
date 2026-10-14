# check=skip=InvalidDefaultArgInFrom
# Builds any institution: the base image plus one institution folder's plugins and
# settings. Usage (the folder is the build context):
#   docker build -f institutions/Dockerfile --build-arg BASE_IMAGE=<base image> institutions/<name>
# BASE_IMAGE has no default on purpose (the check directive above silences the
# warning): every build names the base it builds on.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
COPY --chown=moodle:www-data composer.json composer.lock /app/
COPY --chown=moodle:www-data settings.json /sis/institution/settings.json
RUN composer install --no-dev --no-interaction --prefer-dist && composer clear-cache
