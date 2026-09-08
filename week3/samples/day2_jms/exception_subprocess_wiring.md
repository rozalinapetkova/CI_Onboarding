# Exception Subprocess — Retry / Bypass router wiring

The consumer iFlow's Exception Subprocess is the single most important pattern of Day 3.2. It's how you turn opaque "JMS retried 3 times then DLQ'd" into deliberate, observable error handling.

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
   │     │   End (swallow — JMS treats message as processed)          │
   │     │                                                            │
   │     └── "Retry" (default branch)                                 │
   │             │                                                    │
   │             ▼                                                    │
   │         End Throw  (rethrow — JMS increments retry counter)      │
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

**End event** (regular End, NOT End Throw). The subprocess completes normally → JMS broker sees the consumer succeeded → removes the message from the source queue. **No retry slot consumed.**

### 4b. Retry branch — rethrow

**End Throw event.** This is the canvas element that re-raises the exception out of the subprocess. JMS broker sees an unhandled error → message stays in the queue, retry counter increments, after `Number of Retries` (3) it goes to the auto-DLQ.

Alternative: a Script step with `throw new RuntimeException(...)`. End Throw is cleaner — the intent is visible from the canvas.

## The crucial difference between End and End Throw

| End | End Throw |
|---|---|
| Subprocess completes normally | Subprocess re-raises the exception |
| JMS broker thinks message was processed successfully | JMS broker sees a processing failure |
| Message removed from the queue | Message returns to the queue with retry counter incremented |
| Use for Bypass after explicit DLQ enqueue | Use for Retry — let JMS retry/auto-DLQ logic run |

Get this backwards and you either:

- Use `End` on Retry → message looks "processed" but the downstream never actually got it. Silent data loss.
- Use `End Throw` on Bypass → message goes to DLQ explicitly *and* JMS retries 3 more times *and* eventually auto-DLQs. The same broken message lands in the DLQ four times. Operations confusion.

## Where this lives in the iFlow XML

Exception Subprocess is a `<bpmn2:subProcess>` element with `<bpmn2:property name="activityType" value="ExceptionSubprocess"/>`. Inside it: the same Camel-route DSL as the main Integration Process. The Router is `<bpmn2:exclusiveGateway>`; End Throw is `<bpmn2:endEvent>` with `<bpmn2:errorEventDefinition/>`; regular End is `<bpmn2:endEvent>` without it.
