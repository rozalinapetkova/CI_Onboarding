# Event subscription flow — the Order Hub canvas

Use this as the visual reference while building the AMQP entry branch. It maps to Section 10 of `day3_event_driven.md` and the hands-on lab steps.

## The full canvas

```
                ┌──────────────────────────────────────────────┐
                │     [Sender: AMQP]                           │
                │       Address Type:   Queue                  │
                │       Address Name:   roi-orderhub-          │
                │                       salesorder-created     │
                │       Subscription:   Durable                │
                │       Sub. Name:      roi-orderhub-          │
                │                       salesorder-v1          │
                │       Ack Mode:       Client Ack             │
                └────────────────────┬─────────────────────────┘
                                     │
                                     ▼
                ┌──────────────────────────────────────────────┐
                │     [Script: roiam_setCorrelationId_event]   │
                │       correlationId ← ce-id (or UUID)        │
                │       MPL custom prop: correlationId,        │
                │         eventId, eventType, eventSubject     │
                └────────────────────┬─────────────────────────┘
                                     │
                                     ▼
                ┌──────────────────────────────────────────────┐
                │     [Data Store Get]                         │
                │       Store:  roi_orderhub_event_dedup       │
                │       Key:    ${header.ce-id}                │
                │       Throw on miss: NO  (miss is the        │
                │                          happy path)         │
                └────────────────────┬─────────────────────────┘
                                     │
                                     ▼
                ┌──────────────────────────────────────────────┐
                │     [Router: Idempotency Decision]           │
                │       Condition: property.dedupHit == 'true' │
                └─────────┬──────────────────────────┬─────────┘
                          │                          │
                  HIT (duplicate)              MISS (first time)
                          │                          │
                          ▼                          ▼
            ┌──────────────────────────┐  ┌──────────────────────────────┐
            │ [Script: log duplicate]  │  │ [Content Modifier]           │
            │   MessageLog attachment: │  │   header: roiam_routing_     │
            │     duplicate-event      │  │   destination = 'default'    │
            │   MPL custom prop:       │  └────────────┬─────────────────┘
            │     status = Discarded   │               │
            └────────────┬─────────────┘               ▼
                         │                ┌──────────────────────────────┐
                         ▼                │ [Script: roiam_resolve       │
                ┌──────────────────┐      │            RoutingFromPd]    │
                │ [End: Discarded] │      │   reads PD: ROI_ORDERHUB_    │
                └──────────────────┘      │              ROUTING/default │
                                          │   sets:  roiam_target_system │
                                          │          roiam_target_path   │
                                          └────────────┬─────────────────┘
                                                       │
                                                       ▼
                                          ┌──────────────────────────────┐
                                          │ [Mapping: JSON → Canonical   │
                                          │            XML]              │
                                          │   re-use Week 2 mapping      │
                                          │   on the CloudEvents 'data'  │
                                          │   block                      │
                                          └────────────┬─────────────────┘
                                                       │
                                                       ▼
                                          ┌──────────────────────────────┐
                                          │ [Receiver: JMS Producer]     │
                                          │   Queue: roi.orderhub.queue  │
                                          │   (shared with HTTP entry    │
                                          │    path)                     │
                                          └────────────┬─────────────────┘
                                                       │
                                                       ▼
                                          ┌──────────────────────────────┐
                                          │ [Data Store Write]           │
                                          │   Store:  roi_orderhub_      │
                                          │             event_dedup      │
                                          │   Key:    ${header.ce-id}    │
                                          │   TTL:    7 days             │
                                          │   ONLY on success path       │
                                          └────────────┬─────────────────┘
                                                       │
                                                       ▼
                                          ┌──────────────────────────────┐
                                          │ [End: Completed]             │
                                          └──────────────────────────────┘
```

## Decision points explained

### Decision 1 — Idempotency Router (after Data Store Get)

| Outcome | Condition | Next |
|---|---|---|
| Duplicate event | The Data Store Get found an entry under `ce-id` (within 7-day TTL) | Log + MPL Discarded, end early |
| First-time event | No entry found | Continue to routing resolution |

**Why this comes BEFORE routing**: routing-resolution does a PD lookup and possibly hits the downstream. Cheap to skip for duplicates; we save the round-trips.

### Decision 2 — implicit: AMQP adapter retry on iFlow failure

This isn't a router on the canvas — it's the AMQP adapter's Maximum Retries setting:

| Outcome | Effect |
|---|---|
| iFlow run completes successfully | ACK sent to broker; message removed from queue |
| iFlow run fails on attempt 1–5 | No ACK; broker re-delivers after backoff |
| iFlow run fails on attempt 5+ | Broker stops re-delivery; message moves to DLQ (configured in Event Mesh cockpit) |

## Why the dedup write is at the END

A common mistake: writing to the dedup store right after the Data Store Get (or even before resolution).

| Pattern | What happens on iFlow failure mid-flow |
|---|---|
| Write at start (wrong) | The event was "seen", iFlow then fails. Re-delivery hits the dedup, gets marked Discarded, downstream never gets the order. **Permanent skip.** |
| Write at end (right) | iFlow fails before write. Re-delivery hits empty dedup, retries the full path. May process duplicates if the downstream JMS send succeeded but write didn't — but the downstream-side dedup catches it. |

The trade-off: end-write may cause duplicates if failure is *after* JMS send but *before* dedup write. The alternative (start-write) causes silent skips on failure. Duplicates are catchable; silent skips aren't. End-write wins.

## Shared queue convergence

Notice the JMS Producer step: `roi.orderhub.queue` is the same queue the HTTP entry path writes to. Whether an order arrives via:
- HTTP POST from a partner (Week 1–3 path), or
- AMQP event from S/4 (Day 4.3 path),

…both converge here. The downstream consumer iFlow (Week 3 design) doesn't know or care which entry point fired.

**The benefit**: one downstream consumer, two entry points. Adding a third entry point (file drop, scheduled poll) plugs into the same queue.

**The constraint**: the canonical XML format must be identical from both entry points. The JSON→Canonical XML mapping in the event path must produce the exact same shape as the vendor-XML→Canonical XML mapping in the HTTP path. Schema validation on the downstream side enforces this — drift breaks both paths equally.

## What you DON'T see on the canvas

| Concern | Where it lives |
|---|---|
| AMQP credentials | Security Material alias `event_mesh_amqp` (referenced by adapter) |
| Queue-to-topic binding | Event Mesh cockpit (not in iFlow XML) |
| DLQ configuration | Event Mesh cockpit, queue settings |
| Routing rules content | Partner Directory (referenced by script, not embedded) |
| Subscription state (backlog, depth) | Broker (Event Mesh) |
| Retry backoff schedule | AMQP adapter configuration tab |

This off-canvas state is what makes event-driven different from request-reply: a lot of the system's behavior lives outside the iFlow's XML. The canvas tells you *the logic*; the broker, PD, and credentials store tell you *the configuration*. Both must be consistent across Dev / QA / Prod.

## Day 4.4 hooks (preview)

Day 4.4 (Error Handling) will add:

- An **Exception Subprocess** that catches script/mapping failures, attaches the full original event to MPL, and (depending on classification) either lets the AMQP adapter retry or routes to a permanent error path.
- A **DLQ consumer iFlow** that pulls from `roi-orderhub-salesorder-created.dlq` and writes to a forensics Data Store for offline analysis.
- An **alert wiring** for "subscription disconnected > 5 min" tied to Cloud ALM (from Day 4.1).

Build Day 4.3 first as drawn here. Day 4.4 layers error handling on top without restructuring the happy path.
