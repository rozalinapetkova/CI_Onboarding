#!/usr/bin/env bash
# Day 4.1 — provoke each of the 8 MPL statuses on the Order Hub.
#
# Run subcommands individually; each documents the prerequisite state
# (deployed / undeployed) and the expected MPL status.
#
# Usage:
#   export RUNTIME_URL=https://<runtime-host>
#   export INITIALS=abc
#   ./provoke_8_statuses.sh completed
#   ./provoke_8_statuses.sh processing
#   ./provoke_8_statuses.sh failed
#   ./provoke_8_statuses.sh retry
#   ./provoke_8_statuses.sh escalated
#   ./provoke_8_statuses.sh pending
#   ./provoke_8_statuses.sh discarded
#   ./provoke_8_statuses.sh abandoned

set -euo pipefail

: "${RUNTIME_URL:?set RUNTIME_URL}"
: "${INITIALS:?set INITIALS}"

URL="${RUNTIME_URL}/http/orderhub/orders/${INITIALS}"
TOKEN="$(./obtain_token.sh)"

ORDER_PAYLOAD='{ "orderId": "C-3001", "customer": "Acme GmbH",
                 "totalAmount": 1500,
                 "lines": [ { "sku": "S-1", "quantity": 2, "unitPrice": 750 } ] }'

case "${1:-}" in
    completed)
        cat <<MSG
Prerequisite: Order Hub + Consumer + Translator all deployed and Started.
              All receiver targets (OAuth backend) reachable.

Expected MPL status: Completed
              All four message log attachments present.
MSG
        KEY="$(uuidgen)"
        curl -s -o /tmp/mpl_status.txt -w "HTTP %{http_code}\n" \
            -X POST "${URL}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -H "X-Idempotency-Key: ${KEY}" \
            -d "${ORDER_PAYLOAD}"
        cat /tmp/mpl_status.txt; echo
        echo "Open Monitor → Message Processing → filter Status=Completed."
        ;;

    processing)
        cat <<MSG
Prerequisite: Temporarily edit a script step (e.g. roiam_logIncoming) to add:
              sleep(20000) { interrupted -> /* swallow */ }
              Redeploy. Send the call below. Refresh the Monitor IMMEDIATELY.
              Remove the sleep and redeploy after observing.

Expected MPL status: Processing (visible for ~20 seconds)
MSG
        KEY="$(uuidgen)"
        curl -s -o /tmp/mpl_status.txt -w "HTTP %{http_code} time=%{time_total}s\n" \
            -X POST "${URL}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -H "X-Idempotency-Key: ${KEY}" \
            -d "${ORDER_PAYLOAD}" &
        BG_PID=$!
        echo "Curl PID=${BG_PID}. Open Monitor NOW and look for Processing status."
        wait "${BG_PID}" || true
        cat /tmp/mpl_status.txt; echo
        ;;

    failed)
        cat <<MSG
Prerequisite: Order Hub deployed. NO Exception Subprocess wired yet
              (Day 4.4 wires that — for now, send malformed JSON to
              the parser-bearing step).

Expected MPL status: Failed
              Error Information tab shows JsonParseException.
MSG
        KEY="$(uuidgen)"
        curl -s -o /tmp/mpl_status.txt -w "HTTP %{http_code}\n" \
            -X POST "${URL}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -H "X-Idempotency-Key: ${KEY}" \
            -d '{ "orderId": "C-3001", "broken'
        cat /tmp/mpl_status.txt; echo
        ;;

    retry)
        cat <<MSG
Prerequisite: Undeploy the OAuth2 receiver target — typically the downstream
              order API. The JMS Consumer iFlow tries to call it, raises, and
              enters its retry policy (3 attempts, 30s backoff configured
              earlier in the week).

              IMPORTANT: this provokes a queue-side Retry, visible on the
              CONSUMER iFlow's MPL, not the Producer's.

Expected MPL status: Retry (Consumer side)
              Watch over ~90 seconds as attempts 1/2/3 are visible.
MSG
        KEY="$(uuidgen)"
        curl -s -o /tmp/mpl_status.txt -w "HTTP %{http_code}\n" \
            -X POST "${URL}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -H "X-Idempotency-Key: ${KEY}" \
            -d "${ORDER_PAYLOAD}"
        cat /tmp/mpl_status.txt; echo
        echo "Now watch Monitor → Message Processing → filter Status=Retry on the Consumer iFlow."
        ;;

    escalated)
        cat <<MSG
Prerequisite: Same as Retry — receiver target undeployed. Let the 3 retry
              attempts exhaust. The Consumer's JMS retry policy moves the
              message to DLQ (roi.${INITIALS}.orderhub.dlq).

Expected MPL status: Escalated (Consumer side)
              DLQ queue depth +1 in Monitor → Messages → Queues.
MSG
        KEY="$(uuidgen)"
        curl -s -o /tmp/mpl_status.txt -w "HTTP %{http_code}\n" \
            -X POST "${URL}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -H "X-Idempotency-Key: ${KEY}" \
            -d "${ORDER_PAYLOAD}"
        cat /tmp/mpl_status.txt; echo
        echo "Wait ~120 seconds for retries to exhaust, then check Monitor."
        echo "Filter Status=Escalated on the Consumer iFlow."
        ;;

    pending)
        cat <<MSG
Prerequisite: Undeploy the JMS Consumer iFlow entirely. Producer is still
              up and can enqueue messages; nobody is consuming.

Expected MPL status: Producer side: Completed. Queue side: messages Pending.
              Visible in Monitor → Messages → Queues, queue depth grows.
MSG
        KEY="$(uuidgen)"
        curl -s -o /tmp/mpl_status.txt -w "HTTP %{http_code}\n" \
            -X POST "${URL}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -H "X-Idempotency-Key: ${KEY}" \
            -d "${ORDER_PAYLOAD}"
        cat /tmp/mpl_status.txt; echo
        echo "Check Monitor → Messages → Queues → roi.${INITIALS}.orderhub.in"
        echo "Depth should now be +1."
        ;;

    discarded)
        cat <<MSG
Prerequisite: Everything deployed and happy. Idempotency Data Store wired
              (from Day 3.4).

Expected MPL status: Discarded
              Second call returns the cached response envelope; the MPL run
              is short (no ProcessDirect, no JMS) and marked Discarded.
MSG
        KEY="$(uuidgen)"
        echo "--- Call 1 (fresh key) ---"
        curl -s -o /tmp/mpl_status.txt -w "HTTP %{http_code}\n" \
            -X POST "${URL}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -H "X-Idempotency-Key: ${KEY}" \
            -d "${ORDER_PAYLOAD}"
        cat /tmp/mpl_status.txt; echo; echo

        echo "--- Call 2 (same key, expect Discarded) ---"
        curl -s -o /tmp/mpl_status.txt -w "HTTP %{http_code}\n" \
            -X POST "${URL}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -H "X-Idempotency-Key: ${KEY}" \
            -d "${ORDER_PAYLOAD}"
        cat /tmp/mpl_status.txt; echo
        echo "Open Monitor → Message Processing — second run has status Discarded."
        ;;

    abandoned)
        cat <<MSG
Prerequisite: Trainer-only. The trainer restarts the tenant worker
              mid-run for one cohort message.

Expected MPL status: Abandoned
              Should be rare. Do not provoke this on your own — restarting
              the tenant worker affects every other trainee's iFlows.

This subcommand is a no-op; trainer will demonstrate live.
MSG
        ;;

    *)
        cat <<USAGE
Usage: $0 {completed|processing|failed|retry|escalated|pending|discarded|abandoned}

After running each subcommand:
- Open Monitor → Message Processing
- Filter by the expected status
- Confirm one run is present matching the just-executed call

After Retry / Escalated / Pending, re-deploy the iFlows you undeployed so
the rest of the lab continues to work:
  - JMS Consumer iFlow
  - OAuth2 receiver target

Restore canonical configuration before continuing to Day 4.2.
USAGE
        exit 2
        ;;
esac
