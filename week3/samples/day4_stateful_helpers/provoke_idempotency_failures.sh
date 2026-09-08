#!/usr/bin/env bash
# Day 3.4 — provoke each of the documented idempotency / Number Range
# failure modes. None of these scripts MAKE the failure — they trigger it
# once the iFlow has been misconfigured per the "Misconfigure" step below.
# Use them as confirmation that the misconfig produced the predicted symptom.
#
# Usage:
#   export RUNTIME_URL=https://<runtime-host>
#   export INITIALS=abc
#   ./provoke_idempotency_failures.sh missing-key
#   ./provoke_idempotency_failures.sh exchange-id-key
#   ./provoke_idempotency_failures.sh ttl-zero
#   ./provoke_idempotency_failures.sh rotate-yes
#   ./provoke_idempotency_failures.sh cache-before-work
#   ./provoke_idempotency_failures.sh nr-reset

set -euo pipefail

: "${RUNTIME_URL:?set RUNTIME_URL}"
: "${INITIALS:?set INITIALS}"

URL="${RUNTIME_URL}/http/orderhub/orders/${INITIALS}"
TOKEN="$(./obtain_token.sh)"

ORDER_PAYLOAD='{ "orderId": "C-3001", "customer": "Acme GmbH",
                 "totalAmount": 1500,
                 "lines": [ { "sku": "S-1", "quantity": 2, "unitPrice": 750 } ] }'

case "${1:-}" in
    missing-key)
        cat <<MSG
Misconfigure: nothing — the iFlow should already reject calls without
              X-Idempotency-Key via roiam_requireIdempotencyKey.

Expected: HTTP 400 with body {"error":"X-Idempotency-Key header required",...}
MSG
        curl -s -o /tmp/idemp_fail.txt -w "HTTP %{http_code}\n" \
            -X POST "${URL}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${ORDER_PAYLOAD}"
        echo "Body:"; cat /tmp/idemp_fail.txt; echo
        ;;

    exchange-id-key)
        cat <<MSG
Misconfigure: change Data Store Get's Entry ID to \${exchangeId} (instead of
              \${header.X-Idempotency-Key}). Redeploy.

Expected: Every call is a cache miss. Number Range advances every call.
          Data Store fills with entries that will never be hit again.
          The two calls below will return DIFFERENT orderSequence values
          even though X-Idempotency-Key is identical.
MSG
        KEY="$(uuidgen)"
        for n in 1 2; do
            echo "--- Call ${n} (key=${KEY}) ---"
            curl -s -o /tmp/idemp_fail.txt -w "HTTP %{http_code}\n" \
                -X POST "${URL}" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -H "X-Idempotency-Key: ${KEY}" \
                -d "${ORDER_PAYLOAD}"
            cat /tmp/idemp_fail.txt; echo; echo
        done
        ;;

    ttl-zero)
        cat <<MSG
Misconfigure: set Data Store Write's Expiration Period to 0 (or blank). Deploy.

Expected: Entries never expire. Run this 10 times with fresh keys, then check
          Monitor → Manage Stores → Data Stores → ds_${INITIALS}_OrderIdempotency.
          Entries column will not have an Expires At value.

          Lesson: this is how the tenant Data Store quota fills up over weeks.
MSG
        for n in 1 2 3 4 5 6 7 8 9 10; do
            KEY="$(uuidgen)"
            curl -s -o /dev/null -w "Call ${n} (key=${KEY:0:8}): HTTP %{http_code}\n" \
                -X POST "${URL}" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -H "X-Idempotency-Key: ${KEY}" \
                -d "${ORDER_PAYLOAD}"
        done
        echo
        echo "Now check Manage Stores. Expect 10 entries with no expiration."
        ;;

    rotate-yes)
        cat <<MSG
Misconfigure: edit nr_${INITIALS}_OrderSequence:
              Max = 5
              Rotate = Yes
              Reset Current value to 1
              Save.

Expected: Calls 1–5 return ORD-0001..ORD-0005.
          Call 6 wraps to ORD-0001 — DUPLICATE business reference.

          Lesson: never Rotate=Yes for business references.
MSG
        for n in 1 2 3 4 5 6; do
            KEY="$(uuidgen)"
            echo "--- Call ${n} ---"
            curl -s -o /tmp/idemp_fail.txt -w "HTTP %{http_code}\n" \
                -X POST "${URL}" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -H "X-Idempotency-Key: ${KEY}" \
                -d "${ORDER_PAYLOAD}"
            cat /tmp/idemp_fail.txt; echo; echo
        done
        ;;

    cache-before-work)
        cat <<MSG
Misconfigure: move the Data Store Write step from AFTER ProcessDirect to
              BEFORE the Number Range step. Then stop the Translator iFlow
              (so ProcessDirect will fail).

Expected: Call 1 throws (translator stopped) → Exception Subprocess.
          But the Data Store now contains an entry under this key.
          Restart the translator. Send call 2 with the SAME key.
          Response is HTTP 202 with the cached envelope — but the order
          was never actually translated/enqueued.

          Lesson: cache AFTER success, not before.
MSG
        KEY="$(uuidgen)"
        for n in 1 2; do
            echo "--- Call ${n} (key=${KEY}) ---"
            echo "  (between calls: restart the translator iFlow)"
            curl -s -o /tmp/idemp_fail.txt -w "HTTP %{http_code}\n" \
                -X POST "${URL}" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -H "X-Idempotency-Key: ${KEY}" \
                -d "${ORDER_PAYLOAD}"
            cat /tmp/idemp_fail.txt; echo
            if [ "$n" = "1" ]; then
                echo "Press Enter after restarting the translator and pausing 10 seconds..."
                read -r _
            fi
            echo
        done
        ;;

    nr-reset)
        cat <<MSG
Misconfigure: between the two calls below, manually reset
              nr_${INITIALS}_OrderSequence's current value back to 1 via
              Monitor → Manage Stores → Number Ranges → Edit Current Value.

Expected: Call 1 gets sequence ORD-NNNN.
          You reset.
          Call 2 gets sequence ORD-0001 — duplicate of a previous order's
          sequence if NNNN > 1.

          Lesson: don't reset Number Ranges in any environment carrying
          real or test data you care about. Definitely not in production.
MSG
        for n in 1 2; do
            KEY="$(uuidgen)"
            echo "--- Call ${n} (key=${KEY:0:8}) ---"
            curl -s -o /tmp/idemp_fail.txt -w "HTTP %{http_code}\n" \
                -X POST "${URL}" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -H "X-Idempotency-Key: ${KEY}" \
                -d "${ORDER_PAYLOAD}"
            cat /tmp/idemp_fail.txt; echo
            if [ "$n" = "1" ]; then
                echo "Now reset the Number Range to 1 in the cockpit. Press Enter when done."
                read -r _
            fi
            echo
        done
        ;;

    *)
        cat <<USAGE
Usage: $0 {missing-key|exchange-id-key|ttl-zero|rotate-yes|cache-before-work|nr-reset}

Each subcommand documents the misconfiguration you must apply to the iFlow
or to the Number Range artifact, then triggers the calls that demonstrate
the resulting failure. Restore the canonical config after each experiment.
USAGE
        exit 2
        ;;
esac
