# Exception Subprocess — the pattern

The Exception Subprocess is the iFlow's `try/catch`. It runs only when the main process raises an exception. Every iFlow on the team has exactly one.

## What it is

A second pool inside the iFlow XML, parallel to the main process. The CI runtime watches for unhandled exceptions in the main process; when one fires, control transfers to the Exception Subprocess's Error Start Event, with the original Message (headers, properties, body) intact plus a few runtime properties set by Camel.

```
┌────────────────────────────────────────────────┐
│  Main process pool                             │
│  [Start] → [Step 1] → [Step 2] → ... → [End]   │
│                  ↑                             │
│                  └─ exception thrown here      │
│                     control transfers ──┐      │
└─────────────────────────────────────────┼──────┘
                                          │
┌─────────────────────────────────────────┼──────┐
│  Exception Subprocess pool              │      │
│  [Error Start] ←──────────────────────  ┘      │
│       ↓                                        │
│  [capture-context script]                      │
│       ↓                                        │
│  [Router: classify]                            │
│       ↓                                        │
│  poison / transient / business / configuration │
│       ↓                                        │
│  [DLQ / retry queue / reject / alert]          │
│       ↓                                        │
│  [Error End]                                   │
└────────────────────────────────────────────────┘
```

## Constraints — what the subprocess can and can't do

| Constraint | What it means | Practical consequence |
|---|---|---|
| **One per pool** | An iFlow can have at most one Exception Subprocess for its main process | All error handling logic must converge in one place; route inside the subprocess, don't multiply subprocesses |
| **Runs in the same transaction** | Failure in the subprocess re-fails the whole exchange | A subprocess that throws is worse than no subprocess; keep its steps simple and defensive |
| **Cannot suppress failure** | The exchange is always marked as failed even after subprocess runs | You cannot "catch and recover" — only "catch and log/route" |
| **Cannot retry the failed step** | The subprocess runs *after* the step failed; no re-execution from the same point | Retry happens at the *adapter* level (JMS Maximum Redelivery), not the subprocess level |
| **JMS retry policy runs FIRST** | If the entry adapter is JMS with Maximum Redelivery > 0, exhaustion happens before the subprocess fires | The subprocess only sees terminal failures, not intermediate retries |
| **Sub-flow / Local Process Call inheritance** | Sub-flows do NOT have their own subprocess; exceptions bubble up to the calling iFlow's subprocess | Don't try to wrap sub-flows in their own try/catch — let the parent handle |

## What's available when the subprocess fires

| Property | Source | Typical value |
|---|---|---|
| `CamelExceptionCaught` | Set by runtime | The `Throwable` instance — `.getClass().getName()` and `.getMessage()` are what classification reads |
| `CamelFailureRouteId` | Set by runtime | The route (step) ID where the failure occurred |
| `CamelFailureEndpoint` | Set by runtime | If failure was on a Sender/Receiver, the endpoint URI |
| `CamelRedeliveryCounter` | Set by adapter | If JMS/AMQP, how many times the broker has tried to re-deliver |
| All headers from main process | Inherited | `ce-id`, `correlationId`, `roiam_*`, etc. |
| All properties from main process | Inherited | Whatever Content Modifiers set |
| Message body | Inherited (last-known state) | Whatever the body was at the moment of failure — may be transformed, may be original; capture-context script preserves it |

## The standard subprocess shape

The team's convention — every iFlow follows this:

```
[Error Start Event]
        ↓
[Script: roiam_captureErrorContext]
        ↓     (sets errorClassification, errorClass, errorMessage,
        ↓      failedAt, redeliveryCounter; attaches captured body)
        ↓
[Router: by errorClassification]
        ├──── "poison" ─────────→ [build DLQ envelope] → [JMS: DLQ] → [build alert] → [ANS] → [Error End]
        ├──── "configuration" ──→ [build DLQ envelope] → [JMS: DLQ] → [build alert sev=1] → [ANS] → [Error End]
        ├──── "transient" ──────→ [build retry envelope] → [JMS: retry queue] → [Error End]
        ├──── "business" ───────→ [build reject envelope] → [JMS: reject queue] → [Error End]
        └──── "unknown" (default) → [build DLQ envelope] → [JMS: DLQ] → [build alert] → [ANS] → [Error End]
```

Every branch ends in an **Error End Event**, not a regular End. This signals to the runtime that the exchange terminated as a failure — important for MPL status (`Failed` vs `Completed`) and for the entry adapter (no ACK sent on JMS/AMQP, so the broker handles redelivery or DLQ per its policy).

## When to use it — and when not

| Situation | Use subprocess? | Reason |
|---|---|---|
| Any production iFlow | **Yes** | Standard practice; without one, exceptions are logged to MPL only and ops has nothing to act on |
| Throwaway / one-shot script iFlow | No | Overhead not worth it; MPL is fine for ad-hoc work |
| Sub-flow / Local Process Call | No (it can't have one anyway) | Parent's subprocess catches it |
| iFlow with only synchronous request-reply | Yes, but simpler | Caller already sees the error in the HTTP response; subprocess role is alerting + DLQ-for-forensics, not redelivery |
| iFlow whose failure should pass through to caller verbatim | Yes, with bypass branch | Subprocess classifies, alerts on `configuration`-class, but does NOT swallow — re-throws so caller sees error |

## Common mistakes

1. **Treating the subprocess as retry logic.** It can't retry. Retry is the adapter's job (JMS Maximum Redelivery, AMQP Maximum Retries). The subprocess decides what to do *after* retries are exhausted.

2. **Building parallel subprocesses for different exception types.** CI allows only one per pool. Use a router *inside* the subprocess, not multiple subprocesses.

3. **Throwing from the subprocess.** A `throw` from a script in the subprocess propagates out and re-fails the exchange in a worse way (no MPL attachments, possibly no DLQ write). Wrap subprocess scripts' bodies in try/catch and log-but-don't-rethrow.

4. **Forgetting the Error End event.** Using a regular End event sends an ACK on JMS/AMQP entry adapters, which removes the message from the broker queue even though processing failed. Always Error End on a failure branch.

5. **Reading the body in the subprocess and re-serializing.** The body at failure-time may already be partially transformed. Capture it as-is (binary-safe). Don't try to "fix" it inside the subprocess; let the replay iFlow do that with full context.

6. **No idempotency on DLQ writes.** If the subprocess itself fails partway (e.g., DLQ JMS send succeeds but alert send fails, and the broker re-delivers the original event), you get duplicate DLQ entries. Dedup on `correlationId` + `failedAt` in the DLQ consumer.

## What the subprocess does NOT replace

| Concern | Where it actually lives |
|---|---|
| Per-step validation (schema, required fields) | Validator step in main process — fail fast, let subprocess catch |
| Adapter-level retries | Sender/Receiver adapter configuration (Maximum Retries, backoff) |
| Long-term forensics | DLQ consumer iFlow + Data Store, not the subprocess itself |
| Replay | Separate replay iFlow that reads DLQ and re-injects to main process |
| Alerting routing rules | Alert Notification Service (ANS) categories, not subprocess logic |
| MPL custom properties (correlationId, etc.) | Main process Script step at entry, so they exist *before* failure can occur |

The subprocess is the **last line of defense and the dispatcher**. Everything else — validation, retry, alerting wiring, replay — lives elsewhere and is glued together by the classification the subprocess produces.
