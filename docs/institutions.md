# Institutions and plugins

An institution is a folder under `institutions/` holding only data. CI builds every folder whose
name doesn't start with `_` into its own image.

| File | Holds |
|---|---|
| `composer.json` | the plugins, each pinned to a commit or a version tag |
| `composer.lock` | what Composer resolved; commit it with every change |
| `settings.json` | Moodle settings: `defaults` and `locked`, never connection or path settings ([Configuration](configuration.md#site-settings)) |

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
| has a typed `composer.json` | a `vcs` repository entry, and `require` by its declared name | `bin/plugin` (version tag) or by hand |
| has none (most) | an inline `package` entry: name, version, type, git URL and commit | `bin/plugin` |

### With bin/plugin

```bash
bin/plugin <name> add https://github.com/moodle-an-hochschulen/moodle-theme_boost_union.git v5.2-r12
bin/plugin <name> bump theme_boost_union v5.2-r12
bin/plugin <name> remove theme_boost_union
```

`bin/plugin` reads the plugin's `version.php` at the tag, branch or commit, writes the entry
and re-locks. Review the diff and commit it. If a step fails part-way, it puts
`composer.json` and `composer.lock` back as they were.

- The URL is `https://<host>/<owner>/<repo>` on any git host. An inline entry's package is
  named `<owner>/moodle-<component>`. Deeper paths, such as GitLab subgroups, aren't supported.
- A plugin whose repository has a typed `composer.json` gets a `vcs` entry instead, required
  by its own package name. It takes a tag only, and the tag must read as a version, such as
  `2026081302` or `v5.5.1`.
- It tells an unreachable URL apart from a ref that doesn't exist.

It is a stopgap: Moodle's own Composer repository, once it carries Marketplace plugins, will
make each plugin one `require` line.

### By hand

To add a `vcs` plugin without `bin/plugin`, add the repository and require it:

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
