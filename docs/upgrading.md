# Upgrading and recovery

An upgrade is a new `TAG` and the same two commands as the install. Take a backup first: Moodle
cannot move a database back to an older version.

## Back up

Stop the site so nothing changes mid-backup, then copy the database and the uploaded files:

```bash
docker compose stop app cron
docker compose exec -T db sh -c 'mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --single-transaction --no-tablespaces "$MYSQL_DATABASE"' > moodle-db.sql
docker run --rm -v moodle_moodledata:/data -v "$PWD":/backup alpine tar czf /backup/moodledata.tgz -C /data .
docker compose start app cron
```

With an external database, take the dump on that server instead.

## Upgrade

```bash
sed -i 's/^TAG=.*/TAG=5.3.0-3/' .env
docker compose pull && docker compose up -d
docker compose logs -f app
```

On start the app container:

1. turns on Moodle's maintenance mode, so visitors see a maintenance page and `/up` answers 503;
2. uninstalls any plugin the new image no longer carries, dropping its tables and settings;
3. runs Moodle's upgrade for core and every plugin;
4. turns maintenance off and logs `sis: boot done`.

Admins' changes to settings are kept. An upgrade takes about a minute and a half.

Don't stop the containers while an upgrade runs. A stop waits up to 10 minutes for it to finish;
killed halfway, it can leave the database half-upgraded.

## A failed upgrade

The log shows `sis: UPGRADE FAILED`, with Moodle's error just above it. The site stays in
maintenance mode and keeps serving the maintenance page, and `/up` answers 503.

- If a newer release fixes the cause, set its `TAG` and run `pull` and `up -d` again. Every start
  retries the upgrade.
- Otherwise, restore the backup and go back to the previous `TAG` (below).

## An incomplete first install

The log shows `sis: INCOMPLETE INSTALL`, and the app container keeps restarting with it. The first
install died partway,
so the database holds some Moodle tables. Empty the database and start again. With the bundled
database, that is:

```bash
docker compose down
docker volume rm moodle_db moodle_moodledata
docker compose up -d
```

!!! warning
    This deletes the site's database and files. Use it only on a site that never finished installing.

## Restore and roll back

Restoring replaces the database and the files with the backup, then runs the release that made it:

```bash
docker compose down
docker volume rm moodle_db moodle_moodledata
sed -i 's/^TAG=.*/TAG=5.3.0-2/' .env   # the release the backup was taken on
docker compose up -d --wait db
docker compose exec -T db sh -c 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' < moodle-db.sql
docker compose up --no-start
docker run --rm -v moodle_moodledata:/data -v "$PWD":/backup alpine tar xzf /backup/moodledata.tgz -C /data
docker compose up -d
```

Going back to an older `TAG` without restoring does not work: Moodle refuses with `Cannot
downgrade`, and the site stays in maintenance.

## Health

`/up` answers `ok` (200) once the site has booted, and `booting` (503) while it installs or
upgrades. It is outside Moodle, so it answers even when Moodle cannot, which makes it the address
to point monitoring at.
