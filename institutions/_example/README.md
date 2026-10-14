# Institution template

Copy this folder to `institutions/<name>` (no leading `_`) to add an institution;
CI builds every folder not starting with `_`.

## composer.json

- `require` lists Moodle core (`moodle/moodle`, which must equal the root lock's
  version; `bin/check-lock` enforces it) and every plugin.
- A plugin whose repo ships a `composer.json` with `"type": "moodle-<plugintype>"`
  gets a `vcs` repository entry and is required by its declared name.
- Any other plugin gets an inline `package` entry: `name` (`<owner>/moodle-<component>`),
  `version` (its `$plugin->version`), `type` (`moodle-<plugintype>`) and a git
  `source` with the exact commit as `reference`. Upgrading is editing `version` and
  `reference`.
- Add `"no-api": true` to every `vcs` entry. Composer then clones with plain git
  instead of calling the GitHub API, so neither you nor CI needs a GitHub token.
- A plugin that uses git submodules (for example `mod_hvp`) arrives without them.
  Add a `post-install-cmd` script that runs
  `git -C moodle/public/<path> submodule update --init --recursive`.
- Keep the `config` block as it is: `composer/installers` must stay disabled or it
  installs plugins outside `moodle/public`.
- Re-lock after any change: `bin/composer <name> update --no-install`.

## settings.json

- `defaults.core` / `defaults.plugins.<component>`: applied once on first install,
  editable in the admin UI afterwards.
- `locked.core` / `locked.plugins.<component>`: applied on every start, read-only
  in the admin UI. Connection settings (`wwwroot`, `db*`, ...) are refused here.
- Values are strings; `true`/`false` become `"1"`/`""`. `${VAR}` is read from the
  host's `.env`, and a key whose variable is empty is skipped.
