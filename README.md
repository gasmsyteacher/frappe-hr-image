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
