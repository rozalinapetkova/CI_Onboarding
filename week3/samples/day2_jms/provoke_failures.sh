#!/usr/bin/env bash
# Day 3.2 — provoke Retry-class and Bypass-class failures.
#
# Prerequisites:
#   - Producer + Consumer iFlows deployed.
#   - Consumer has Exception Subprocess + roiam_categorizeError.groovy + Router wired.
#   - Trainer has briefly stopped the downstream stub (for the Retry test) or the
#     stub returns 400 on a malformed body (for the Bypass test).
#
# Usage: same env vars as call_orderhub_async.sh

set -euo pipefail

: "${RUNTIME_URL:?}"
: "${INITIALS:?}"

URL="${RUNTIME_URL}/http/orderhub/orders/${INITIALS}"
TOKEN="$(./obtain_token.sh)"

echo "=== Retry-class failure (transient) ==="
echo "Coordinate with the trainer: the downstream stub should be temporarily"
echo "unreachable (502/503) or returning 504. Then send a valid order:"
echo
curl -s -o /dev/null -w "Producer HTTP %{http_code}\n" \
    -X POST "${URL}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "correlationId: lab-retry-$(date +%s)" \
    -d '{ "orderId": "C-RETRY-001", "customer": "Retry Co", "totalAmount": 100 }'
echo
echo "Expected:"
echo "  - Producer returns 202 (it always does — the queue accepted the message)."
echo "  - Consumer run #1 fails with 5xx -> categorized as Retry -> rethrown."
echo "  - Queue 'roi.orderhub.outbound.${INITIALS}' shows the message with retry counter 1."
echo "  - 60s later, retry counter 2. Then 120s later (exp backoff), retry 3. It keeps"
echo "    retrying indefinitely, by design - this branch was correctly classified as"
echo "    transient, so it's supposed to keep trying."
echo "  - If trainer restores the downstream, the next retry succeeds and the message"
echo "    is removed from the queue."
echo "  - If the trainer never restores it, the message eventually goes 'Blocked' in the"
echo "    same source queue (the adapter's own Dead-Letter Queue checkbox) - an acceptable"
echo "    outcome for a message that was correctly given a chance to recover but didn't."
echo "    This is NOT the real DLQ ('roi.orderhub.dlq.${INITIALS}') - that's only reached"
echo "    by the Bypass path below, for failures known to be permanent from the start."
echo

sleep 2

echo "=== Bypass-class failure (permanent) ==="
echo "Send a deliberately malformed order. Trainer's stub should return 400."
echo
curl -s -o /dev/null -w "Producer HTTP %{http_code}\n" \
    -X POST "${URL}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "correlationId: lab-bypass-$(date +%s)" \
    -d '{ "broken": true }'
echo
echo "Expected:"
echo "  - Producer returns 202 (the body is well-formed JSON, only the schema is wrong)."
echo "  - Consumer run #1 fails: downstream returns 400."
echo "  - roiam_categorizeError sets errorCategory=Bypass (httpCode 400 -> permanent)."
echo "  - Exception subprocess routes the message to roi.orderhub.dlq.${INITIALS}."
echo "  - Exception subprocess ends normally (no rethrow) -> JMS sees success ->"
echo "    message removed from source queue."
echo "  - Result: ONE Failed consumer run + ONE message in the DLQ. NOT three retries."
echo
echo "If you see THREE Failed consumer runs for the Bypass test, the Router's default"
echo "branch is wrong or the categorization script is not setting errorCategory=Bypass."
