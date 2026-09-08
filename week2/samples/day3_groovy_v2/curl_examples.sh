#!/usr/bin/env bash
# Day 2.3 — Order Translator curl examples
# Fill in the env vars, then run the three POSTs below.

: "${TENANT:?set TENANT to your CPI runtime host, e.g. my-tenant.it-cpi020.cfapps.eu20.hana.ondemand.com}"
: "${INITIALS:?set INITIALS to your three-letter initials, lowercase}"
: "${USER:?set USER}"
: "${PWD:?set PWD}"

URL="https://${TENANT}/http/roi/orderhub/${INITIALS}"

echo "=== XML branch (Message Mapping) ==="
curl -u "${USER}:${PWD}" -X POST "${URL}" \
     -H "X-Order-Format: xml" \
     -H "Content-Type: application/xml" \
     --data-binary @../day1_message_mapping/vendor_order_sample.xml \
     -w "\nHTTP %{http_code}\n"

echo
echo "=== JSON branch (Groovy script) ==="
curl -u "${USER}:${PWD}" -X POST "${URL}" \
     -H "X-Order-Format: json" \
     -H "Content-Type: application/json" \
     -d @order_sample.json \
     -w "\nHTTP %{http_code}\n"

echo
echo "=== CSV branch (Groovy script + required headers) ==="
curl -u "${USER}:${PWD}" -X POST "${URL}" \
     -H "X-Order-Format: csv" \
     -H "X-Order-Id: C-3001" \
     -H "X-Customer: 50001" \
     -H "X-Currency: usd" \
     -H "Content-Type: text/csv" \
     --data-binary @order_sample.csv \
     -w "\nHTTP %{http_code}\n"

echo
echo "=== CSV without required headers (expect 500) ==="
curl -u "${USER}:${PWD}" -X POST "${URL}" \
     -H "X-Order-Format: csv" \
     -H "Content-Type: text/csv" \
     --data-binary @order_sample.csv \
     -w "\nHTTP %{http_code}\n"
