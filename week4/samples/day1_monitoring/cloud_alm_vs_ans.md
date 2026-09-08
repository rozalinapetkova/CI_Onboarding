# Cloud ALM vs Alert Notification Service — decision matrix

Both are SAP-provided monitoring tools. They overlap; neither replaces the other. The Order Hub uses both.

## At a glance

| | Alert Notification Service (ANS) | Cloud ALM |
|---|---|---|
| **Purpose** | Real-time event routing — turn an event into a notification | Long-term observability + lifecycle management |
| **Latency** | Seconds (events route immediately) | Minutes (synthetic checks run on schedule) |
| **Retention** | Short — events held for ~30 days then dropped | 90+ days, queryable |
| **Triggered by** | iFlow emits an event, or CI emits an MPL event automatically | Scheduled synthetic checks, CTM transport events, MPL polling |
| **Output** | Email, Teams, Slack, Webhook, PagerDuty, ServiceNow, OpenAPI | Dashboards, reports, queryable cockpit + can forward to ANS |
| **Cost model** | Per-event throughput | Per-monitored-system + per-check |
| **Setup effort** | Minutes (one subscription) | Hours (synthetic monitoring config, scenario mapping, change-tracking) |

## When to use which

| Use case | Tool |
|---|---|
| "Page on-call when the Order Hub DLQ gets a message" | **ANS** — immediate, action-routed |
| "Show me availability of the Order Hub endpoint for the last 90 days" | **Cloud ALM** — retention + synthetic monitoring |
| "Catch deploys that broke a downstream consumer" | **Both** — Cloud ALM change tracking flags the deploy, ANS pings ops |
| "Was the iFlow up at 02:14 last Tuesday?" | **Cloud ALM** — long-window history |
| "End-of-quarter SLA report" | **Cloud ALM** — retention + reporting |
| "Wake somebody up right now" | **ANS** — that's its job |
| "Synthetic curl every 5 minutes to verify the endpoint responds" | **Cloud ALM** — has the scheduler |
| "Audit trail of who deployed what" | **Cloud ALM** — change events |
| "Track end-user error rate" | **Cloud ALM** — RUM data feed |

## How they interact

Cloud ALM can **forward events to ANS**. The intended pattern:

- Cloud ALM detects an issue (synthetic check fails, KPI breaches threshold).
- Cloud ALM emits an ANS-formatted event.
- ANS routes it via the subscription you already configured.

This way, operations has one subscription pipeline regardless of source — Cloud ALM, iFlow scripts, or CI native MPL events all flow through ANS to the same Action.

## For the Order Hub lab — what we wire

| Day | Tool | What |
|---|---|---|
| Day 4.1 | ANS | One subscription on `roi.orderhub.dlq` to a trainer-provided Email action |
| Day 4.1 | Cloud ALM | Trainer-driven tour (~15 min). No trainee wiring this week |
| Day 4.2 | Cloud ALM | Change tracking demonstration during CTM Dev → QA promotion |
| Day 4.4 | ANS | Explicit emit step from the iFlow's Exception Subprocess |

Cloud ALM full-config is out of scope for Week 4. It's a multi-day topic and the cohort hasn't yet built enough iFlows to fill its dashboards meaningfully.

## What Cloud ALM is NOT

- Not a logging tool — it doesn't capture message payloads. Use the MPL for that.
- Not an iFlow editor — it doesn't deploy or modify iFlows.
- Not a free replacement for ANS — it costs more per monitored system; use ANS for routing.

## What ANS is NOT

- Not a historical store — events drop after ~30 days. Use Cloud ALM for retention.
- Not a dashboard tool — it's a router. No charts, no aggregation, no trending.
- Not a synthetic monitor — it reacts to events, doesn't generate them. Cloud ALM (or a scheduled iFlow) generates synthetic events.

## The honest summary

For a cohort just learning monitoring:

1. Wire ANS for **immediate alerts** (Day 4.1).
2. Look at Cloud ALM during the trainer tour to know it exists.
3. Revisit Cloud ALM properly when you have 10+ iFlows in production and need dashboards. By then, you'll know which KPIs matter.

Trying to do both perfectly on day one is a common over-engineer trap. The Order Hub gets value from ANS today; from Cloud ALM in 3 months.
