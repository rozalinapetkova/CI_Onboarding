#!/usr/bin/env bash
# Failure injection — country "ZZ" returns 404 from restcountries.
# Behavior depends on the "Throw Exception on Failure" setting on the HTTP receiver:
#   - on  → iFlow throws, MPL goes FAILED, client gets 500
#   - off → script sees null body, sets lookupStatus="not_found", client gets 200

set -euo pipefail
TENANT="${TENANT:-<tenant>-iflmap.hcisbt.eu1.hana.ondemand.com}"
INITIALS="${INITIALS:-<initials>}"
USER="${USER:-<svc-user>}"
PWD="${PWD:-<svc-pwd>}"

curl -sS -u "${USER}:${PWD}" \
     -X POST "https://${TENANT}/http/customer/${INITIALS}/echo" \
     -H "Content-Type: application/json" \
     -H "customerCountry: ZZ" \
     --data-raw '{"customerId":"C-1099","name":"Nowhereland Ltd","country":"ZZ"}' \
| jq .
