# Retry queue pattern — "try again later" for transient errors

The DLQ is for messages that won't succeed without intervention. The **retry queue** is for messages that probably *will* succeed — just not right now. They're different destinations with different consumer logic.

## Why a separate queue, not just more redeliveries

The JMS Maximum Redelivery covers *immediate* retries (seconds-to-minutes range). Some transient failures need *scheduled* retry — minutes-to-hours.

| Scenario | Right tool |
|---|---|
| Network blip, OAuth token momentarily invalid | JMS Maximum Redelivery (retries within 30 min absorbing) |
| Downstream OMS announced 2-hour maintenance window | Retry queue (re-attempt in 2 hours, not 30 minutes) |
| Throttled by downstream (HTTP 429 with `Retry-After: 3600`) | Retry queue (honor the back-pressure signal) |
| Vendor's daily batch window closes at 18:00; we hit it at 17:58 | Retry queue (re-attempt at 06:00 the next morning) |
| Schema validation failure | **Not retry queue** — DLQ, never auto-retry |

The first row stays in the adapter retry. The next four call for a retry queue.

## Queue layout

```
roi.orderhub.queue           ← main work queue (entry → downstream)
roi.orderhub.retry           ← scheduled-retry queue
roi.orderhub.dlq             ← terminal failures
```

A "retry consumer" iFlow drains `roi.orderhub.retry` on a schedule, re-publishing each message to `roi.orderhub.queue` for normal processing.

## The retry queue envelope

Same shape as the DLQ envelope (`dlq_envelope_schema.md`) plus:

| Extra field | Type | Description |
|---|---|---|
| `retryAfter` | string (ISO 8601) | Earliest re-attempt time. Producer iFlow sets based on the failure (e.g., `now + 1h` for generic transient; honoring `Retry-After` if HTTP) |
| `retryAttempt` | integer | Count of retry-queue cycles for this correlationId. `1` on first entry. |
| `maxRetryAttempts` | integer | Default 5. After this, the retry consumer moves to DLQ. |

## The retry consumer iFlow shape

```
[JMS Sender: roi.orderhub.retry, Read=peek-then-commit]
         ↓
[Script: roiam_checkRetryReady] — compares now() to envelope.retryAfter
         ↓
   ┌─────┴─────┐
   ↓           ↓
ready    not-ready
   ↓           ↓
[unwrap   [requeue with delay
 envelope, OR leave in queue
 publish    if broker supports
 to main    timed delivery]
 queue]
   ↓
[ACK]
```

Or, simpler if the broker supports scheduled delivery (most do): the producer sets the JMS scheduled-delivery header and writes directly to the *main* queue with a future delivery time. No second consumer iFlow needed. Use this when available.

| Broker | Scheduled delivery header | Notes |
|---|---|---|
| SAP CPI internal JMS | `JMS_AMQP_DeliveryTime` (epoch ms) | Native support; preferred |
| ActiveMQ | `AMQ_SCHEDULED_DELAY` (ms from now) | Native |
| RabbitMQ | Not native; need delayed-message plugin | Workaround: separate retry queue |
| Solace (Event Mesh) | `_AMQP_TTL` + DLQ chain | Workaround; less elegant |

## Inside the Exception Subprocess — routing to retry vs DLQ

```
[Router: by errorClassification]
├── "transient" + redeliveryCounter < 5      → main process retries continue (no subprocess fire — adapter still trying)
├── "transient" + redeliveryCounter >= 5     → retry queue (with retryAfter = now + 1h)
├── "transient" + retryAttempt >= maxRetry   → DLQ (give up; surface to humans)
├── "poison"                                 → DLQ
├── "configuration"                          → DLQ + page
├── "business"                               → reject queue
└── "unknown"                                → DLQ
```

The retry queue exists between "broker retry exhausted" and "DLQ". It buys hours of patience without burning the adapter retry budget.

## When to use, when not

| Use retry queue when | Don't use when |
|---|---|
| Failure is known-transient (network, throttle, scheduled outage) | Failure is poison (malformed payload) |
| Re-attempt window is hours, not seconds | Re-attempt is immediate (use adapter retry) |
| Downstream gave a Retry-After hint | Failure is configuration (won't fix by retrying) |
| Cost of retry < cost of human investigation | Cost of duplicate is high and dedup not in place |

## Hazards

1. **No bound on retry attempts** — easy to create an infinite-loop queue. Always enforce `maxRetryAttempts`. The consumer must move to DLQ on the Nth attempt.

2. **Stale retries** — message scheduled for retry in 4 hours; meanwhile the downstream comes back online and forward processing resumes; eventually the scheduled retry fires *after* a manual replay already succeeded → duplicate. Mitigate with downstream-side idempotency (`replay_safety_pattern.md`).

3. **Volume explosion during outages** — if downstream is down for 6 hours and 10k events/hour arrive, your retry queue has 60k entries scheduled for the same hour. The consumer iFlow becomes a thundering herd. Smear retryAfter by adding jitter: `retryAfter = now + baseDelay + random(0, baseDelay * 0.3)`.

4. **Retry queue depth not monitored** — operators don't see the backlog. Add a Cloud ALM rule on `roi.orderhub.retry` queue depth (Day 4.1). Different threshold than the main queue — the retry queue is *expected* to have depth, but if it grows monotonically for hours, that's a problem.

## Operational view

| Queue | Healthy depth | Alert depth | Alert delay |
|---|---|---|---|
| `roi.orderhub.queue` | 0–10 | >100 sustained 5 min | 5 min |
| `roi.orderhub.retry` | 0–500 (spike during outages) | >5000 sustained 30 min | 30 min |
| `roi.orderhub.dlq` | 0 | >0 | Immediate |

DLQ depth > 0 is always an alert. Retry queue depth needs *trend* analysis, not threshold.

## The "no retry queue" alternative

For small / simple iFlows, skip the retry queue entirely. Adapter retry → DLQ; humans inspect DLQ and decide whether to replay. Adds operator burden but reduces moving parts.

Use the retry queue only when:
- Volume makes manual replay impractical (>10 transient failures/day)
- Outages routinely exceed adapter retry budget (>30 min)
- You have a consumer iFlow already running on a schedule that can absorb the retry consumer role

Otherwise: adapter retries + DLQ + human replay is enough.
