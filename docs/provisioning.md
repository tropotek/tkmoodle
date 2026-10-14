# Plugin provisioning

A plugin that needs more than settings — a web service and token to pair with another system, an
SSO issuer, roles, categories — creates them itself. Nothing in the harness knows about them, so a
new integration is a plugin change, never a new script.

`local_sisexample` shows the pattern. It creates a web service with its user and token (a stand-in
for pairing), an OAuth2 issuer (a stand-in for SSO), a role and a course category.

## Shape

| File | Does |
|---|---|
| `classes/provisioner.php` | `apply()` creates or fixes everything; `check()` lists what differs, changing nothing |
| `db/install.php` | calls `apply()` when the plugin is installed: on a fresh site, or added to an existing one |
| `db/upgrade.php` | calls `apply()` again from an upgrade step, when what it creates changes |
| `cli/provision.php` | runs it by hand: `--check` reports drift (exit 2), `--show-token` prints the token |

```bash
docker compose exec app php /app/moodle/public/local/sisexample/cli/provision.php --check
```

## Rules

- **Find, then create or fix.** Each object is looked up by a stable key (a service's short name,
  a role's short name, a category's idnumber, an issuer's name), so running it again changes
  nothing.
- **Read `locked` settings and `.env`, never `defaults`.** `defaults` are applied after Moodle's
  install, so a plugin installed during it can't see them.
- **Secrets come from `.env`.** Generated secrets, such as the token, are created by the plugin and
  never configured. The log shows only their last four characters.
- **A change ships as a version bump.** Add an upgrade step that calls `apply()`.
- **Skip what isn't configured.** The SSO issuer is created only when all `SISEXAMPLE_SSO_*` settings
  are set.

## The example's settings

| Setting | Used for |
|---|---|
| `SISEXAMPLE_REMOTE_URL` | the paired system's address, locked as `local_sisexample/remoteurl` |
| `SISEXAMPLE_SSO_ISSUER`, `SISEXAMPLE_SSO_CLIENT_ID`, `SISEXAMPLE_SSO_SECRET` | the OAuth2 issuer: its base URL, client ID and secret |

## Moodle details that bite

- A created user's password must meet the site's password policy: use `generate_password()`.
- An OAuth2 issuer needs `image` set (an empty string will do); the database refuses null.
- An exception in `apply()` fails the install or upgrade. The next start retries, reusing what was
  already created.
