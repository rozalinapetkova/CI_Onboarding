#!/usr/bin/env bash
# Day 3.3 — exercise the full chained flow: HTTPS -> Order Hub -> ProcessDirect ->
# Order Translator -> back -> JMS -> Order Hub Consumer -> downstream OAuth2 API.
#
# Producer returns 202 instantly. Three MPL runs appear, linked by correlationId.
#
# Usage:
#   export TOKEN_URL="..."
#   export CLIENT_ID="..."
#   export CLIENT_SECRET="..."
#   export RUNTIME_URL="https://<runtime-host>"
#   export INITIALS="abc"
#   ./call_chained_flow.sh

set -euo pipefail

: "${RUNTIME_URL:?set RUNTIME_URL to the iFlow runtime host (https://...)}"
: "${INITIALS:?set INITIALS to your three-letter initials, lowercase}"

URL="${RUNTIME_URL}/http/orderhub/orders/${INITIALS}"
TOKEN="$(./obtain_token.sh)"

CORR_ID="lab33-$(date +%s)-$$"
ORDER_ID="C-3001"

echo "=== Chained call — expect HTTP 202 from producer ==="
echo "correlationId=${CORR_ID}"
echo "orderId=${ORDER_ID}"
echo

curl -s -o /tmp/orderhub_chained.txt -w "HTTP %{http_code}  (time=%{time_total}s)\n" \
    -X POST "${URL}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "correlationId: ${CORR_ID}" \
    -d "{
        \"orderId\": \"${ORDER_ID}\",
        \"customer\": \"Acme GmbH\",
        \"totalAmount\": 1500,
        \"lines\": [
            { \"sku\": \"S-1\", \"quantity\": 2, \"unitPrice\": 750 }
        ]
    }"

echo
echo "Producer response body:"
cat /tmp/orderhub_chained.txt
echo

cat <<EOF

=========================================================================
Now open Monitor -> Message Processing and filter by correlationId=${CORR_ID}.
You should see THREE runs, all linked by this correlationId:

  1. roi_${INITIALS}_OrderHub
     - Status: Completed
     - Run Steps: HTTPS sender -> Content Modifier -> roiam_logIncoming
                  -> ProcessDirect (sync request-reply) -> JMS receiver -> End
     - Attachments: 'incoming' (the inbound JSON)

  2. roi_${INITIALS}_OrderTranslator
     - Status: Completed
     - Run Steps: ProcessDirect sender -> Router by X-Order-Format
                  -> JSON branch -> canonical XML construction -> End
     - Headers tab: confirm correlationId=${CORR_ID}, orderId=${ORDER_ID},
                    X-Order-Format=json are visible. If any are MISSING,
                    the ProcessDirect allow-list is wrong on one or both
                    adapters. See header_allowlist_reference.md.

  3. roi_${INITIALS}_OrderHubConsumer
     - Status: Completed
     - Run Steps: JMS sender -> roiam_logIncoming -> Request-Reply HTTP
                  -> End
     - Attachments: 'incoming' (canonical XML — different content from #1,
                    SAME script, that's the reuse)
=========================================================================

Failure modes to check for:

  - Only 1 run visible:
      Producer ran but the ProcessDirect call to the translator never landed.
      Check: callee deployed? Address spelling? MEP match (Request-Reply)?

  - 2 runs visible (producer + translator), no consumer:
      JMS queue not being drained. Check consumer iFlow status (Started?
      Concurrent Processes >= 1?) and queue depth in Manage Stores.

  - Translator run has empty correlationId / orderId headers:
      Allow-list misconfigured. Both caller and callee adapters must list
      these headers.

  - 'incoming' attachment missing on either iFlow:
      Script Collection reference not added, OR Script step doesn't point
      to roiam_logIncoming, OR collection not deployed.
EOF
