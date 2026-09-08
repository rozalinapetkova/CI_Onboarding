# JMS Receiver adapter — producer side (iFlow → queue)

The producer iFlow ends in a **JMS receiver** adapter. The "receiver" terminology is from the iFlow's perspective: the iFlow *sends* the message to the broker, the broker is the *receiver*. This is the side that **persists** the message and returns 202 to the original caller in milliseconds.

## Where it sits

```
HTTPS sender ──► Content Modifier (canonical XML) ──► JMS receiver (enqueue) ──► End
                                                          │
                                                          ▼
                                                  roi.orderhub.outbound.<your_initials>
```

The JMS receiver is the **last** step before End on the producer iFlow. After enqueue, the producer iFlow returns to the HTTPS caller. Response code = `202 Accepted` (set via Content Modifier on the `CamelHttpResponseCode` header before the JMS receiver, or in an inline Content Modifier between JMS receiver and End).

## Adapter configuration

| Property | Lab value | Why |
|---|---|---|
| Queue Name | `roi.orderhub.outbound.<your_initials>` | Naming convention `roi.<flow>.<purpose>.<initials>` (§2 + §11) |
| Persistence | `Persistent` | Default. Messages survive broker restart. Required for any business-meaningful queue |
| Compress Message | `No` | `Yes` only for payloads >100 KB (canonical Order XML stays well under) |
| Encrypt Stored Message | `No` | `Yes` for PII or regulatory payloads — adds tiny CPU cost per enqueue/dequeue |
| Expiration Period | *blank* | Set to seconds only for self-cleaning queues (e.g. cache invalidations); leave blank for business orders |
| Priority | `4` | Default. Different priorities only matter when a single consumer drains a multi-priority queue, which we do not |

## Response wiring — return 202 to the caller

The HTTPS caller wants a status code and a body. Two ways:

**Option A (recommended) — Content Modifier *after* the JMS receiver:**

| Step | Type | Body | Header `CamelHttpResponseCode` |
|---|---|---|---|
| 1 | JMS receiver | (canonical XML enqueued) | — |
| 2 | Content Modifier | `{ "status": "accepted", "orderSequence": "${header.X-Order-Sequence}" }` | `202` |
| 3 | End | — | — |

**Option B — set them in the Content Modifier *before* the JMS receiver:**

| Step | Type | Body | Header `CamelHttpResponseCode` |
|---|---|---|---|
| 1 | Content Modifier | (canonical XML) | — |
| 2 | JMS receiver | (enqueued) | — |
| 3 | Content Modifier | replace body with `{ "status": "accepted" }` | `202` |

Option A is cleaner: the body during enqueue is the canonical XML the consumer will process; the response body to the caller is set afterwards.

## What the caller observes

```
POST /http/orderhub/orders/<initials>   HTTP/1.1
Authorization: Bearer <token>
Content-Type: application/json
{ "orderId": "C-3001", ... }

HTTP/1.1 202 Accepted
Content-Type: application/json
{ "status": "accepted", "orderSequence": "ORD-PENDING" }
```

Latency: typically 50–200 ms — the broker's persist round-trip. Whatever the downstream API's latency is no longer the caller's problem.

## Common configuration mistakes

| Wrong | Symptom | Fix |
|---|---|---|
| Queue Name with uppercase or spaces | Deploy succeeds, broker rejects at runtime: "queue name invalid" | Lower-case, dot-separated only |
| Persistence = Non-Persistent | All messages lost on broker maintenance | Always Persistent for business queues |
| Forgot to set CamelHttpResponseCode | Caller sees 200 (or whatever the previous step left) — looks fine, but breaks downstream expectations | Explicit `CamelHttpResponseCode = 202` |
| JMS receiver wired into the *middle* of the flow with a Request-Reply pattern | Compilation error: JMS receiver is one-way fire-and-forget | Use it only at the end of a branch |
| Queue created in producer but consumer iFlow not yet deployed | Messages pile up immediately; queue depth grows | Deploy consumer first or accept the warmup pile |
