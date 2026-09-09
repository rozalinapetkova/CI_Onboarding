# Day 4.4 — Error Handling End-to-End

> **Goal of the day.** Add a complete error strategy to the Resilient Order Hub: an Exception Subprocess that captures context, a structured DLQ for poison messages, retry policies that distinguish transient from permanent failures, idempotent replay tooling, and an Alert Notification policy that surfaces problems to humans without crying wolf. By end of day, the Order Hub fails gracefully — and tells you about it.

## 1. Why this is the hardest day of the week

You can ship an iFlow without monitoring (Day 4.1 fixes that), without transports (Day 4.2 fixes that), even without event subscriptions (Day 4.3 added one). You cannot ship an iFlow without error handling. The first 3am page comes from a missing error path, not a missing feature.

Hard parts:
- Distinguishing **transient** errors (retry) from **poison** messages (don't retry, escalate).
- Capturing enough context at failure time that the on-call engineer can diagnose without reproducing.
- Avoiding the alerting equivalent of "boy who cried wolf" — if every error pages, on-call ignores all alerts within a week.
- Making replay safe — the dead message can be replayed without double-processing.

Today wires the rest of the week's pieces (correlation, MessageLog, JMS DLQ from Week 3, Alert Notification from Day 4.1) into one cohesive strategy.

## 2. Error categories you must distinguish

Project taxonomy:

| Category | Examples | Behavior |
|---|---|---|
| **Transient** | OAuth token expired (no auto-refresh on this receiver); network blip; downstream 502/503; JMS broker connection drop | Retry with backoff. Eventually escalate if it persists. |
| **Poison** | Malformed JSON; schema validation failure; missing required field; PD parameter not found | **Do not retry.** Send straight to DLQ + alert. |
| **Business** | Order rejected by OMS for "credit hold"; duplicate orderId on a non-idempotent path | Routed to a separate "rejected" queue or callback flow. Not a "failure" in monitoring sense — but logged. |
| **Configuration** | Wrong receiver URL; missing Security Material; missing PD parameter | Loud Failed status, alert immediately. *Should* have been caught at deploy time. |
| **Runtime** | Tenant restart (Abandoned status); out-of-memory (rare on this plan); time-out | Alert; usually only operations can fix. |

The strategy *follows* the category. Don't apply one rule to all errors.

## 3. Exception Subprocesses — what they catch, what they don't

An **Exception Subprocess** is a special pool inside the iFlow that runs *only when an exception is raised in the main process*. It's the equivalent of `try/catch` at the iFlow boundary.

Its constraints (the bit that surprises everyone):

| Constraint | Implication |
|---|---|
| One Exception Subprocess per Integration Process pool | Multiple pools (e.g., main + Local Integration Process) need their own subprocesses. |
| It runs in the *same* transaction as the main flow | Body, headers, and properties are visible at failure time. |
| It cannot suppress the failure for upstream callers | The MPL still ends up Failed unless you explicitly route the subprocess back to a successful end. |
| It cannot retry the original step | Retries belong on the JMS / AMQP / SFTP adapter or on a separate iFlow design. |
| Sub-flows (Local Integration Process) inherit handling — but only if you don't have a subprocess inside them | If both have subprocesses, the inner wins. |
| **JMS consumer iFlows** have their own retry policy that runs *before* the subprocess | The subprocess sees the failure only after retries are exhausted. |

Use the Exception Subprocess for:
- Capturing context (headers, properties, body snippet) into a `MessageLog` attachment.
- Routing the failed message to a DLQ.
- Emitting an Alert Notification event.
- Setting human-readable properties on the MPL so search-by-error-class works.

Do not use it for:
- Retrying — wrong tool. Retry on the adapter.
- Recovering — if you can recover, the main flow shouldn't have failed in the first place. Restructure.
- "Hiding" failures from monitoring — that's the HTTP error suppression anti-pattern.

## 4. The Exception Subprocess template

This is what every iFlow on the team looks like at the subprocess level:

```
[Error Start Event]
        |
        v
[Script: roiam_captureErrorContext]   <- gather error info into properties + MessageLog
        |
        v
[Router: classify error]              <- by exception class / property
   |              |              |
   poison      transient      configuration
   v              v              v
   [DLQ]      [retry queue]  [alert + DLQ]
   v              v              v
   [Alert]     [Alert]       [Alert]
   v              v              v
   [Error End]
```

The key bits:

1. **Capture-context script** runs first, every time, no exceptions. It sets up the structured information that everything downstream uses. Don't put logic before it.
2. **Classification** is a Router based on properties the capture script populated.
3. **DLQ writes** are JMS sends to a structured envelope queue — see section 6.
4. **Alert emits** go to Alert Notification with a category like `roi.orderhub.dlq` or `roi.orderhub.poison`.
5. **Error End** — the iFlow ends with status Failed (or Escalated, depending on configuration). Don't route to a Successful End to "hide" the error.

## 5. The capture-context script — `roiam_captureErrorContext.groovy`

```groovy
import com.sap.it.script.v2.api.Message;
import groovy.json.JsonOutput;
import java.io.Reader;

def Message processData(Message message) {
    def headers = message.getHeaders();
    def properties = message.getProperties();

    Throwable cause = (Throwable) properties.get("CamelExceptionCaught");
    String errorClass = (cause != null) ? cause.getClass().getName() : "unknown";
    String errorMessage = (cause != null) ? cause.getMessage() : "no exception captured";
    String failingStep = properties.get("CamelFailureRouteId") as String;

    String correlationId = headers.get("correlationId") as String;
    String orderId = headers.get("orderId") as String;
    String eventId = headers.get("ce-id") as String;

    String classification = classify(cause);

    message.setProperty("errorClass", errorClass);
    message.setProperty("errorMessage", errorMessage);
    message.setProperty("failingStep", failingStep);
    message.setProperty("errorClassification", classification);

    String snapshot = JsonOutput.prettyPrint(JsonOutput.toJson([
        correlationId : correlationId,
        orderId       : orderId,
        eventId       : eventId,
        errorClass    : errorClass,
        errorMessage  : errorMessage,
        failingStep   : failingStep,
        classification: classification,
        headers       : headers.collectEntries { k, v -> [k, v?.toString()] }
    ]));

    def messageLog = messageLogFactory.getMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("errorClass", errorClass);
        messageLog.setStringProperty("errorClassification", classification);
        messageLog.setStringProperty("failingStep", failingStep ?: "unknown");
        messageLog.addAttachmentAsString("error-snapshot", snapshot, "application/json");
    }

    return message;
}

String classify(Throwable cause) {
    if (cause == null) {
        return "unknown";
    }
    String name = cause.getClass().getName();
    if (name.contains("JsonException") || name.contains("XmlException") || name.contains("SAXParseException")) {
        return "poison";
    }
    if (name.contains("javax.net") || name.contains("ConnectException") || name.contains("SocketTimeout")) {
        return "transient";
    }
    if (name.contains("PartnerDirectory") || name.contains("SecurityMaterial")) {
        return "configuration";
    }
    if (cause.getMessage() != null && cause.getMessage().toLowerCase().contains("credit hold")) {
        return "business";
    }
    return "unknown";
}
```

Save under `scripts/collections/resilientOrderHub/roiam_captureErrorContext.groovy`. Inside the iFlow project, `script/v2/`. Upload via Script step dialog, then click *Upgrade* (top-right).

Notes:

- `CamelExceptionCaught` and `CamelFailureRouteId` are runtime properties Camel sets on the exchange when an exception is in flight — read but do not modify them.
- The classification is heuristic, not exhaustive. Tune it based on what you see in production. Start with the categories that fire monthly; add more as new failure modes appear.
- Don't include the entire body in the snapshot — for a 30 MB payload it's both useless and a log-store cost. Take a fixed-size head if you need a body sample, or attach the body as a separate attachment under a debug flag.

## 6. Dead Letter Queues — structured, not raw

Project rule: **DLQs hold structured envelopes, not raw failed payloads.** Future you (and your replay tool) needs more than the body to fix the issue.

The envelope format on the JMS DLQ message:

```json
{
  "correlationId":     "uuid",
  "orderId":           "ORD-12345",
  "eventId":           "evt-9988",
  "originalEntryPoint":"http|amqp",
  "errorClass":        "...",
  "errorMessage":      "...",
  "errorClassification":"poison|transient|configuration|business",
  "failingStep":       "Receiver.OMS.Send",
  "failedAt":          "2026-06-23T14:21:08Z",
  "originalHeaders":   { ... },
  "originalBody":      "<base64 or string>"
}
```

Wrapping like this gives the replay tool everything it needs:

- `correlationId` to dedup across replay attempts.
- `originalEntryPoint` to send the message back through the right path.
- Classification so the replay tool can refuse to replay poison messages without manual override.
- `originalHeaders` + `originalBody` to reconstruct the input.

The DLQ is itself a JMS queue (Week 3 design): `roi.orderhub.dlq`. There's also a *retry* queue (`roi.orderhub.retry`) for transient errors that should be retried via a scheduled iFlow rather than blocking the main consumer — covered in section 8.

## 7. JMS retry policy — what's on the adapter, what's on you

JMS consumer iFlows have a **maximum redelivery** setting on the JMS sender adapter:

| Setting | Recommendation for Order Hub |
|---|---|
| Retry Interval (initial) | 30 seconds |
| Maximum Redelivery Attempts | 3 |
| Exponential Backoff Multiplier | 2.0 |
| Maximum Backoff | 5 minutes |
| Dead Message Queue | `roi.orderhub.dlq` (yes, the JMS adapter knows how to write to a DLQ on its own) |

That handles transient failures. After 3 retries with backoff, the message lands in `roi.orderhub.dlq` automatically. The Exception Subprocess **also** sees the failure on each attempt — but you should classify and skip the alert on retries 1-3, only firing the alert when redelivery is exhausted (`Escalated` MPL status).

How: in the capture-context script, check `properties.get("CamelRedeliveryCounter")` against the configured max. If less than max, classify as "transient-retrying" and *skip* the alert emit; the retry will happen automatically. Only when counter >= max should the script route to alert + DLQ-with-envelope.

## 8. The retry queue — a separate path for "try again later"

Some transient failures don't resolve in 5 minutes. OAuth provider down for an hour; downstream system in maintenance window. For those, the JMS adapter's automatic retry exhausts and the message lands in DLQ — but the message is *not* poison; it just needs a longer retry horizon.

Pattern: a separate **retry queue** (`roi.orderhub.retry`) that a scheduled iFlow drains every 15 minutes back into the main JMS queue. Cap retry-queue retries (e.g., 10 cycles ≈ 2.5 hours) before final escalation to a human-attention queue.

The Exception Subprocess routes:
- `errorClassification = "transient"` AND `redeliveryCounter < maxRedeliveryCounter` → let JMS retry, no envelope, no alert.
- `errorClassification = "transient"` AND `redeliveryCounter >= maxRedeliveryCounter` → wrap in envelope, send to `roi.orderhub.retry`, alert at lower severity.
- `errorClassification = "poison"` → wrap in envelope, send to `roi.orderhub.dlq`, alert at higher severity.
- `errorClassification = "configuration"` → wrap in envelope, send to `roi.orderhub.dlq`, alert at *highest* severity (this is "the iFlow is misconfigured", a deploy-time problem).

For the lab, implement the simpler form: transient → retry queue, poison/configuration → DLQ, business → reject queue. Tune severities later.

## 9. Alert Notification — the categories

Building on Day 4.1's category naming:

| Category | When emitted | Severity | Action |
|---|---|---|---|
| `roi.orderhub.dlq` | Message landed on DLQ (poison or configuration) | Sev-2 | Email + MS Teams |
| `roi.orderhub.retry-stuck` | Message stuck in retry queue past N cycles | Sev-3 | Email |
| `roi.orderhub.subscription-down` | Event Mesh subscription disconnected | Sev-2 | Email + MS Teams |
| `roi.orderhub.poison-burst` | More than 5 poison messages in 1 hour | Sev-1 | Email + MS Teams + on-call rotation |
| `roi.orderhub.transport` | CTM-related lifecycle event | Sev-4 | Email only |

The severities are made up for this project; align with your operations team's actual scheme. The principle: **fewer Sev-1s than you think you want**. If everything is Sev-1, nothing is.

Emit pattern from Groovy — there's a script API but the simpler approach is to send a structured event to an HTTP receiver that ANS exposes:

```groovy
import com.sap.it.script.v2.api.Message;
import groovy.json.JsonOutput;

def Message processData(Message message) {
    def headers = message.getHeaders();
    def properties = message.getProperties();

    String correlationId = headers.get("correlationId") as String;
    String classification = properties.get("errorClassification") as String;

    String category = "roi.orderhub.dlq";
    if (classification == "transient") {
        category = "roi.orderhub.retry-stuck";
    } else if (classification == "configuration") {
        category = "roi.orderhub.dlq";
    }

    Map alertEvent = [
        eventType        : "exception",
        category         : category,
        severity         : (classification == "configuration") ? "FATAL" : "ERROR",
        subject          : "Resilient Order Hub - " + (classification ?: "unknown") + " failure",
        body             : (properties.get("errorMessage") as String) ?: "no message",
        tags             : [
            correlationId: correlationId,
            errorClass   : properties.get("errorClass"),
            failingStep  : properties.get("failingStep"),
            iflow        : "roi_ResilientOrderHub"
        ]
    ];

    message.setHeader("Content-Type", "application/json");
    message.setBody(JsonOutput.toJson(alertEvent));

    def messageLog = messageLogFactory.getMessageLog(message);
    if (messageLog != null) {
        messageLog.addAttachmentAsString("alert-event", JsonOutput.prettyPrint(JsonOutput.toJson(alertEvent)), "application/json");
    }

    return message;
}
```

Save as `roiam_buildAlertEvent.groovy`. The next step is an HTTP receiver call to the ANS REST endpoint (URL externalized as `AlertNotificationProducerUrl`, OAuth credentials in Security Material). The receiver should *not* throw on failure — if alerting fails, you don't want to compound the original error. Set "Throw Exception on Failure" off and log a `MessageLog` attachment if the alert emit returns non-2xx.

## 10. Idempotency replay — making DLQ entries safe to re-run

When the root cause of a poison batch is fixed (bad PD config corrected, schema mapping updated), operations replays the DLQ entries. Replay must be safe.

The replay path:

1. A small **replay iFlow** drains `roi.orderhub.dlq` on demand (manual trigger, not scheduled).
2. For each envelope, it extracts `originalEntryPoint`, `originalBody`, `originalHeaders`.
3. It re-injects into the main entry point — same JMS queue the HTTP and AMQP paths feed into.
4. Because the main consumer **already deduplicates by `orderId` (HTTP) and `ce-id` (AMQP)** (Week 3 + Day 4.3), any message that *did* succeed before crashing won't double-process.
5. The replay iFlow logs each replay attempt with the original `correlationId` so the audit trail connects "first failed at T1, replayed at T2, succeeded at T2".

For the lab, you don't need to build the full replay iFlow — but the design must support it. The envelope shape from section 6 is what makes that future iFlow possible.

## 11. Wiring it all together — the Order Hub final shape

```
                      [HTTP sender] -----+
                                         |
                      [AMQP sender] -----+
                                         |
                                         v
                           [roiam_setCorrelationId]
                                         |
                                         v
                           [Idempotency Data Store check]
                                         |
                                         v
                           [Canonical XML mapping]
                                         |
                                         v
                                   [JMS Producer]
                                         |
                                         v
                                  [JMS Consumer iFlow]
                                         |
              +--------+-----------------+-----------------+--------+
              |        |                 |                 |        |
              v        v                 v                 v        v
            (any step's exception bubbles to the Exception Subprocess)
              |
              v
           [roiam_captureErrorContext]
              |
              v
       [Router: classification]
        |       |       |       |
   transient poison  cfg    business
   /retrying  v      v      v
        |    [DLQ envelope]  [reject queue]
        |    [Alert: dlq]    [no alert; log only]
        v
   [retry queue]
   [Alert: retry-stuck]
              |
              v
        [Error End]
```

Three separate consumers (transient, poison/config, business) each ending appropriately. One subprocess; multiple paths inside.

---

## Hands-on lab — Add full error strategy to the Order Hub

> Time: ~3 hours (this is the longest lab of the week — budget accordingly). Goal: the Order Hub fails gracefully on every failure mode, classifies, alerts at the right severity, and supports safe replay.

### Setup

- Order Hub from Day 4.3 — instrumented (4.1), transported (4.2), event-subscribed (4.3).
- JMS queues from Week 3: `roi.orderhub.queue`, `roi.orderhub.dlq`. Add `roi.orderhub.retry`, `roi.orderhub.rejects`.
- Alert Notification subscriptions wired by trainer, one per category in section 9.
- ANS HTTP producer URL in tenant destinations as `AlertNotificationProducer`.

### Steps

1. **Add an Exception Subprocess** to the main Integration Process pool. *Right-click pool → Add Exception Subprocess*. The Error Start Event appears.
2. **First step in the subprocess: `roiam_captureErrorContext.groovy`** (section 5). Save under `scripts/collections/resilientOrderHub/`, place inside the iFlow under `script/v2/`, upload via Script step dialog, then click *Upgrade* (top-right).
3. **Add a Router** after the capture script. Branches on `${property.errorClassification}`:
   - `poison`
   - `transient` AND `${property.CamelRedeliveryCounter} >= 3` → "transient-exhausted"
   - `configuration`
   - `business`
   - default
4. **Wire each branch** to its destination:
   - `poison`, `configuration`, default → "DLQ envelope" path → JMS Producer to `roi.orderhub.dlq` → Alert emit (`roi.orderhub.dlq`).
   - `transient-exhausted` → "Retry envelope" path → JMS Producer to `roi.orderhub.retry` → Alert emit (`roi.orderhub.retry-stuck`).
   - `business` → JMS Producer to `roi.orderhub.rejects` → no alert.
5. **Build the envelope.** A Content Modifier or Groovy script (`roiam_buildDlqEnvelope.groovy`) constructs the JSON envelope from section 6 from headers + properties + body. Same script style as the rest of the iFlow.
6. **Build and emit the alert.** `roiam_buildAlertEvent.groovy` from section 9 → HTTP receiver to `AlertNotificationProducer` (externalized URL). Tick *Throw Exception on Failure: off* — alerting failure must not compound the underlying failure.
7. **Configure JMS retry on the consumer side.** Open the JMS sender adapter on the consumer iFlow. Set Maximum Redelivery to 3, exponential backoff 2.0, initial interval 30 seconds, max backoff 5 minutes. Set the adapter's Dead Message Queue to `roi.orderhub.dlq` (this is the *fallback* DLQ the JMS layer writes to if the iFlow itself doesn't catch the exception — should rarely fire now that the subprocess catches everything).
8. **Add an idempotency-on-replay note** to the project. Document in `changelog/roi_ResilientOrderHub/<YYYY-MM-DD>_error_strategy.txt`: the envelope shape, why we deduplicate on the main consumer (callback to Week 3 idempotency), and the planned replay iFlow design (don't build the replay iFlow this week).
9. **Provoke the categories** end-to-end:
   - **Poison:** send a malformed JSON payload via HTTP. Verify MPL Failed → Exception Subprocess runs → `error-snapshot` attachment → DLQ envelope visible on `roi.orderhub.dlq` → email + MS Teams alert arrived with category `roi.orderhub.dlq`.
   - **Transient:** undeploy the OAuth receiver target. Send a happy-path payload. Verify three retries (Retry status), then Escalated → "transient-exhausted" branch → message on `roi.orderhub.retry` → alert with category `roi.orderhub.retry-stuck`.
   - **Configuration:** rename the PD parameter from Day 4.3 (or set wrong `roiam_routing_destination` header). Send an event. Verify Failed → DLQ → high-severity alert.
   - **Business:** the trainer's mock OMS returns 422 with body containing "credit hold". Verify the *business* branch fires → reject queue → no alert.
10. **Replay drill** (no full replay iFlow yet — do it manually). Pick a DLQ envelope. Confirm by inspection that:
    - `originalEntryPoint` is set.
    - `originalBody` is intact.
    - `correlationId` is present.
    - The classification is correct.
    Verbally walk through how a replay iFlow would re-inject the message and rely on the existing idempotency guard to prevent double-processing.
11. **Final changelog entry.** Write the day's changes into `changelog/roi_ResilientOrderHub/<YYYY-MM-DD>_error_strategy.txt`. Include the four scenarios you provoked, the alert categories you configured, and the JMS retry settings.

### Failure cases to provoke

- **Exception Subprocess hangs.** Put a long-running step in the subprocess (sleep 30s). Send 50 messages that fail. Watch the subprocess become a bottleneck. *Lesson:* the subprocess is on the message's critical path — keep it fast.
- **Alert emit failure compounds the error.** Take down the ANS endpoint while the iFlow is running. Send a poison message → original error captured fine, alert emit fails, but the iFlow doesn't double-fail because we set "Throw Exception on Failure: off" on the alert receiver. *Lesson:* alerting must be best-effort, not blocking.
- **Misclassified error.** A new exception type (say, a TLS handshake failure) defaults to "unknown" classification. Show that "unknown" routes to DLQ + alert (safe default), and decide whether to add a new branch or refine `classify()`. *Lesson:* always have a sensible default; refine over time.
- **Alert flood.** Send 100 poison messages in a row. Email inbox floods. *Lesson:* this is why the `roi.orderhub.poison-burst` category exists in section 9 — coalesce on burst rather than per-message.
- **Replay double-processing.** Disable the idempotency guard (temporarily). Replay an envelope from DLQ. Observe the OMS receives the order *twice*. Re-enable the guard. *Lesson:* replay safety depends on consumer idempotency. The DLQ envelope alone doesn't prevent duplicates — it enables replay; the consumer prevents duplicates.

---

## Reference card excerpt — Day 4.4

- **Error categories:** transient, poison, business, configuration, runtime. Strategy follows category — don't apply one rule to all.
- **Exception Subprocess** is `try/catch` at the iFlow level. One per pool. Cannot retry the original step (retry is on the adapter).
- **Standard subprocess shape:** capture-context script → router by classification → DLQ/retry/reject + alert → Error End.
- **`roiam_captureErrorContext.groovy`** reads `CamelExceptionCaught` and `CamelFailureRouteId`, classifies, writes `error-snapshot` MessageLog attachment, sets searchable properties.
- **DLQ envelopes** are structured (correlationId, originalEntryPoint, originalHeaders, originalBody, errorClass, classification, failedAt). Raw failed payloads in DLQ are useless.
- **JMS retry on the adapter:** 3 attempts, exponential backoff (×2), initial 30s, max 5 min. After exhaustion, route to retry queue or DLQ depending on classification.
- **Retry queue** for "try again later" transient errors with longer horizon. A scheduled drain iFlow re-injects every 15 min, capped at ~10 cycles before final escalation.
- **Alert Notification severities:** fewer Sev-1s than you think. `roi.orderhub.dlq`, `roi.orderhub.retry-stuck`, `roi.orderhub.poison-burst`, `roi.orderhub.subscription-down`, `roi.orderhub.transport`.
- **Alert emit must not block.** "Throw Exception on Failure: off" on the alert receiver. Alerting failures get logged but don't compound the underlying error.
- **Replay safety** depends on consumer idempotency (Week 3 Data Store guard). DLQ envelope shape enables replay; the guard prevents double-processing.
- **Don't hide errors in HTTP receivers** to silence alerting. "Completed" with a hidden 500 is worse than Failed — it lies to operations.
