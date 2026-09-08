#!/usr/bin/env bash
# Test the deployed Hello iFlow.
# Replace <tenant>, <initials>, <user>, <pwd> for your environment.

set -euo pipefail

TENANT="${TENANT:-<tenant>-iflmap.hcisbt.eu1.hana.ondemand.com}"
INITIALS="${INITIALS:-<initials>}"
USER="${USER:-<svc-user>}"
PWD="${PWD:-<svc-pwd>}"

curl -sS -u "${USER}:${PWD}" \
     -H "Accept: application/json" \
     "https://${TENANT}/http/roi/hello/${INITIALS}" \
| jq .

# Expected:
# {
#   "message": "hello from <your-name>",
#   "version": 1
# }
