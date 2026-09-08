#!/usr/bin/env bash
# Day 2.4 — body signer test harness
# Run against your test iFlow after deploying roiam_bodySigner.groovy.

: "${TENANT:?set TENANT to your CPI runtime host}"
: "${INITIALS:?set INITIALS to your three-letter initials, lowercase}"
: "${USER:?set USER}"
: "${PWD:?set PWD}"

URL="https://${TENANT}/http/roi/sign/${INITIALS}"

echo "=== Happy path: 'hello world' signed with secret 'shh' ==="
RESPONSE_HEADERS=$(curl -s -u "${USER}:${PWD}" -X POST "${URL}" \
     -H "X-Signing-Secret: shh" \
     -H "Content-Type: text/plain" \
     --data "hello world" \
     -D - -o /dev/null)
echo "${RESPONSE_HEADERS}"

ACTUAL=$(echo "${RESPONSE_HEADERS}" | grep -i '^X-Body-Signature:' | awk '{print $2}' | tr -d '\r')
EXPECTED=$(printf '%s' "hello worldshh" | sha256sum | awk '{print $1}')

echo
echo "Expected: ${EXPECTED}"
echo "Actual:   ${ACTUAL}"
if [ "${ACTUAL}" = "${EXPECTED}" ]; then
    echo "OK"
else
    echo "MISMATCH"
fi

echo
echo "=== Failure case: missing X-Signing-Secret (expect HTTP 500) ==="
curl -u "${USER}:${PWD}" -X POST "${URL}" \
     -H "Content-Type: text/plain" \
     --data "hello world" \
     -w "\nHTTP %{http_code}\n"

echo
echo "Now open Monitor → Message Processing → Failed and confirm the"
echo "RuntimeException carries the message 'Missing required header X-Signing-Secret'."
