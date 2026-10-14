# Institutions and plugins

An institution is a folder under `institutions/` holding only data. CI builds every folder whose
name doesn't start with `_` into its own image.

| File | Holds |
|---|---|
| `composer.json` | the plugins, each pinned to an exact commit |
| `composer.lock` | what Composer resolved; commit it with every change |
| `settings.json` | Moodle settings: `defaults` and `locked` ([Configuration](configuration.md#site-settings)) |

## Add an institution

```bash
cp -r institutions/_example institutions/<name>
bin/composer <name> update --no-install      # writes composer.lock
bin/smoke <name>
```

The name becomes the image `ghcr.io/tropotek/moodle-<name>` on the next release.

## Plugins

Composer gets a plugin in one of two ways, depending on whether its repository ships a
`composer.json` with `"type": "moodle-<plugintype>"`.

| The plugin's repo | In `composer.json` | Managed with |
|---|---|---|
| has a typed `composer.json` | a `vcs` repository entry, and `require` by its declared name | Composer |
| has none (most) | an inline `package` entry: name, version, type, git URL and commit | `bin/plugin` |

### With bin/plugin

```bash
bin/plugin <name> add https://github.com/moodle-an-hochschulen/moodle-theme_boost_union.git v5.2-r12
bin/plugin <name> bump theme_boost_union v5.2-r12
bin/plugin <name> remove theme_boost_union
```

`bin/plugin` looks up the commit for the tag or branch, reads the plugin's `version.php` there,
writes the entry and re-locks. Review the diff and commit it. It handles GitHub URLs only, and
inline entries only. It is a stopgap: Moodle's own Composer repository, once it carries
Marketplace plugins, will make each plugin one `require` line.

### By hand

For a `vcs` plugin, add the repository and require it:

```json
{ "type": "vcs", "url": "https://github.com/jonof/moodle-block_completion_progress.git", "no-api": true }
```

```bash
bin/composer <name> require --no-update jonof/moodle-block_completion_progress:2026101200
bin/composer <name> update jonof/moodle-block_completion_progress --no-install
```

To remove one, delete its repository entry and run
`bin/composer <name> remove <package> --no-install`.

`"no-api": true` makes Composer clone with git rather than ask GitHub's API, so no token is needed.

### Rules

- Keep the `config` block from `_example`. `composer/installers` must stay disabled, or plugins land
  outside Moodle's folders; the audit setting lets Moodle 5.3.0's pinned Guzzle install.
- `moodle/moodle` must match the base's version exactly. `bin/check-lock` checks it, and lint fails
  on a mismatch.
- A plugin with git submodules (H5P's `mod_hvp`) arrives without them. Add a `post-install-cmd`
  script: `git -C moodle/public/mod/hvp submodule update --init --recursive`.
- Always run Composer through `bin/composer`, so the lock is resolved by the image's PHP.

## Removing a plugin from sites

Remove it from the institution and release. Each site uninstalls it, dropping its tables and
settings, on the start after it moves to that release; cron then clears its leftover blocks. The
plugin's own uninstall code doesn't run, because its code is already gone. For a plugin that keeps
data elsewhere, uninstall it in Moodle first, then remove it from the institution.
