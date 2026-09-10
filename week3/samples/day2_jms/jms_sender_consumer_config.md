# JMS Sender adapter — consumer side (queue → iFlow)

The **consumer** iFlow starts with a **JMS sender** adapter (terminology: the iFlow is *being sent* messages by the broker). The consumer iFlow is **separate** from the producer — different artifact, different deployment, different runtime.

## Where it sits

```
JMS sender (poll) ──► Request-Reply + HTTP receiver (downstream) ──► End
        │
        ├─── Exception Subprocess (Retry/Bypass router) ──► JMS receiver (DLQ) or rethrow
        │
        └─── roi.orderhub.outbound.<your_initials>   (consumed from)
             roi.orderhub.dlq.<your_initials>         (produced to on Bypass)
```

## Adapter configuration

| Property | Lab value | Why |
|---|---|---|
| Queue Name | `roi.orderhub.outbound.<your_initials>` | Same queue the producer writes to |
| Concurrent Processes | `1` | Trainee default. Production typically `2–4`. Higher only if downstream can absorb |
| Retry Interval | `60` (seconds) | Sane starting backoff for HTTP downstreams. Never `1` — see Common failures |
| Exponential Backoff | `Yes` | Doubles each retry: 60s, 120s, 240s — gives the downstream room to recover |
| Maximum Retry Interval | `3600` (seconds) | Caps how far exponential backoff can grow |
| Dead-Letter Queue (Connection tab) | `checked` | A safety net, not a real DLQ — see below |
| Access Type | `Non-Exclusive` | Set to `Exclusive` only for ordering or rate-limit constraints (§6). Caps throughput at one worker, ignoring Concurrent Processes |
| Lock Timeout | `300` (seconds) | Time a worker holds a message before broker reclaims it for retry. Must exceed worst-case processing time |

**There's no "Number of Retries" field.** The **Dead-Letter Queue** field *does* exist — but it's a checkbox with no name, and what it does is much blunter than the name implies: a message whose retries exhaust it gets marked `Blocked` in the *same* source queue, with no automatic reprocessing. It isn't limited to node crashes — any exhausted-retry message ends up there. Building a real, separate, reprocessable DLQ is something you do yourself — see "DLQ wiring" below.

## What the consumer iFlow actually does per message

1. JMS broker hands a message to a worker.
2. Worker starts a new iFlow run — `Monitor → Message Processing` shows it as a separate run from the producer.
3. Request-Reply step calls the downstream OAuth2 API (same `oauth2_<initials>_orderhub_downstream` credential from Day 3.1).
4. On HTTP 2xx → End → JMS acks → message removed from queue.
5. On exception → Exception Subprocess runs → see `exception_subprocess_wiring.md`.

## Concurrent Processes — choosing the number

| Value | When |
|---|---|
| `1` | Default for labs. Single-worker drain. Predictable, easy to debug. Throughput = 1 message at a time |
| `2`–`4` | Production sweet spot for most downstreams. Workers parallelise the drain. Confirm downstream can handle the load |
| `5`+ | Only when the downstream is high-throughput and you have measured queue-depth growth at lower values |
| Access Type = `Exclusive` (Concurrent Processes becomes irrelevant) | Strict single-threaded drain across the entire runtime (multi-worker tenants) — needed for ordered or rate-limited processing |

**Watch out:** the `Concurrent Processes` knob multiplies *per worker*. On a 3-worker production runtime with Concurrent Processes = `2`, you can have up to 6 messages in flight. The 150-transaction tenant limit (§2) is the ceiling.

## DLQ wiring — the real DLQ vs. the adapter's safety net

Two genuinely different mechanisms, and it matters which one a message ends up in:

- **The adapter's `Blocked` state** (Dead-Letter Queue checkbox) — same source queue, no name, no automatic reprocessing. A message lands here only if it exhausts JMS's own indefinite retry *and nothing catches it first*. There's no workflow around it: an operator has to manually retry-in-place or delete it from the cockpit.
- **The real DLQ** (`roi.orderhub.dlq.<your_initials>`) — a genuinely separate queue you create, populated only by the Exception Subprocess's *Bypass* branch, routing there explicitly via a *JMS receiver* adapter pointing at it, then completing normally (Message End Event). This is reprocessable: inspect it, fix the root cause, move messages back on purpose.

Which one a message ends up in isn't about how many times it's failed — it's decided immediately, from the *nature* of the failure, by the categorization script (§9, `roiam_categorizeError.groovy`):

- **Permanent failure** (HTTP 400/401/403/422, schema validation failure) — route to the real DLQ on the very first attempt. It was never going to succeed; don't wait to find that out.
- **Transient failure** (5xx, timeout, connection issue) — rethrow, let native retry keep trying indefinitely. If it happens to never recover, ending up `Blocked` is an acceptable outcome for that case — you were right to give it a chance.

## Common configuration mistakes

| Wrong | Symptom | Fix |
|---|---|---|
| Categorization script mis-classifies a permanent error as transient | Message retries indefinitely instead of reaching the real DLQ on attempt one, eventually goes `Blocked` in the source queue with no automatic reprocessing | Fix the classification — permanent failures route to the DLQ immediately, not after some number of retries |
| Retry Interval = `1` (second) | Retry storm — hammers a recovering downstream and re-fails | Minimum `60` for HTTP. Exponential backoff on |
| Concurrent Processes = `4` + Access Type = `Exclusive` | Throughput is `1` (Exclusive overrides regardless of worker count or Concurrent Processes), but the config implies 4 — confuses ops | Pick one model deliberately |
| Lock Timeout = `60` for an iFlow that sometimes takes 90s | Broker reclaims a still-in-flight message → duplicate processing | Lock Timeout > worst-case processing time. Default 300s is generally safe |
| No Exception Subprocess | Failures categorized by JMS as "delivery failure" only — no diagnostic logging, no Retry/Bypass | Always attach an Exception Subprocess. Always |
