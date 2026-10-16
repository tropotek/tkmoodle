# check=skip=InvalidDefaultArgInFrom
# Builds any institution: the base image plus one institution folder's plugins and
# settings. Usage (the folder is the build context):
#   docker build -f institutions/Dockerfile --build-arg BASE_IMAGE=<base image> \
#     --build-arg SIS_INSTITUTION=<name> institutions/<name>
# BASE_IMAGE has no default on purpose (the check directive above silences the
# warning): every build names the base it builds on. SIS_INSTITUTION is required too.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG SIS_INSTITUTION
ENV SIS_INSTITUTION=${SIS_INSTITUTION}
COPY --chown=moodle:www-data composer.json composer.lock /app/
USER root
RUN --mount=type=cache,id=composer,target=/var/cache/composer \
    test -n "$SIS_INSTITUTION" || { echo "SIS_INSTITUTION build arg is required" >&2; exit 1; }; \
    sis-composer-install
USER moodle
# After composer install, so editing settings reuses the plugin layer.
COPY --chown=moodle:www-data settings.json /sis/institution/settings.json
