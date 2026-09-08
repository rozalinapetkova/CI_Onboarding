#!/usr/bin/env bash
# Day 3.1 — exercise the OAuth2-secured Order Hub sender.
#
# Usage:
#   export TOKEN_URL="https://<subdomain>.authentication.eu10.hana.ondemand.com/oauth/token"
#   export CLIENT_ID="..."
#   export CLIENT_SECRET="..."
#   export RUNTIME_URL="https://<runtime-host>"
#   export INITIALS="abc"
#   ./call_iflow.sh

set -euo pipefail

: "${RUNTIME_URL:?set RUNTIME_URL to the iFlow runtime host (https://...)}"
: "${INITIALS:?set INITIALS to your three-letter initials, lowercase}"

URL="${RUNTIME_URL}/http/orderhub/orders/${INITIALS}"
TOKEN="$(./obtain_token.sh)"

echo "=== 1) Happy path: valid bearer token ==="
curl -s -o /tmp/orderhub_ok.txt -w "HTTP %{http_code}\n" \
    -X POST "${URL}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{ "orderId": "C-3001", "customer": "Acme GmbH", "totalAmount": 1500 }'
echo "Body:"
cat /tmp/orderhub_ok.txt
echo

echo "=== 2) Failure: no Authorization header (expect 401) ==="
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
    -X POST "${URL}" \
    -H "Content-Type: application/json" \
    -d '{ "orderId": "C-3001" }'

echo
echo "=== 3) Failure: garbage token (expect 401) ==="
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
    -X POST "${URL}" \
    -H "Authorization: Bearer not-a-real-token" \
    -H "Content-Type: application/json" \
    -d '{ "orderId": "C-3001" }'

echo
echo "Note: 401 responses do NOT show up in Monitor -> Message Processing."
echo "The XSUAA layer rejects the call before the iFlow runtime sees it."
