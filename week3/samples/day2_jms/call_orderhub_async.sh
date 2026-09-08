#!/usr/bin/env bash
# Day 3.2 — exercise the JMS-decoupled Order Hub producer.
#
# Producer returns HTTP 202 as soon as the canonical XML is on the queue.
# The consumer iFlow drains the queue asynchronously — check Monitor afterwards.
#
# Usage:
#   export TOKEN_URL="https://<subdomain>.authentication.eu10.hana.ondemand.com/oauth/token"
#   export CLIENT_ID="..."
#   export CLIENT_SECRET="..."
#   export RUNTIME_URL="https://<runtime-host>"
#   export INITIALS="abc"
#   ./call_orderhub_async.sh

set -euo pipefail

: "${RUNTIME_URL:?set RUNTIME_URL to the iFlow runtime host (https://...)}"
: "${INITIALS:?set INITIALS to your three-letter initials, lowercase}"

URL="${RUNTIME_URL}/http/orderhub/orders/${INITIALS}"
TOKEN="$(./obtain_token.sh)"

CORR_ID="lab-$(date +%s)-$$"

echo "=== Producer call — expect HTTP 202 Accepted ==="
curl -s -o /tmp/orderhub_async.txt -w "HTTP %{http_code}  (time=%{time_total}s)\n" \
    -X POST "${URL}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "correlationId: ${CORR_ID}" \
    -d '{ "orderId": "C-3001", "customer": "Acme GmbH", "totalAmount": 1500 }'

echo "Producer response body:"
cat /tmp/orderhub_async.txt
echo

echo "correlationId=${CORR_ID}"
echo
echo "Now open Monitor -> Message Processing and filter by:"
echo "  correlationId = ${CORR_ID}"
echo "You should see TWO runs:"
echo "  1. Producer  roi_${INITIALS}_OrderHub          (Completed within ~200ms of this call)"
echo "  2. Consumer  roi_${INITIALS}_OrderHubConsumer  (Completed ~1-3s later, drained from JMS)"
echo
echo "If you only see the producer run, check:"
echo "  Monitor -> Message Queues -> roi.orderhub.outbound.${INITIALS}"
echo "Queue depth > 0 means the consumer iFlow is not deployed or its JMS sender adapter is misconfigured."
