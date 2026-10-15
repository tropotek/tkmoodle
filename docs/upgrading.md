# Upgrading and recovery

An upgrade is a new `TAG` and the same two commands as the install. Moodle cannot move a database
back to an older version, so every upgrade takes a backup first, automatically
([below](#automatic-backup-before-an-upgrade)).

## Back up

```bash
docker compose run --rm dbtools sis-backup
```

Upgrades take their own backup, so a manual one is for other times: before a risky change, or to
copy a site elsewhere.

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

On start the app container:

1. turns on Moodle's maintenance mode, so visitors see a maintenance page and `/up` answers 503;
2. uninstalls any plugin the new image no longer carries, dropping its tables and settings;
3. runs Moodle's upgrade for core and every plugin;
4. turns maintenance off and logs `sis: boot done`.

Admins' changes to settings are kept. An upgrade takes about a minute and a half.

Don't stop the containers while an upgrade runs. A stop waits up to 10 minutes for it to finish;
killed halfway, it can leave the database half-upgraded.

## Automatic backup before an upgrade

Before `app` starts, the one-shot `preupgrade` service compares the release being started with
the one the database last ran. When they differ, it backs up to `backups/pre-<release>/` (for
example `pre-5.3.0-4`) and only then lets the upgrade start. Restarts on the same release and
the first install skip it in a second or two.

```bash
docker compose logs preupgrade
```

- **It takes as long as a full backup**, so a large site upgrades more slowly. The site is down
  from `up -d` until the upgrade finishes.
- **Old `pre-*` backups stay.** Delete the ones you no longer need.
- **A failed backup stops the upgrade.** `preupgrade` logs `pre-upgrade backup FAILED` and the
  reason, `app` never starts, and the site stays down until you fix the cause and run
  `docker compose up -d` again, or set `TAG` back.
- **Escape hatch:** `SKIP_PREUPGRADE_BACKUP=1` in `.env` lets one upgrade through without a
  backup. Both logs say `SKIPPING`. Remove it afterwards, or every later upgrade skips too.
- **Retrying after a failed upgrade** reuses the `pre-<release>` backup already taken, because
  the database is still on the release it holds.
- `docker compose run app …` also starts `preupgrade`. Add `--no-deps` for one-off commands.

## A failed upgrade

The log shows `sis: UPGRADE FAILED`, with Moodle's error just above it. The site stays in
maintenance mode and keeps serving the maintenance page, and `/up` answers 503.

- If a newer release fixes the cause, set its `TAG` and run `pull` and `up -d` again. Every start
  retries the upgrade.
- Otherwise, restore `pre-<the release that failed>` and set `TAG` back to the release it names
  (below).

Two other refusals stop the start:

- `Moodle cannot downgrade`: `TAG` is older than the database. Set it back, or restore a backup
  of that release.
- `UPGRADE REFUSED` (in the `app` log): the app image is newer than the `dbtools` image that
  checked the backup, usually from an `APP_IMAGE`/`DBTOOLS_IMAGE` override or a pull that only
  half finished. Run `docker compose pull` and start again.

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
