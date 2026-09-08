# Day 3.2 — JMS Messaging: Producer / Queue / Consumer

> **Goal of the day.** Decouple the Order Hub. By end of day, your iFlow returns **202 Accepted** to the caller as soon as the canonical XML is enqueued, a separate consumer iFlow drains the queue and calls the downstream OAuth2 API, transient failures are retried, permanent failures land in a Dead Letter Queue, and you can explain the difference between Retry-category and Bypass-category errors without notes.

## 1. Why JMS exists in the iFlow toolbox

Synchronous HTTP chains are the simplest thing that works — until they don't:

- The downstream is briefly down → the caller's request times out and bubbles a 5xx back to the user.
- A traffic spike puts 200 messages/second on an API rated for 50/second → cascading timeouts.
- One message takes 45 seconds to process → the caller is held hostage for 45 seconds.
- The downstream needs maintenance → the producer can't be deployed during the window.

JMS solves all of these with a **persistent broker between producer and consumer** that:

- **Decouples lifecycles** — producer and consumer can be redeployed independently.
- **Smooths traffic** — the queue absorbs bursts; the consumer drains at its own pace.
- **Retries automatically** — failed deliveries are retried with backoff before going to DLQ.
- **Isolates failures** — a slow/broken consumer doesn't time out the producer's caller.
- **Doesn't count for metering** — JMS hops are free (per CURRICULUM.md note in Week 1).

The cost: one more moving part to monitor, eventual-consistency semantics for the caller, and a real DLQ to operate.

## 2. JMS on Cloud Integration — the broker behind the curtain

SAP CI ships a **managed JMS broker** as part of the tenant. You don't install it. On the **Standard plan** you get:

- **30 queues** maximum.
- **9.3 GB total queue storage**.
- **150 transactions/consumers/providers** — the limit on concurrent JMS adapter slots across the tenant.

There is no separate broker UI — queues are created **lazily** when an adapter references them, and you manage them via *Monitor → Manage Stores → Message Queues*.

**Naming convention** the team uses on this tenant: `roi.<flow>.<purpose>` lower-case, dot-separated. For the lab:

- `roi.orderhub.outbound` — the main queue.
- `roi.orderhub.dlq` — the dead-letter queue for poison messages.

(Your actual lab queue names get your initials suffix to avoid clashes — `roi.orderhub.outbound.<your_initials>`, `roi.orderhub.dlq.<your_initials>` — see Section 11.)

## 3. The producer/consumer split

A JMS-decoupled iFlow is **two iFlows**, not one with a JMS step in the middle:

```
Producer iFlow:   HTTPS sender ──► Content Modifier ──► JMS receiver
                                                          │
                                                          ▼
                                                   roi.orderhub.outbound
                                                          │
                                                          ▼
Consumer iFlow:   JMS sender ──► Request-Reply (HTTP receiver) ──► End
```

Why two iFlows? Because **JMS sender** is the *consuming* side — an iFlow with a JMS sender adapter polls the queue and starts a new run for each message. You can't have a "producer + consumer in one iFlow" because the lifecycle of producing a message and consuming it are independent by definition.

This is the **single biggest mental adjustment** going from sync to async: you stop thinking about "the iFlow" and start thinking about "the producer iFlow" and "the consumer iFlow", each deployable independently, monitored independently, version-managed independently.

## 4. Producer side — the JMS receiver adapter

On the **producer** iFlow you drop a **JMS receiver adapter** (the *receiver* terminology is from the iFlow's perspective: the iFlow *sends* to a queue that *receives* the message). Configuration:

| Property | Value | Note |
|---|---|---|
| Queue Name | `roi.orderhub.outbound.<your_initials>` | Created on first deploy |
| Persistence | *Persistent* | Default; messages survive broker restart |
| Compress Message | *No* / *Yes* | Yes for >100KB payloads |
| Encrypt Stored Message | *No* / *Yes* | Yes for sensitive data |
| Expiration Period | *blank* (no expiry) or seconds | Use for self-cleaning queues |
| Priority | 0–9 | Default 4; rarely changed |

After enqueue, the producer iFlow ends. The caller sees **202 Accepted** as soon as the JMS receiver acknowledges the broker's persist. Latency measured in milliseconds.

## 5. Consumer side — the JMS sender adapter

On the **consumer** iFlow the **JMS sender adapter** polls the queue and starts a run per message:

| Property | Value | Note |
|---|---|---|
| Queue Name | `roi.orderhub.outbound.<your_initials>` | Same queue the producer writes to |
| Concurrent Processes | *1* / *2* / *N* | Parallelism — Section 6 |
| Number of Retries | *3* | Then → DLQ |
| Retry Interval | *60 s* / *300 s* | Backoff between retries |
| Exponential Backoff | *Yes* | Doubles each retry |
| Dead-Letter Queue | *Enabled* | Routes to `<queue>.dlq` after retries exhausted |

**Vocabulary you need before Concurrent Processes makes sense:**

- **Worker node** — a physical runtime unit in your tenant's cluster (a JVM running Karaf + Camel). It's shared infrastructure: any worker node can run *any* of your deployed iFlows, not just this one. How many worker nodes you have is a property of how your tenant is sized, not something you configure per iFlow — a production tenant typically has several, a trial tenant usually has one.
- **Worker count** — how many of those worker nodes your tenant currently has. You don't set this on the adapter; it's tenant sizing.
- **Concurrent Processes** — on *this* adapter, how many parallel instances of *this consumer iFlow* a single worker will run at once, each instance picking up a different message from the queue.

So on a 3-worker tenant with Concurrent Processes = `2`: each of the 3 workers independently runs up to 2 simultaneous instances of this consumer iFlow, all pulling from the same queue — up to 6 messages processed at once, total. Full detail on how this interacts with ordering (Access Type) is Section 6.

**Key thing:** the consumer iFlow always has at least one *Exception Subprocess* attached, even at this stage. Without one, transient errors land in the JMS broker's retry mechanism with no visibility into *why*. The exception subprocess runs once per failure attempt, lets you classify the error, and writes a useful `MessageLog` attachment for monitoring (Week 4 deep dive).

## 6. Access Type: Exclusive vs. Non-Exclusive — and how that's different from Concurrent Processes

Two separate dials control parallelism on the JMS sender, and they answer different questions:

- **Access Type** (*Exclusive* / *Non-Exclusive*) — how many **workers** may touch this queue at once.
- **Concurrent Processes** — how many parallel **threads a single worker** runs against it.

"Workers" are a property of the runtime itself — how many worker nodes your tenant is sized with — not something you configure per adapter. A production tenant typically has several; a trial tenant usually has one.

**Non-Exclusive** (the default) lets every worker node compete for messages independently, and each worker can additionally run up to `Concurrent Processes` threads against the queue at once. So the number of messages potentially in flight at the same time is *(worker count) × (Concurrent Processes)* — on a 3-worker tenant with Concurrent Processes = 2, that's up to 6 messages processed simultaneously. Throughput scales with both numbers, but there's no ordering guarantee across any of it.

**Exclusive** collapses all of that to a single consumer across the *entire* tenant, regardless of worker count or what Concurrent Processes is set to — strictly one message at a time, in order. Reasons to use it:

- **Order-sensitive processing** — you cannot have two messages from the same customer processed concurrently.
- **Downstream rate limit** — the target API caps you at 1 RPS and you cannot afford to violate it.
- **State-shared logic** — the consumer maintains a Data Store entry that must be updated atomically.

Set on the JMS sender: *Access Type* = **Exclusive**. Trade-off: throughput is bounded by one worker's capacity, and if one message errors, it blocks every message queued behind it. Do not enable unless you genuinely need it — most cohorts default to enabled and starve their queue under load. And once Access Type is Exclusive, changing Concurrent Processes does nothing — there's only ever one consumer regardless of that number.

## 7. EOIO — Exactly Once In Order

EOIO is a guarantee, not a knob. SAP CI offers EOIO via:

- **SOAP SAP RM** adapter (Week 1 Day 1.3 mention) — 90-day message-ID dedup window.
- **JMS with a serialization key** — messages with the same key are processed strictly in order; different keys can interleave.

For the Order Hub, you'd use a serialization key of `customerId` if "two orders for the same customer must process in arrival order" was a requirement. **For our lab, it isn't** — the canonical Order is independent per `orderId`. Skip EOIO. But know it exists.

## 8. The DLQ — Dead Letter Queue

After **N retries** (default 3), a message that keeps failing is moved to a **Dead Letter Queue**. On SAP CI, the DLQ is a separate queue you reference by name on the JMS sender adapter:

| Without DLQ | With DLQ |
|---|---|
| Failed message stays in the source queue with retry counter, blocks/slows the queue | Failed message moved out of the source queue to `<queue>.dlq` |
| Operations sees the message in the source queue — can't tell if it's "in retry" or "stuck" | Operations sees a clean source queue + a DLQ to inspect/replay/discard |
| No alerting on "permanent failure" | Alert Notification can watch the DLQ depth and page on-call |

**Always enable DLQ on production queues.** Always.

The DLQ is just another queue. To **replay** a DLQ message, you need an iFlow that drains the DLQ and re-enqueues to the source queue (a "retry iFlow"), or you do it manually via the cockpit's *Monitor → Message Queues → Move* feature.

## 9. Error categories — Retry vs. Bypass

This is the project's most opinionated JMS rule, and it's the bit that separates "production-shaped" iFlows from "it works in the demo" iFlows.

When a consumer iFlow fails, the failure is **either**:

- **Retry** — *transient* failure, likely to succeed on a future attempt. Examples: HTTP 502/503/504, connection timeout, downstream maintenance window, OAuth token endpoint briefly unreachable. **Action:** let the JMS retry mechanism do its thing — backoff, retry, eventually DLQ if the storm doesn't pass.
- **Bypass** — *permanent* failure, will **never succeed** no matter how many times you retry. Examples: HTTP 400 (malformed payload), HTTP 401/403 (auth wrong), HTTP 422 (validation rejection), schema-validation failure on the canonical XML. **Action:** route **directly to DLQ** without using the 3 retry attempts. Retrying a 400 is a waste of broker cycles and pollutes monitoring.

Implementation pattern:

1. The exception subprocess on the consumer iFlow inspects the exception and the response code.
2. If transient → it **rethrows** the exception. JMS sees an unhandled error, increments the retry counter, returns the message to the queue.
3. If permanent → it **routes the message to the DLQ explicitly** (e.g. via a JMS receiver adapter inside the exception subprocess pointing at `roi.orderhub.dlq.<your_initials>`), then **swallows** the exception so JMS sees a "successful processing" and removes the message from the source queue.

The categorization logic itself is usually a Groovy script:

```groovy
import com.sap.it.script.v2.api.Message;

def Message processData(Message message) {
    def headers = message.getHeaders();
    def properties = message.getProperties();

    Object exHeader = properties.get("CamelExceptionCaught");
    String exClass = exHeader != null ? exHeader.getClass().getName() : "";
    Integer httpCode = headers.get("CamelHttpResponseCode") as Integer;

    String category = "Retry";
    if (httpCode != null && httpCode >= 400 && httpCode < 500 && httpCode != 408 && httpCode != 429) {
        category = "Bypass";
    }
    if (exClass.contains("ValidationException")) {
        category = "Bypass";
    }

    message.setProperty("errorCategory", category);
    message.setHeader("X-Error-Category", category);

    def messageLog = messageLogFactory.createMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("errorCategory", category);
    }

    return message;
}
```

A Router after this script branches on `${property.errorCategory}` — `Retry` rethrows, `Bypass` routes to the DLQ adapter and ends.

## 10. Queue design strategy

**One queue per business purpose, not per iFlow and not per message type.** The Order Hub has:

- `roi.orderhub.outbound` — canonical orders waiting for downstream delivery.
- `roi.orderhub.dlq` — failed orders waiting for human triage.

You would *not* split into `roi.orderhub.json`, `roi.orderhub.xml`, `roi.orderhub.csv` — by the time the canonical XML hits the queue, the format distinction is gone. You would *not* combine with an unrelated queue (`roi.orderhub.outbound` ≠ `roi.invoice.outbound`) — different consumers, different SLAs, different DLQ semantics.

**Queue depth should normally be near zero.** A consistently non-zero depth means the consumer is slower than the producer — either scale the consumer (add workers, parallel processes) or rate-limit the producer. *Monitor → Message Queues* shows depth.

## 11. Naming, scoping, and resource limits

For the cohort lab, append your initials to avoid clashing with peers:

- `roi.orderhub.outbound.<your_initials>`
- `roi.orderhub.dlq.<your_initials>`

In production: omit the suffix; queues are unique tenant-wide.

Each lab uses 2 queues per trainee × 8 trainees = 16 queues. Plus existing tenant queues = check tenant total against the 30-queue limit on Sunday. If tight, ask the trainer to clean up old test queues before Monday.

---

## Hands-on lab — Split the Order Hub into producer + consumer with DLQ

> Time: ~3 hours. Goal: take yesterday's `roi_<your_initials>_OrderHub` (currently a sync chain ending in a downstream HTTP call) and split it into two iFlows — `roi_<your_initials>_OrderHub` (producer) and `roi_<your_initials>_OrderHubConsumer` (consumer) — connected by `roi.orderhub.outbound.<your_initials>`. Add a DLQ at `roi.orderhub.dlq.<your_initials>` and Retry/Bypass error categorization.

### Setup

- Yesterday's `roi_<your_initials>_OrderHub` deployed and working end-to-end (sync chain).
- Trainer-provisioned downstream API still reachable at `https://<trainer-stub>/orderhub/accept`.
- Queue prefix for your initials: e.g. `roi.orderhub.outbound.ab` for trainee `ab`.

### Steps

1. **Refactor `roi_<your_initials>_OrderHub` to a producer.**
   - Open the iFlow.
   - **Remove** the Request-Reply + HTTP receiver to the downstream API.
   - **Add** a JMS receiver adapter on the End or just before End:
     - Queue Name: `roi.orderhub.outbound.<your_initials>`
     - Persistence: *Persistent*
     - Encrypt Stored Message: *No* (you're not handling secrets in the body for this lab)
   - **Set the response body** in a Content Modifier to:
     ```json
     { "status": "accepted", "orderSequence": "${header.X-Order-Sequence}" }
     ```
     (Note: `X-Order-Sequence` is set by Day 3.4's lab. For today, hardcode it as `ORD-PENDING` or use the `${exchangeId}`.)
   - **Set the response code** to `202` via header `CamelHttpResponseCode = 202`.
   - Save → version → deploy.

2. **Create the consumer iFlow `roi_<your_initials>_OrderHubConsumer`.**
   - New iFlow in the *Training* package.
   - **JMS sender adapter** at the start:
     - Queue Name: `roi.orderhub.outbound.<your_initials>`
     - Concurrent Processes: *1*
     - Number of Retries: *3*
     - Retry Interval: *60 s*
     - Exponential Backoff: *Yes*
     - Dead-Letter Queue: *Enabled*
     - DLQ Name: `roi.orderhub.dlq.<your_initials>`
   - **Request-Reply + HTTP receiver** to the downstream API — same OAuth2 Credential Name (`oauth2_<your_initials>_orderhub_downstream`) as yesterday.
   - **End**.
   - Save → version → deploy.

3. **Test the happy path.**
   ```bash
   curl -X POST "<runtime-url>/http/orderhub/orders/<your-initials>" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{ "orderId": "C-3001", "customer": "Acme GmbH", "totalAmount": 1500 }'
   ```
   - Confirm 202 Accepted from the producer.
   - Open *Monitor → Message Processing* — see the producer run **Completed** instantly.
   - Wait ~2 seconds — see the consumer run **Completed** for the same message (correlated via `correlationId` if you set it; via timing otherwise).
   - Inspect the consumer's HTTP receiver sub-step — should show 200 from the downstream.

4. **Add an Exception Subprocess to the consumer.**
   - On the canvas, drop an *Exception Subprocess* alongside the Integration Process.
   - Inside: a Script step → a Router → two ends.
   - Script step: paste the categorization script from Section 9 above. Save as `roiam_categorizeError.groovy` under `script/v2/`.
   - Router branches on `${property.errorCategory}`:
     - `Retry` → set body to a small error JSON, end (rethrow happens by default — you can also use *End Throw* step to force).
     - `Bypass` → JMS receiver adapter pointing at `roi.orderhub.dlq.<your_initials>` → End.
   - **Important:** for the `Bypass` branch, you want to **swallow** the original exception so JMS treats the message as processed and removes it from the source queue. You do this by NOT throwing from the subprocess — let it complete normally.
   - For the `Retry` branch, **rethrow** so JMS knows to retry. *End Throw* step or `throw new RuntimeException(...)` in a Script.
   - Save → version → deploy.

5. **Provoke a Retry-class failure.**
   - Trainer **briefly stops** the downstream API (or you set `Address` to `https://nonexistent.example.com` temporarily).
   - Send an order. Producer returns 202.
   - Consumer fails. Watch the JMS retry kick in — *Monitor → Message Queues → roi.orderhub.outbound.\<your_initials\> → Messages* shows the message with retry counter incrementing every 60s.
   - Trainer brings the downstream back. Next retry succeeds.
   - Confirm the message is removed from the queue.

6. **Provoke a Bypass-class failure.**
   - Send a deliberately malformed order — e.g. a body of `{ "broken": true }` and trainer's stub returns 400.
   - Consumer's exception subprocess runs once, categorizes as Bypass, routes the message to `roi.orderhub.dlq.<your_initials>`, completes successfully.
   - Confirm the message is in the DLQ via *Monitor → Message Queues*. Confirm the source queue is empty.
   - Critically: confirm there were **NOT** 3 retry attempts. Bypass = direct-to-DLQ.

7. **Replay a DLQ message manually.**
   - In the cockpit: *Monitor → Message Queues → roi.orderhub.dlq.<your_initials> → select message → Move To... → roi.orderhub.outbound.<your_initials>*.
   - Watch the consumer pick it up and (still) fail with the same 400 → goes back to DLQ.
   - Lesson: replay only works when you've fixed the *root cause*. Replaying a malformed message just sends it through the same Bypass path.

### Failure cases to provoke

- **Forget the DLQ name** on the JMS sender → after 3 retries the message is *deleted* (moved to `roi._<source>.dlq` if the broker auto-creates one, or lost). Lesson: always set DLQ Name explicitly.
- **Set Concurrent Processes to 4** then set Access Type to Exclusive → only one consumer actually drains the queue; you've capped throughput at one worker regardless of Concurrent Processes. Watch the queue depth grow.
- **Mis-categorize a 422 as Retry** → 3 retries, all fail with 422, eventual DLQ. Wasted 3 retry cycles on a permanent error. Show the consumer's MPL — three Failed runs for one message. Operations team's nightmare.
- **No exception subprocess at all** → consumer fails opaquely; JMS retries blindly; DLQ messages have no useful diagnostic info.
- **Set Retry Interval to 1 second** → tight retry storm overwhelms the downstream. Always use sane backoff (60s minimum for HTTP downstreams).

---

## Reference card excerpt — Day 3.2

- **JMS = decoupling.** Producer and consumer are *two iFlows*, deployed independently.
- **JMS receiver** = producer side (iFlow → queue). **JMS sender** = consumer side (queue → iFlow).
- **Naming**: `roi.<flow>.<purpose>` lower-case dot-separated. For lab, suffix `<your_initials>`.
- **Standard plan limits**: 30 queues, 9.3 GB, 150 transactions. Check before adding.
- **Always set DLQ Name.** Never leave it default.
- **Retry vs. Bypass** error categorization is mandatory on production consumers. Retry = transient, rethrow. Bypass = permanent, route to DLQ + swallow.
- **EOIO** via JMS serialization key when arrival order matters per partition. Skip otherwise.
- **Access Type = Exclusive** caps throughput at one worker, ignoring Concurrent Processes entirely. Use deliberately, not by default.
- **JMS hops are not metered.** Free in the message count.
- **Queue depth ≈ 0** in steady state. A growing queue = consumer can't keep up.
