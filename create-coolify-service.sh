#!/usr/bin/env bash
# Create (but do not start) the ERPNext + Frappe HR compose service on Coolify.
#
# Run only after: server2 capacity was confirmed and the hr A record points at
# 157.173.122.183 (DNS only). Starting the service additionally needs the image.
#
# Targets are resolved BY NAME at run time and the script refuses to continue
# unless each name matches exactly one resource. An earlier draft hardcoded a
# uuid copied from a listing that printed the environment's uuid, not the
# project's -- a remembered uuid is the easiest thing here to get wrong.
set -euo pipefail
cd "$(dirname "$0")"

SERVER_NAME=sentry                      # Coolify's name for server2
PROJECT_NAME="Collaboration & Support"
ENVIRONMENT_NAME=production
DOMAIN=https://hr.virtualmindshub.app
SERVICE_NAME=erpnext-hr
B=https://coolify.virtualmindshub.app/api/v1
ENV_FILE=/home/gasmsy/moderncert/.env.local

umask 077
HDR=$(mktemp); BODY=$(mktemp); RESP=$(mktemp)
trap 'rm -f "$HDR" "$BODY" "$RESP"' EXIT

python3 - "$ENV_FILE" > "$HDR" <<'PY'
import re, sys
for line in open(sys.argv[1]):
    m = re.match(r"^\s*coolify_api_key\s*=(.*)$", line)
    if m:
        print("Authorization: Bearer " + m.group(1).strip().strip("'\""))
        break
PY

api() { curl -s -m 60 -H @"$HDR" -H 'Accept: application/json' "$B$1"; }

# --- resolve targets by name, exactly one match each -------------------------
SERVER_UUID=$(api /servers | python3 -c '
import json, sys
m = [s for s in json.load(sys.stdin) if s.get("name") == sys.argv[1]]
if len(m) != 1: sys.exit(f"server {sys.argv[1]!r}: {len(m)} matches")
print(m[0]["uuid"])' "$SERVER_NAME")

PROJECT_UUID=$(api /projects | python3 -c '
import json, sys
m = [p for p in json.load(sys.stdin) if p.get("name") == sys.argv[1]]
if len(m) != 1: sys.exit(f"project {sys.argv[1]!r}: {len(m)} matches")
print(m[0]["uuid"])' "$PROJECT_NAME")

ENVIRONMENT_UUID=$(api "/projects/$PROJECT_UUID" | python3 -c '
import json, sys
m = [e for e in json.load(sys.stdin).get("environments", []) if e.get("name") == sys.argv[1]]
if len(m) != 1: sys.exit(f"environment {sys.argv[1]!r}: {len(m)} matches")
print(m[0]["uuid"])' "$ENVIRONMENT_NAME")

echo "server      $SERVER_NAME = $SERVER_UUID"
echo "project     $PROJECT_NAME = $PROJECT_UUID"
echo "environment $ENVIRONMENT_NAME = $ENVIRONMENT_UUID"

# --- refuse to create a duplicate or to steal the hostname -------------------
api /services | python3 -c '
import json, sys
name, host = sys.argv[1], sys.argv[2]
clash = [s["name"] for s in json.load(sys.stdin) if s.get("name") == name or host in json.dumps(s)]
if clash: sys.exit(f"refusing: already present -> {clash}")' "$SERVICE_NAME" "${DOMAIN#https://}"

# --- create -------------------------------------------------------------------
python3 - coolify-compose.yml "$SERVER_UUID" "$PROJECT_UUID" "$ENVIRONMENT_UUID" "$DOMAIN" "$SERVICE_NAME" > "$BODY" <<'PY'
import base64, json, sys
compose, server, project, env_uuid, domain, name = sys.argv[1:7]
print(json.dumps({
    "name": name,
    "description": "ERPNext v16 + Frappe HR (hr.virtualmindshub.app), image from gasmsyteacher/frappe-hr-image",
    "server_uuid": server,
    "project_uuid": project,
    "environment_uuid": env_uuid,
    "instant_deploy": False,
    "docker_compose_raw": base64.b64encode(open(compose, "rb").read()).decode(),
    # matched by sub-service name; Coolify checks the hostname against every other resource
    "urls": [{"name": "frontend", "url": domain}],
}))
PY

code=$(curl -s -m 90 -o "$RESP" -w '%{http_code}' -X POST -H @"$HDR" \
  -H 'Content-Type: application/json' --data-binary @"$BODY" "$B/services")
echo "POST /services -> $code"
python3 -m json.tool "$RESP" | head -40
[ "$code" = "201" ] || exit 1

uuid=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['uuid'])" "$RESP")
echo "service uuid: $uuid"
echo "$uuid" > .service_uuid

# --- read back what Coolify actually parsed ------------------------------------
api "/services/$uuid" | python3 -c '
import json, sys
s = json.load(sys.stdin)
print("status:", s.get("status"))
for a in s.get("applications", []):
    print("  %-13s %-62s fqdn=%s excluded=%s" % (a["name"], a.get("image"), a.get("fqdn"), a.get("exclude_from_status")))
for d in s.get("databases", []):
    print("  %-13s %-62s (database)" % (d["name"], d.get("image")))
'
api "/services/$uuid/envs" | python3 -c '
import json, sys
d = json.load(sys.stdin)
keys = sorted(e["key"] for e in d) if isinstance(d, list) else d
print("env keys (values never returned):", keys)
'
