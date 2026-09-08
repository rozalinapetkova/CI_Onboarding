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
| Number of Retries | `3` | After 3 failed deliveries, message moves to DLQ |
| Retry Interval | `60` (seconds) | Sane starting backoff for HTTP downstreams. Never `1` — see Common failures |
| Exponential Backoff | `Yes` | Doubles each retry: 60s, 120s, 240s — gives the downstream room to recover |
| Dead-Letter Queue | `Enabled` | Always. Without this, a failing message blocks/pollutes the source queue |
| Dead-Letter Queue Name | `roi.orderhub.dlq.<your_initials>` | Explicit. Never rely on a broker-auto-generated DLQ name |
| Exclusive Consumer | `No` | Set `Yes` only for ordering or rate-limit constraints (§6). Caps throughput at one worker |
| Lock Timeout | `300` (seconds) | Time a worker holds a message before broker reclaims it for retry. Must exceed worst-case processing time |

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
| `1` + Exclusive Consumer = `Yes` | Strict single-threaded drain across the entire runtime (multi-worker tenants) — needed for ordered or rate-limited processing |

**Watch out:** the `Concurrent Processes` knob multiplies *per worker*. On a 3-worker production runtime with Concurrent Processes = `2`, you can have up to 6 messages in flight. The 150-transaction tenant limit (§2) is the ceiling.

## DLQ wiring — two paths to the DLQ

A message reaches the DLQ either:

1. **Automatically** — JMS retries exhausted (3 attempts). The adapter moves it to `Dead-Letter Queue Name`.
2. **Explicitly** — Bypass-class error categorization (§9, see `roiam_categorizeError.groovy`). The exception subprocess routes to the DLQ via a *JMS receiver* adapter pointing at `roi.orderhub.dlq.<your_initials>`, then completes successfully — JMS removes the message from the source queue without using a retry slot.

Both end up in the same DLQ. The difference: Bypass is intentional and immediate; automatic-after-retries is wasted cycles for permanent failures.

## Common configuration mistakes

| Wrong | Symptom | Fix |
|---|---|---|
| DLQ Name left blank | After 3 retries, message vanishes (or auto-DLQ name `<queue>.dlq` you don't monitor) | Always set DLQ Name explicitly |
| Retry Interval = `1` (second) | Retry storm — hammers a recovering downstream and re-fails | Minimum `60` for HTTP. Exponential backoff on |
| Concurrent Processes = `4` + Exclusive Consumer = `Yes` | Throughput is `1` (Exclusive overrides), but the config implies 4 — confuses ops | Pick one model deliberately |
| Lock Timeout = `60` for an iFlow that sometimes takes 90s | Broker reclaims a still-in-flight message → duplicate processing | Lock Timeout > worst-case processing time. Default 300s is generally safe |
| No Exception Subprocess | Failures categorized by JMS as "delivery failure" only — no diagnostic logging, no Retry/Bypass | Always attach an Exception Subprocess. Always |
