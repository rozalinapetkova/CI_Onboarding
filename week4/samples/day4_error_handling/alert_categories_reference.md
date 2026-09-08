# Alert categories — what fires, when, to whom

Alerts cost attention. Too many and ops ignores all of them; too few and outages go unnoticed. The team's discipline: one alert category per error classification, severities calibrated to actionability, suppression on in-flight retries.

## Categories

| Category | Severity | Fires when | Audience | Runbook |
|---|---|---|---|---|
| `roi.orderhub.dlq` | ERROR | DLQ depth > 0 OR new envelope written with classification = `poison`/`configuration`/`unknown`/`runtime` | Oncall (paged after hours if `configuration`; otherwise email) | Inspect envelope; manual replay or escalate to producer team |
| `roi.orderhub.retry-stuck` | WARNING | Retry queue depth > 5000 sustained 30 min OR `retryAttempt >= maxRetryAttempts` reached | Oncall (email; page only if business-hours-critical iFlow) | Investigate downstream; manual replay or extend SLA |
| `roi.orderhub.business-reject` | INFO | Business rejection routed to reject queue | None (log only) — dashboard counts visible | Aggregate trends weekly; if a class of rejections spikes, investigate upstream |
| `roi.orderhub.subscription-down` | ERROR | AMQP/JMS subscription disconnected > 5 min | Oncall (paged) | Check Event Mesh / broker health, credentials, network |
| `roi.orderhub.poison-burst` | ERROR | DLQ rate > 50/hour for 30 min | Oncall (paged) | Likely producer-side schema drift; coordinate with upstream |
| `roi.orderhub.transport` | INFO | Transport request created, deployed, or failed | Release engineer (email) | Standard release tracking |

## Severity scale

| Severity | What it implies | Where it routes |
|---|---|---|
| `ERROR` | Customer impact happening or imminent | Pages oncall (after-hours), email + Slack (business hours) |
| `WARNING` | Trend toward customer impact; investigate soon | Email + Slack; no page |
| `INFO` | Observability only; trend tracking | Slack/dashboard only |

Severities map to ANS event severities (`ERROR`, `WARNING`, `INFO`, `NOTICE`). Don't invent new ones.

## The "alert flood" rules

A new alert category must pass these gates before going live:

| Gate | Check |
|---|---|
| **Distinct action** | Does each fire of this alert have a different remediation? If every fire = "investigate manually", consolidate with an existing category |
| **Achievable threshold** | At healthy baseline traffic, fires < 1/week. Otherwise the alert is noise |
| **Suppression on retries** | Doesn't fire during in-flight adapter retries (`redeliveryCounter < Max`) — only after exhaustion |
| **Deduplication window** | Identical alerts within N minutes are suppressed (ANS supports this) — prevents 1000 events failing in a burst from generating 1000 alerts |
| **Owner assigned** | Every category has a named owner who acknowledges and acts on it |

## Suppression strategy — three layers

### Layer 1 — adapter retry suppression

The capture-context script already runs at adapter-retry-exhausted time, not on every redelivery. The subprocess doesn't fire until the broker gives up. So adapter retries are inherently silent until exhausted.

### Layer 2 — ANS deduplication

ANS event with same `type` + `tags.correlationId` within a 10-min window: suppressed. This catches:
- Two iFlow runs failing on the same message (e.g., during a partial-outage incident where the same correlationId re-DLQ's after a botched replay)

### Layer 3 — burst detection

The `roi.orderhub.poison-burst` category exists *specifically* to swallow per-message DLQ alerts during a burst. Logic in ANS rules:

```
IF dlq_event_rate > 50/hour FOR 30 min
THEN
  suppress per-message roi.orderhub.dlq events
  fire one roi.orderhub.poison-burst event
```

Operationally: one alert that says "many bad messages" instead of 500 alerts that each say "one bad message".

## The alert payload — what ANS receives

Built by `roiam_buildAlertEvent.groovy`:

```json
{
  "type": "roi.orderhub.dlq",
  "eventTimestamp": "2026-06-22T14:32:08.123+02:00",
  "subject": "[ERROR] roi.orderhub.dlq — groovy.json.JsonException",
  "severity": "ERROR",
  "category": "EXCEPTION",
  "body": "Unexpected character ('x') in numeric value at line: 3, column: 18",
  "tags": {
    "correlationId": "evt-2026-06-22-7f3a91c4-...",
    "classification": "poison",
    "failedRouteId": "JSONToXMLConverter_2",
    "iflow": "roi-orderhub"
  }
}
```

The `tags` block is critical — ANS routing rules and downstream tooling filter on tags, not on the body. Always include `correlationId`, `classification`, `iflow`.

## Cloud ALM correlation

Cloud ALM (the SAP-side monitoring tool) can subscribe to ANS events. The team uses:

| Cloud ALM dashboard | Subscribed to | Purpose |
|---|---|---|
| Order Hub — Live | All `roi.orderhub.*` ERROR events | Real-time incident view for oncall |
| Order Hub — Trends | All `roi.orderhub.*` events (any severity) | Weekly review; spot rising error classes |
| Order Hub — DLQ Detail | `roi.orderhub.dlq` only | Forensics view with envelope content |

## Anti-patterns

| Anti-pattern | Why bad | Replace with |
|---|---|---|
| One generic `roi.orderhub.error` category for everything | Loses signal; ops can't tell page-worthy from log-worthy | Split by classification, as above |
| Fire on every DLQ envelope without burst protection | Producer outage = ANS rate limit hit → some alerts dropped, others delayed | Burst detection layer |
| Page on `transient` exhaustion | Most transient failures resolve themselves before humans act | Email/WARNING only; page if persists 30+ min |
| No alert on subscription-down | Silent stop of all event processing | Dedicated subscription-down category, ERROR severity |
| Fire alert from inside main process try/catch | Duplicates the subprocess's job; alert fires twice (once for caught, once for re-thrown) | Only the Exception Subprocess fires alerts |

## Cross-reference

| Concern | Where defined |
|---|---|
| What classification maps to what category | `roiam_buildAlertEvent.groovy::pickCategory()` |
| Why business rejections don't alert | `error_categories_reference.md` (Business section) |
| Burst rule for poison events | `error_lab_failure_cases.md` (lab scenario 4) |
| Subscription-down threshold | `event_subscription_flow_diagram.md` (Day 4.4 hooks) |
| Cloud ALM dashboard wiring | Day 4.1 module |
