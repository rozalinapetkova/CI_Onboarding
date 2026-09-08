# Final Order Hub canvas — Week 4 complete shape

The Order Hub at the end of Week 4. All four entry paths, the Exception Subprocess, idempotency, retry policy, DLQ, and alert wiring assembled.

## The complete iFlow canvas

```
═══════════════════════════════════════════════════════════════════════════════
                          ENTRY ADAPTERS
═══════════════════════════════════════════════════════════════════════════════

  ┌──────────────────────┐     ┌────────────────────────┐
  │ [Sender: HTTPS]      │     │ [Sender: AMQP]         │
  │  Path: /orders       │     │  Queue: roi-orderhub-  │
  │  Method: POST        │     │         salesorder-    │
  │  Auth: OAuth         │     │         created        │
  │                      │     │  Sub: Durable          │
  └──────────┬───────────┘     │  Ack: Client           │
             │                 │  Max Retries: 5        │
             │                 └────────────┬───────────┘
             │                              │
             │      ┌───────────────────────┘
             ▼      ▼
  ┌──────────────────────────────────────────────────────────┐
  │ [Script: roiam_setCorrelationId]                         │
  │  correlationId = ce-id || header.correlationId || UUID   │
  │  MPL custom props: correlationId, entryPoint, eventType  │
  └──────────────────────┬───────────────────────────────────┘
                         ▼
  ┌──────────────────────────────────────────────────────────┐
  │ [Content Modifier: capture original body to property]    │
  │  property: originalBody = ${body}                        │
  │  used by subprocess if main path mutates body            │
  └──────────────────────┬───────────────────────────────────┘
                         ▼
  ┌──────────────────────────────────────────────────────────┐
  │ [Data Store Get: roi_orderhub_event_dedup]               │
  │  Key: ${header.ce-id || correlationId}                   │
  │  Throw on miss: NO                                       │
  └──────────────────────┬───────────────────────────────────┘
                         ▼
  ┌──────────────────────────────────────────────────────────┐
  │ [Router: Idempotency Decision]                           │
  └──────┬──────────────────────────────────┬────────────────┘
         │ HIT (duplicate)                   │ MISS (first time)
         ▼                                   ▼
  ┌──────────────────┐         ┌──────────────────────────────────────────┐
  │ [Script: log     │         │ [Content Modifier]                       │
  │  duplicate]      │         │  header: roiam_routing_destination       │
  │  MPL: Discarded  │         │          = 'default'                     │
  └────────┬─────────┘         └────────────────────┬─────────────────────┘
           ▼                                        ▼
  ┌──────────────────┐         ┌──────────────────────────────────────────┐
  │ [End: Discarded] │         │ [Script: roiam_resolveRoutingFromPd]     │
  └──────────────────┘         │  Reads PD: ROI_ORDERHUB_ROUTING/default  │
                               │  Dispatch by ce-type → roiam_target_*    │
                               └────────────────────┬─────────────────────┘
                                                    ▼
                               ┌──────────────────────────────────────────┐
                               │ [Mapping: source → Canonical XML]        │
                               │  HTTP path: vendor XML → canonical       │
                               │  AMQP path: CloudEvents JSON → canonical │
                               └────────────────────┬─────────────────────┘
                                                    ▼
                               ┌──────────────────────────────────────────┐
                               │ [Receiver: JMS Producer]                 │
                               │  Queue: roi.orderhub.queue               │
                               │  (shared internal queue; downstream      │
                               │   consumer iFlow drains it)              │
                               └────────────────────┬─────────────────────┘
                                                    ▼
                               ┌──────────────────────────────────────────┐
                               │ [Data Store Write: roi_orderhub_event_   │
                               │                    dedup]                │
                               │  Key: ${ce-id || correlationId}          │
                               │  TTL: 7 days                             │
                               │  ONLY on success path                    │
                               └────────────────────┬─────────────────────┘
                                                    ▼
                               ┌──────────────────────────────────────────┐
                               │ [End: Completed]                         │
                               └──────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════════════════
                       EXCEPTION SUBPROCESS POOL
═══════════════════════════════════════════════════════════════════════════════

  ┌──────────────────────────────────────────────────────────┐
  │ [Error Start Event]                                      │
  └──────────────────────────┬───────────────────────────────┘
                             ▼
  ┌──────────────────────────────────────────────────────────┐
  │ [Script: roiam_captureErrorContext]                      │
  │  reads:  CamelExceptionCaught, CamelFailureRouteId,      │
  │          CamelRedeliveryCounter                          │
  │  sets:   errorClassification, errorClass, errorMessage,  │
  │          failedAt, correlationId (fallback chain)        │
  │  MPL attachments: error-context, failed-payload          │
  └──────────────────────────┬───────────────────────────────┘
                             ▼
  ┌──────────────────────────────────────────────────────────┐
  │ [Router: by errorClassification]                         │
  └──┬───────┬───────────┬────────────┬──────────────────────┘
     │       │           │            │
     │poison │transient  │business    │configuration / unknown / runtime
     │       │           │            │
     ▼       ▼           ▼            ▼
  ┌─────┐ ┌──────────┐ ┌────────┐ ┌─────┐
  │ DLQ │ │  RETRY   │ │ REJECT │ │ DLQ │
  │branch│ │ branch  │ │ branch │ │ +   │
  │     │ │          │ │        │ │ SEV1│
  └──┬──┘ └─────┬────┘ └────┬───┘ └──┬──┘
     │          │           │        │
     │   ┌──────┘    ┌──────┘        │
     │   │           │               │
     ▼   ▼           ▼               ▼

  [Script: roiam_buildDlqEnvelope]   [Script:  [Script: build alert sev=ERROR
        (poison/cfg/runtime/unk)      build     immediate-page category
         OR build retry envelope      reject    roi.orderhub.dlq]
         OR build reject envelope]    env]
                │                       │             │
                ▼                       ▼             ▼
  [Receiver: JMS]                  [Receiver:    [Receiver: HTTP→ANS]
   Dest:                            JMS]          POST event to
   - roi.orderhub.dlq               Dest: roi.    Alert Notification
   - roi.orderhub.retry             orderhub.     Service
   - roi.orderhub.reject            reject
                │                       │             │
                ▼                       ▼             │
  [Script: roiam_buildAlertEvent]                     │
   (skipped on retry/reject branches)                 │
                │                                     │
                ▼                                     │
  [Receiver: HTTP→ANS]◄────────────────────────────── │ (alert step shared
                │                                       across branches)
                ▼
  ┌──────────────────────────────────────────────────────────┐
  │ [Error End Event]                                        │
  │  signals failure to runtime; entry adapter does NOT ACK  │
  └──────────────────────────────────────────────────────────┘
```

## What's wired up by Week 4 end

| Capability | Implemented in | Day |
|---|---|---|
| MPL custom properties for correlation | `roiam_setCorrelationId` at entry | 4.1 |
| Cloud ALM dashboard / queue alerts | ANS rules + Cloud ALM subscription | 4.1 |
| Transport routing Dev→QA→Prod | CTM packages + Configure-on-target | 4.2 |
| Event subscription (CloudEvents) | AMQP Sender + dedup | 4.3 |
| Partner Directory routing | `roiam_resolveRoutingFromPd` | 4.3 |
| Exception Subprocess | Per shape above | 4.4 |
| Capture context | `roiam_captureErrorContext` | 4.4 |
| Structured DLQ envelope | `roiam_buildDlqEnvelope` + schema | 4.4 |
| JMS retry policy | Adapter Maximum Redelivery + backoff | 4.4 |
| Retry queue | `roi.orderhub.retry` + retry consumer iFlow | 4.4 |
| Alert routing by classification | `roiam_buildAlertEvent` → ANS categories | 4.4 |
| Replay-safe DLQ design | End-of-flow dedup write + envelope schema | 4.4 |

## What is NOT in this iFlow (and where it lives)

| Concern | Lives in | Why |
|---|---|---|
| Downstream consumer (OMS-facing call) | `roi-orderhub-consumer` iFlow | Separate concerns; consumer dedupes and posts to OMS |
| DLQ replay | `roi-orderhub-replay` iFlow | Day 4.4 sketches; full build is post-curriculum |
| Forensics archival | DLQ consumer iFlow writes to Data Store / external store | Day 4.4 design |
| Routing rules content | Partner Directory `ROI_ORDERHUB_ROUTING/default` | Editable without redeploy |
| OAuth credentials | Security Material `orderhub-<env>-oauth` | Per-tenant alias |
| AMQP credentials | Security Material `event_mesh_amqp_<your_initials>` | Per-tenant alias |
| Queue-to-topic bindings | Event Mesh cockpit | Broker-side config |
| ANS routing rules / dedup window | ANS configuration | Out of iFlow |

## How the shape evolves later

| Future change | What in canvas changes |
|---|---|
| Add a third entry path (file drop, scheduled poll) | New Sender, converges to same post-correlation flow |
| Add per-partner routing (not just default) | `roiam_routing_destination` header set by entry script based on partner header; `resolveRoutingFromPd` already reads it |
| Add schema validation | New Validator step after entry, before idempotency check; throws on mismatch → subprocess catches as `poison` |
| Add request-reply for synchronous HTTP entry | Loop back from consumer queue's result; HTTP entry must hold its exchange — usually a separate iFlow pattern |
| Split into multiple smaller iFlows | Likely natural at "consumer" boundary; entry+dedup stays one iFlow, consumer separate |

## The week-by-week comparison

| Week | What the iFlow looks like |
|---|---|
| 1 | HTTP entry → mapping → HTTP receiver. No subprocess, no dedup, no DLQ |
| 2 | HTTP entry → mapping → JMS handoff → consumer iFlow. Subprocess minimal (log only) |
| 3 | + Idempotency check (Data Store dedup). + Idempotency cache for response. Subprocess writes generic alert |
| 4 | + AMQP entry. + PD-driven routing. + Capture context, classified subprocess, structured DLQ, alert wiring. + Transport-ready |

Each week added one capability without breaking the prior ones. The capacity to do that — adding capabilities without rewiring — comes from the discipline: capture early, dedup late, side effects last, error handling at the boundary.

## Reading order for someone joining the project

1. This canvas (you are here)
2. `error_categories_reference.md` — to understand classification
3. `exception_subprocess_pattern.md` — to understand the subprocess shape
4. `dlq_envelope_schema.md` — to understand the contract
5. `replay_safety_pattern.md` — to understand why it's designed this way
6. The Groovy scripts — to see the implementation match the shape
