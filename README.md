# frappe-hr-image

Container image for **Frappe v16 + ERPNext + Frappe HR**, deployed at
`hr.virtualmindshub.app` on Coolify.

- Pinned apps: see [`apps.json`](apps.json) (ERPNext `v16.34.2`, HRMS `v16.18.1`).
- Built by [`.github/workflows/build.yml`](.github/workflows/build.yml) from
  [frappe_docker](https://github.com/frappe/frappe_docker)'s
  `images/layered/Containerfile` at a pinned commit, with `apps.json` passed as a
  BuildKit secret.
- Published to `ghcr.io/gasmsyteacher/frappe-hr` with tags `v16`,
  `erpnext-<ver>-hrms-<ver>` and `sha-<commit>`. Deploy the versioned tag, not `v16`.

To upgrade: bump the tags in `apps.json`, push, wait for the build, then change the
image tag in the Coolify compose and redeploy (the `create-site` job runs
`bench migrate` on an existing site).

Why `FRAPPE_BRANCH` is `version-16` and not a release tag: the layered Containerfile
also uses it as the tag of `frappe/build` and `frappe/base`, and `frappe/build` has
no per-release tags.

## Frontend healthcheck

`frontend` is health-checked with a real `GET /api/method/ping` (it must answer
`pong`), not a bare TCP write. This matters more than log noise: Traefik stops
routing to a container whose healthcheck fails, so a wrong check takes the site
offline.

Correction to commit "Trust Traefik's forwarded client IP, and health-check over
HTTP": its message says the check was tested. The test run at that commit was
invalid (the stand-in server's port was already in use, so every case hit an
unrelated listener), and a second attempt started the stand-in inside a command
substitution that waited for it to exit. The check was validated afterwards, with
the stand-in confirmed listening and logging the exact request:

| case | result |
|---|---|
| 200 + `pong` | healthy |
| nginx up, backend down (502) | unhealthy |
| 200 without `pong` | unhealthy |
| nothing listening | unhealthy |

## Outgoing mail (password resets)

Set these in Coolify → `erpnext-hr` → **Environment Variables**, then **Redeploy**:

| Variable | Example |
|---|---|
| `MAIL_SERVER` | `smtp.gmail.com` |
| `MAIL_PORT` | `587` — must be STARTTLS; 465 does not work on this route |
| `MAIL_LOGIN` | `mail@virtualmindshub.com` |
| `MAIL_PASSWORD` | a Google **app password** dedicated to this site |
| `MAIL_FROM` | `mail@virtualmindshub.com` (defaults to `MAIL_LOGIN`) |
| `MAIL_SENDER_NAME` | display name on outgoing mail |

The `configurator` container writes them to `common_site_config.json` and logs
`smtp login test: OK (no message sent)` or `FAILED`. A default outgoing
**Email Account** created in the ERPNext UI takes precedence over these settings.
