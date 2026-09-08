#!/usr/bin/env bash
# Day 3.1 — fetch a client_credentials access token from XSUAA.
# Outputs the token only (consumes the JSON; needs `jq`).
#
# Usage:
#   export TOKEN_URL="https://<subdomain>.authentication.eu10.hana.ondemand.com/oauth/token"
#   export CLIENT_ID="sb-orderhub-inbound!t12345"
#   export CLIENT_SECRET="(redacted)"
#   ./obtain_token.sh

set -euo pipefail

: "${TOKEN_URL:?set TOKEN_URL to the XSUAA token endpoint}"
: "${CLIENT_ID:?set CLIENT_ID}"
: "${CLIENT_SECRET:?set CLIENT_SECRET}"

RESPONSE=$(curl -s -X POST "${TOKEN_URL}" \
    -u "${CLIENT_ID}:${CLIENT_SECRET}" \
    -d "grant_type=client_credentials")

if command -v jq >/dev/null 2>&1; then
    echo "${RESPONSE}" | jq -r '.access_token'
else
    # Fallback when jq is not installed — fragile but workable for the lab.
    echo "${RESPONSE}" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
fi
