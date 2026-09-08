#!/usr/bin/env bash
# Happy path — country "DE" exists in restcountries.

set -euo pipefail
TENANT="${TENANT:-<tenant>-iflmap.hcisbt.eu1.hana.ondemand.com}"
INITIALS="${INITIALS:-<initials>}"
USER="${USER:-<svc-user>}"
PWD="${PWD:-<svc-pwd>}"

curl -sS -u "${USER}:${PWD}" \
     -X POST "https://${TENANT}/http/customer/${INITIALS}/echo" \
     -H "Content-Type: application/json" \
     -H "customerCountry: DE" \
     -d @"$(dirname "$0")/request_payload.json" \
| jq .

# Expected: see final_response.json — country block populated, lookupStatus "ok".
