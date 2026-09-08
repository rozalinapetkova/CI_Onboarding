#!/usr/bin/env bash
# Day 3.4 — exercise the idempotency guard on roi_<initials>_OrderHub.
#
# Sends the same order twice with the same X-Idempotency-Key, then again
# with a fresh key. Expected:
#   call 1 (fresh key)   → 202, orderSequence ORD-NNNN, NR advances, DS writes
#   call 2 (same key)    → 202, IDENTICAL orderSequence, NR does NOT advance,
#                          DS entry unchanged, run is short (no ProcessDirect)
#   call 3 (fresh key)   → 202, orderSequence ORD-NNNN+1
#
# Usage:
#   export TOKEN_URL=... CLIENT_ID=... CLIENT_SECRET=...
#   export RUNTIME_URL=https://<runtime-host>
#   export INITIALS=abc
#   ./call_orderhub_idempotent.sh

set -euo pipefail

: "${RUNTIME_URL:?set RUNTIME_URL}"
: "${INITIALS:?set INITIALS}"

URL="${RUNTIME_URL}/http/orderhub/orders/${INITIALS}"
TOKEN="$(./obtain_token.sh)"

# Reuse the same key for calls 1 and 2; fresh for call 3.
KEY_A="$(uuidgen | tr 'A-Z' 'a-z')"
KEY_B="$(uuidgen | tr 'A-Z' 'a-z')"

CORR_A="lab34-${KEY_A:0:8}-1"
CORR_B="lab34-${KEY_A:0:8}-2"
CORR_C="lab34-${KEY_B:0:8}-3"

ORDER_PAYLOAD='{
    "orderId": "C-3001",
    "customer": "Acme GmbH",
    "totalAmount": 1500,
    "lines": [ { "sku": "S-1", "quantity": 2, "unitPrice": 750 } ]
}'

call() {
    local label="$1" key="$2" corr="$3"
    echo
    echo "=== ${label} ==="
    echo "X-Idempotency-Key: ${key}"
    echo "correlationId:     ${corr}"
    echo "----"
    curl -s -o /tmp/orderhub_idemp.txt -w "HTTP %{http_code}  (time=%{time_total}s)\n" \
        -X POST "${URL}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -H "X-Idempotency-Key: ${key}" \
        -H "correlationId: ${corr}" \
        -d "${ORDER_PAYLOAD}"
    echo "Body:"
    cat /tmp/orderhub_idemp.txt
    echo
}

call "Call 1 — fresh key, expect ORD-NNNN, NR advances" "${KEY_A}" "${CORR_A}"
call "Call 2 — same key as call 1, expect IDENTICAL ORD-NNNN, NR does NOT advance" "${KEY_A}" "${CORR_B}"
call "Call 3 — fresh key, expect ORD-NNNN+1" "${KEY_B}" "${CORR_C}"

cat <<EOF

=========================================================================
Verification steps (Monitor → Manage Stores):

  Number Ranges → nr_${INITIALS}_OrderSequence
      Current value should have advanced by exactly 2 (calls 1 and 3),
      NOT 3. Call 2 was a cache hit and must not have burned a sequence.

  Data Stores → ds_${INITIALS}_OrderIdempotency → Entries
      Two entries: one keyed ${KEY_A:0:8}... and one keyed ${KEY_B:0:8}...
      Click into the first — payload should match call 1's response body.

  Monitor → Message Processing (filter by correlationId):
      ${CORR_A}: full path (HTTPS → ... → ProcessDirect → ... → JMS → End)
      ${CORR_B}: short path (HTTPS → roiam_logIncoming → Data Store Get →
                  Router true-branch → End). No ProcessDirect run linked.
      ${CORR_C}: full path again.

Failure modes:

  Call 2 returns a DIFFERENT orderSequence:
      Idempotency guard not wired. Check:
        - Data Store Get's Entry ID is ${"$"}{header.X-Idempotency-Key}
        - "Throw Exception on Failure" is unchecked
        - Router branches on the property the Get step actually sets
          (verify in the MPL Run Steps view)

  Call 2 returns the SAME orderSequence but the MPL shows it still hit
  ProcessDirect:
      Router placed AFTER ProcessDirect instead of after Get. Fix order.

  Call 2 returns HTTP 500:
      "Throw Exception on Failure" is checked → cache miss is firing
      Exception Subprocess. Uncheck it.

  Call 3 returns ORD-NNNN+2 instead of NNNN+1:
      Some other lab session pulled a sequence between your calls 1 and 3.
      Expected on the shared tenant. Not a bug.
=========================================================================
EOF
