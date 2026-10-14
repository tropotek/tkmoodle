# Upgrading and recovery

An upgrade is a new `TAG` and the same two commands as the install. Take a backup first: Moodle
cannot move a database back to an older version.

## Back up

```bash
docker compose run --rm dbtools sis-backup
```

The site stays up while it runs. The backup lands in `backups/<date-time>/`, or give it a name:
`sis-backup before-5.3.0-4`. Add `--maintenance` to show Moodle's maintenance page while it runs,
for a backup nobody can change halfway. The first run downloads the `dbtools` image, which shares
its layers with the bundled database's.

| File | Holds |
|---|---|
| `manifest.env` | the release and institution the site was running, and its Moodle version |
| `db.sql.zst` | the database. Sessions, cache flags and the settings log are kept empty |
| `moodledata.tar.zst` | uploaded files, without the caches Moodle rebuilds |

Moodle's code isn't in the backup: it's in the image, and the manifest names the release that
carries it. A backup never overwrites another, and a failed one leaves nothing behind. One
killed outright (a reboot, `docker kill`) leaves a `.<name>.partial` folder that blocks the name
until you delete it, and with `--maintenance` also leaves `climaintenance.html` in moodledata,
which keeps the site in maintenance: `docker compose exec app rm /moodledata/climaintenance.html`. Old
backups are yours to prune or copy elsewhere. [Configuration](configuration.md#backups) covers
keeping them outside the site's folder.

It works the same with an external database.

## Upgrade

```bash
sed -i 's/^TAG=.*/TAG=5.3.0-3/' .env
docker compose pull && docker compose up -d
docker compose logs -f app
```

`pull` skips `dbtools`, which is tagged with the same `TAG`. A pinned `TAG` changes its image too.
With `TAG=latest`, also run `docker compose pull dbtools`, or it stays on the release you first
backed up with.

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

Restoring replaces the database and the uploaded files with a backup:

```bash
docker compose stop app cron
docker compose run --rm dbtools sis-restore <name>
docker compose up -d
```

`sis-restore` checks everything before it changes anything, and refuses:

| Refusal | Means |
|---|---|
| `still running: app cron` / `other connection(s)` | the site is still up; stop it as above |
| `newer than …; set TAG=…` | the backup is from a newer release than this host runs. Set that `TAG` in `.env`, `docker compose pull`, and run it again |
| `from institution …` | the backup is from a different institution's site. Restoring it would drop the data of every plugin this image lacks |
| `damaged` / `incomplete` | the backup files are cut short or missing |

A backup from the same or an older release restores, and the next start upgrades it. To roll
back a failed upgrade, set the `TAG` the backup names (`grep sis_release backups/<name>/manifest.env`),
`docker compose pull`, then restore as above.

If a restore stops partway, the site is incomplete until a restore finishes; running the same
`sis-restore` again is safe.

Going back to an older `TAG` without restoring does not work: Moodle refuses with `Cannot
downgrade`, and the site stays in maintenance.

## Health

`/up` answers `ok` (200) once the site has booted, and `booting` (503) while it installs or
upgrades. It is outside Moodle, so it answers even when Moodle cannot, which makes it the address
to point monitoring at.
