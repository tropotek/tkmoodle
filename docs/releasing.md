# Releasing

A release is a git tag on `main`. It builds the base image and every institution's image, and
publishes them for servers to pull.

## Tags

Tags look like `v<moodle>-<n>`: `v5.3.0-1`, `v5.3.0-2`. The part before the dash must equal the
Moodle version in the root `composer.lock`, or the release stops. The number after it counts
releases on that Moodle version: a plugin change, a settings change or a harness fix each take the
next one.

## Release

```bash
bin/smoke demo          # and any institution you changed
git switch main && git pull
git tag v5.3.0-4 && git push origin v5.3.0-4
gh run watch            # about 5 minutes
```

The release workflow then:

1. builds the base image and pushes `ghcr.io/tropotek/moodle:5.3.0-4`;
2. builds each institution on that exact base and pushes `ghcr.io/tropotek/moodle-<name>:5.3.0-4`
   and, when it is the newest release so far, `:latest`;
3. builds the backup tools and pushes `ghcr.io/tropotek/moodle-dbtools:5.3.0-4` and, when it is
   the newest release so far, `:latest`.

Re-running an older tag, or tagging a fix on an older core, publishes its version tag only:
`:latest` stays on the newest release.

Every image records its release, and institution images their name. A site stores both in its
database on each start, and backups carry them.

A failed build publishes nothing for that institution, and servers keep running what they have.
Fix it and tag the next number. Servers move to the release by changing `TAG`
([Upgrading](upgrading.md)).

A release that adds a required `.env` setting says so in its notes. A host without it stops at
`preupgrade`, before any backup, and the site stays down until the setting is added and `up -d`
runs again. `SIS_ENV` is the first.

Pull requests only run lint: shellcheck, PHP syntax, `composer validate` and `bin/check-lock`.
Images are built only on a tag.

## A new Moodle version

Moodle core is pinned in the root `composer.json` and in every institution, and they must match.

```bash
bin/composer require --no-update moodle/moodle:5.3.1
bin/composer update moodle/moodle --with-all-dependencies --no-install
bin/composer demo require --no-update moodle/moodle:5.3.1        # each institution
bin/composer demo update moodle/moodle --with-all-dependencies --no-install
bin/check-lock && bin/smoke demo
```

Commit all the locks in one pull request, then tag `v5.3.1-1`. For a major version (5.4), check each
plugin supports it, and test each institution with `bin/dev` before the release.

## Registry

Images go to GitHub's container registry under `ghcr.io/tropotek`, built for amd64. They come out
public, because the repository is public. If the `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`
repository secrets are set, the build pulls its own base images from Docker Hub as that user, to
avoid anonymous rate limits.
