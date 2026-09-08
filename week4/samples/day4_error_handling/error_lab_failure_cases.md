# Error handling lab — failure cases to provoke

Walk through these in order. Each case provokes one classification and confirms the subprocess handles it correctly. By the end you'll have seen the full taxonomy fire and the DLQ accumulate envelopes you can inspect.

## Setup checklist before starting

| Check | How |
|---|---|
| Order Hub iFlow deployed | Tenant cockpit → Monitoring → Manage Integration Content → search "orderhub" → status Started |
| Exception Subprocess wired | Open iFlow XML, verify second pool present with Error Start Event |
| Capture-context script uploaded | Script step opens, file `roiam_captureErrorContext.groovy` visible |
| DLQ queue exists | Event Mesh / JMS broker cockpit → queue `roi.orderhub.dlq` exists |
| ANS endpoint configured | Receiver `ans_endpoint` resolves; test ping succeeds |
| Sample payloads on hand | `sample_cloudevents_payload.json` and `sample_dlq_envelope.json` open |
| MPL filter ready | Monitoring → Message Processing → filter by `correlationId` prefix `lab-` |

## Case 1 — Poison (malformed JSON)

**Goal**: produce a poison-classified DLQ envelope.

### Provocation

POST to the HTTP entry path with deliberately broken JSON:

```bash
curl -X POST https://<tenant>/http/orders \
  -H "Content-Type: application/json" \
  -H "correlationId: lab-poison-001" \
  -d '{"orderId": "test-001", "amount": -x99, "items": [}'
```

Note `-x99` (invalid number) and the unclosed `[` array.

### Expected

| Where | What to see |
|---|---|
| MPL | Run status Failed; correlationId `lab-poison-001` |
| MPL custom properties | `errorClassification = poison`, `errorClass = groovy.json.JsonException` |
| MPL attachments | `error-context`, `failed-payload` |
| DLQ `roi.orderhub.dlq` | New envelope; `classification: "poison"`; `originalBody` contains the broken JSON verbatim |
| ANS | Event `roi.orderhub.dlq` severity ERROR fired |
| Adapter retries | Did NOT retry (poison should fail-fast; check `redeliveryCounter` = 0) |

### What to investigate if it fails

- If `errorClassification` = `unknown`: the heuristic doesn't recognize the exception class; check what `errorClass` actually was and add to `classify()`
- If DLQ envelope is missing: JMS DLQ branch isn't wired or the DLQ queue doesn't exist
- If retries did happen: JSON parse error isn't supposed to be retryable — check that the parser step throws a recognizable exception class

## Case 2 — Transient (downstream unreachable)

**Goal**: produce a transient-classified failure that eventually exhausts adapter retries and ends in DLQ.

### Provocation

Reconfigure the OMS endpoint URL to point to a non-existent host *just before* sending a valid order:

1. Externalized parameter `OMSEndpointBase` = `http://does-not-exist.invalid`
2. Save iFlow config and redeploy
3. POST a valid order:

```bash
curl -X POST https://<tenant>/http/orders \
  -H "Content-Type: application/json" \
  -H "correlationId: lab-transient-001" \
  -d '{"orderId": "test-002", "amount": 100.00, "items": [{"sku":"SKU-A","qty":1}]}'
```

4. Watch MPL for the next 30 minutes — you'll see the message re-attempted per the backoff schedule until Maximum Redelivery exhausts.

### Expected

| Where | What to see |
|---|---|
| MPL | First attempt Failed; redelivered N times; final attempt status Escalated |
| `CamelRedeliveryCounter` | Increases 0, 1, 2, 3, 4, then subprocess fires at 5 |
| DLQ envelope `classification` | `"transient"`; `redeliveryCounter` = 5 |
| ANS | Event `roi.orderhub.retry-stuck` (NOT `dlq`) severity WARNING |
| Time elapsed | ~30 minutes from first attempt to DLQ |

### What to investigate if it fails

- If retries don't happen: Maximum Redelivery is 0 or Auto-Ack mode is set; check adapter config
- If classification is `unknown`: ConnectException class name didn't match the heuristic; verify exact class in `errorClass`
- If subprocess fires too early (counter < 5): the broker is somehow ACK'ing prematurely — verify Client Ack mode

### Cleanup

Restore `OMSEndpointBase` to the real value and redeploy. Replay the DLQ entry to confirm idempotency works.

## Case 3 — Configuration (PD parameter missing)

**Goal**: produce a configuration-classified failure with Sev-1 alert.

### Provocation

Delete the PD parameter the event path depends on:

1. Cockpit → Partner Directory → search `ROI_ORDERHUB_ROUTING` → delete the parameter `default` (or rename it)
2. Publish a CloudEvent via the trainer's helper iFlow OR send a synthetic AMQP message:

```
ce-id:            lab-config-001
ce-source:        /sap/s4hanacloud/dev01
ce-specversion:   1.0
ce-type:          sap.s4.beh.salesorder.v1.SalesOrder.Created.v1
ce-subject:       0009999001
ce-time:          <now>
ce-datacontenttype: application/json

Body: { "orderId": "test-003", "amount": 50, "items": [...] }
```

### Expected

| Where | What to see |
|---|---|
| MPL | Run failed at `roiam_resolveRoutingFromPd` step |
| `errorMessage` | "Routing parameter not found for partnerId..." |
| `errorClassification` | `configuration` |
| DLQ envelope | `classification: "configuration"`; `failedRouteId` points at the PD-resolve script step |
| ANS | Event `roi.orderhub.dlq` severity ERROR; should page oncall (in lab: shows in Slack/email rather than pager) |
| Adapter retries | Happened (transient-looking from broker side) but always failed identically |

### What to investigate if it fails

- If classification is `transient`: the `classify()` heuristic isn't picking up the "parameter not found" message; check the actual exception message and tune the heuristic
- If alert didn't fire: ANS receiver step error or alert category not configured

### Cleanup

Restore the PD parameter from `pd_routing_parameter.json` (Day 4.3 sample).

## Case 4 — Business (credit hold rejection)

**Goal**: produce a business rejection that does NOT alert and does NOT go to the DLQ.

### Provocation

Send an order whose downstream OMS (or the trainer's stub) will reject with HTTP 422 + body "Customer is on credit hold":

```bash
curl -X POST https://<tenant>/http/orders \
  -H "Content-Type: application/json" \
  -H "correlationId: lab-business-001" \
  -d '{"orderId": "test-004", "amount": 100, "customer": {"id": "CREDIT-HOLD-CUSTOMER"}, "items": [{"sku":"SKU-A","qty":1}]}'
```

(The trainer's stub OMS is configured to return 422 + "credit hold" for the magic customer id.)

### Expected

| Where | What to see |
|---|---|
| MPL | Failed at downstream step; `errorMessage` contains "credit hold" |
| `errorClassification` | `business` |
| DLQ `roi.orderhub.dlq` | NOTHING (business doesn't go to DLQ) |
| Reject queue `roi.orderhub.reject` | New envelope with `classification: "business"` |
| ANS | NO alert fired (business is INFO-level, log-only) |

### What to investigate if it fails

- If classification is `poison`: the heuristic doesn't see "credit hold" in the message; check exact downstream response body
- If it goes to DLQ: routing in subprocess sends business to wrong destination; verify router branch
- If an alert fires: the alert builder is firing on all classifications; should skip business

### Why this case matters

This is the test that most cohorts get wrong on first try. Business rejections often get mistaken for poison ("the downstream rejected the message — that's an error, right?"). It's not an error from the iFlow's perspective — the iFlow did its job correctly; the *content* is what the downstream rejected. Treating it as poison generates Sev-2 alerts every time a customer fails a credit check, which is exactly the alert fatigue the classification taxonomy exists to prevent.

## Case 5 — Burst (poison flood)

**Goal**: trigger the burst-detection layer that converts N individual DLQ alerts into one `roi.orderhub.poison-burst`.

### Provocation

Send 60 malformed messages in 10 minutes:

```bash
for i in {001..060}; do
  curl -X POST https://<tenant>/http/orders \
    -H "Content-Type: application/json" \
    -H "correlationId: lab-burst-$i" \
    -d "{\"orderId\": \"burst-$i\", \"amount\": -x, \"items\": []}"
  sleep 10
done
```

### Expected

| Where | What to see |
|---|---|
| DLQ depth | 60 envelopes accumulated |
| ANS events | First few `roi.orderhub.dlq` fired individually; then deduplication suppression kicks in; one `roi.orderhub.poison-burst` event fires |
| Slack/email | One summary alert, not 60 |

### What to investigate if it fails

- If 60 individual alerts fire: ANS deduplication rule or burst-detection rule not configured (check `alert_categories_reference.md`)
- If no alert fires at all: the rate threshold for burst is higher than what your provocation produces; tune down for the lab

## Case 6 — Runtime (synthetic OOM, optional)

**Goal**: see a runtime classification fire. Hardest to provoke in a small lab.

### Provocation

Send an unreasonably large body:

```bash
python -c "import json; print(json.dumps({'orderId':'big','items':[{'sku':'X','qty':1,'data':'x'*1000000}]*100}))" \
  | curl -X POST https://<tenant>/http/orders \
      -H "Content-Type: application/json" \
      -H "correlationId: lab-runtime-001" \
      --data-binary @-
```

100 MB-ish body. Will hit either the iFlow timeout, JVM heap, or a CI request-size limit.

### Expected (variable)

- If it hits JVM heap: `errorClass = java.lang.OutOfMemoryError`; classification = `runtime`
- If it hits timeout: `errorClass = ...TimeoutException`; classification may be `transient` (incorrectly) or `runtime`
- If it hits request-size limit: HTTP 413 from the entry adapter; no subprocess fire (rejected before iFlow runs)

### What to investigate

- If classification is `transient`: timeout exceptions can be misclassified; consider routing timeouts to `runtime` instead since they often indicate capacity issues
- If nothing fires: request was rejected at adapter level, before iFlow logic

### Skip this case if your training tenant is small

OOM is rarely reproducible cleanly in cohort training. The case is documented for completeness; don't burn an afternoon on it if it doesn't fire on first try.

## Post-lab check

After running cases 1–5 you should have:

| Queue | Approx. count |
|---|---|
| `roi.orderhub.dlq` | 1 (case 1) + 1 (case 2) + 1 (case 3) + 60 (case 5) = 63 envelopes |
| `roi.orderhub.reject` | 1 (case 4) |
| `roi.orderhub.retry` | 0 (cases that should have used retry queue were forced to DLQ in lab for visibility) |

Inspect the envelopes by reading messages from the DLQ in the broker cockpit. Compare to `sample_dlq_envelope.json`. Verify field-by-field — `classification`, `correlationId`, `originalBody`, `originalHeaders`.

## Cleanup

```
1. Drain or purge all four queues
2. Restore PD parameter from sample
3. Restore externalized OMSEndpointBase
4. Redeploy iFlow
5. Send one valid order, confirm Completed status
```

## What this lab is teaching beyond the mechanics

By the time you finish:
- You've seen what each classification looks like at runtime
- You've experienced alert fatigue (case 5) and the burst-protection fix
- You've understood why business rejection is not poison (case 4)
- You've seen the DLQ envelope as a *contract*, not a debug dump

These are the lessons that make the difference between an iFlow developer who "handles errors" and one who designs error handling. The exception subprocess is the easy part; the discipline of classifying right and alerting actionably is the hard part.
