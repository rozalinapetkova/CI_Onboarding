# Exception Subprocess — Retry / Bypass router wiring

The consumer iFlow's Exception Subprocess is the single most important pattern of Day 3.2. Without it, a permanently-failing message just goes through retries and ends up `Failed` (or `Blocked`, if the adapter's Dead-Letter Queue checkbox is on) with no diagnostic context. This subprocess is how you turn that into deliberate, observable error handling with a real, reprocessable DLQ.

## Canvas layout

```
                       Exception Subprocess
   ┌──────────────────────────────────────────────────────────────────┐
   │                                                                  │
   │  Start Event                                                     │
   │      │                                                           │
   │      ▼                                                           │
   │  Script step                                                     │
   │  roiam_categorizeError.groovy                                    │
   │      │                                                           │
   │      ▼                                                           │
   │  Router  ────────────────  ${property.errorCategory}             │
   │     │                                                            │
   │     ├── "Bypass"                                                 │
   │     │       │                                                    │
   │     │       ▼                                                    │
   │     │   Content Modifier (build DLQ envelope)                    │
   │     │       │                                                    │
   │     │       ▼                                                    │
   │     │   JMS receiver  ──►  roi.orderhub.dlq.<initials>           │
   │     │       │                                                    │
   │     │       ▼                                                    │
   │     │   Message End Event (swallow — JMS treats msg as processed)│
   │     │                                                            │
   │     └── "Retry" (default branch)                                 │
   │             │                                                    │
   │             ▼                                                    │
   │         Error End Event  (rethrow — broker redelivers)           │
   │                                                                  │
   └──────────────────────────────────────────────────────────────────┘
```

## Step-by-step

### 1. Start Event

The Start Event of an Exception Subprocess fires on any unhandled exception in the main Integration Process. You don't configure it — just drop it.

### 2. Script — `roiam_categorizeError.groovy`

See `roiam_categorizeError.groovy` in this folder. Reads `CamelExceptionCaught` (property) and `CamelHttpResponseCode` (header), writes:

- `property.errorCategory` = `Retry` | `Bypass` (used by the Router)
- `header.X-Error-Category` = same (visible in MPL headers)
- MessageLog string property `errorCategory` (visible in *Monitor → Message Processing*)
- MessageLog attachment `categorization` with full diagnostic context

Save under `script/v2/`. Place this script in `sc_<initials>_OrderHubHelpers` Script Collection if you've created one (Day 3.3) — otherwise inline in the iFlow.

### 3. Router on `${property.errorCategory}`

| Branch | Condition | Default? |
|---|---|---|
| Bypass | `${property.errorCategory} = 'Bypass'` | No |
| Retry | (default) | **Yes** — set as Default branch |

**Default = Retry** is the safer fallback: if the categorization script can't decide, you retry. Better to spend a few cycles on an ambiguous case than to silently move it to DLQ.

### 4a. Bypass branch — route to DLQ + swallow

**Content Modifier (optional but recommended):**

Add a header `X-DLQ-Reason` set to `${property.errorReason}` and prepend a small JSON envelope to the body so the DLQ message carries diagnostic context for the on-call:

```json
{
  "originalPayload": "${in.body}",
  "errorCategory": "${property.errorCategory}",
  "errorReason": "${property.errorReason}",
  "httpCode": "${header.CamelHttpResponseCode}",
  "failedAt": "${date:now:yyyy-MM-dd'T'HH:mm:ss'Z'}"
}
```

(Or keep the body unchanged and rely on the headers — depends on what the DLQ consumer/replay tool expects.)

**JMS receiver adapter:**

- Queue Name: `roi.orderhub.dlq.<your_initials>`
- Persistence: `Persistent`

**Message End Event** (the regular End, not an Error End Event). The subprocess completes normally → JMS broker sees the consumer succeeded → removes the message from the source queue. **No retry slot consumed.**

### 4b. Retry branch — rethrow

**Error End Event.** This is the canvas element that re-raises the exception out of the subprocess. JMS broker sees an unhandled error → message stays in the queue and keeps retrying. That's intentional for this branch — you only route here when the categorization script has already decided the failure is transient. If it never actually recovers, it ends up `Failed` (or `Blocked`, if Dead-Letter Queue is enabled).

Alternative: a Script step with `throw new RuntimeException(...)`. The Error End Event is cleaner — the intent is visible from the canvas.

## The crucial difference between Message End Event and Error End Event

| Message End Event | Error End Event |
|---|---|
| Subprocess completes normally | Subprocess re-raises the exception |
| JMS broker thinks message was processed successfully | JMS broker sees a processing failure |
| Message removed from the queue | Message returns to the queue, `SAPJMSRetries` incremented |
| Use for Bypass after explicit DLQ enqueue | Use for Retry — broker keeps redelivering with backoff |

Get this backwards and you either:

- Use Message End Event on Retry → message looks "processed" but the downstream never actually got it. Silent data loss.
- Use Error End Event on Bypass → message goes to DLQ explicitly *and* keeps getting redelivered by the broker on top of that, since rethrowing never stops. The same broken message lands in the DLQ repeatedly. Operations confusion.

## Where this lives in the iFlow XML

Exception Subprocess is a `<bpmn2:subProcess>` element with `<bpmn2:property name="activityType" value="ExceptionSubprocess"/>`. Inside it: the same Camel-route DSL as the main Integration Process. The Router is `<bpmn2:exclusiveGateway>`; an Error End Event is `<bpmn2:endEvent>` with `<bpmn2:errorEventDefinition/>`; a Message End Event is `<bpmn2:endEvent>` without it.
