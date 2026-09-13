# JMS retry policy — adapter configuration reference

The JMS adapter's retry is simple: on an unhandled exception, the Exception Subprocess fires (**every** attempt, not once at the end). The subprocess decides — immediately, from the nature of the error, not from how many times it's already failed — whether this is worth retrying at all:

- **Transient** (might succeed on a future attempt) → rethrow. The broker redelivers after a backoff delay. If it never actually recovers, it ends up `Failed`, or `Blocked` if Dead-Letter Queue is enabled (Section "Dead-Letter Queue" below).
- **Permanent** (no number of retries will ever fix it) → route straight to a real DLQ, on this first failure, no waiting.

There's no adapter-level attempt limit and no "try N times then decide it's permanent" logic anywhere — that split is made once, by classification, same as Day 3.2 (`week3/samples/day2_jms/exception_subprocess_wiring.md`).

## Where it's configured

For every JMS Sender (consumer) adapter in the iFlow:

```
Sender (JMS) > Processing tab
├─ Number of Concurrent Processes:  5 (default; tune per throughput)
├─ Retry Interval (s):              60
├─ Exponential Backoff:             Yes
└─ Maximum Retry Interval (s):      3600

Sender (JMS) > Connection tab
└─ Dead-Letter Queue:               checked (see caveat below)
```

**No `Maximum Redelivery` or `Acknowledge Mode` fields exist on this adapter.** The `Dead-Letter Queue` field is available on Non-Exclusive queues: off, a message whose retries exhaust ends up `Failed` in the source queue; on, it's marked `Blocked` instead and released manually from the cockpit. Building a real, separate, reprocessable DLQ is logic you write yourself in the Exception Subprocess's categorization script — deciding Retry vs. Bypass immediately, not by counting attempts.

These fields don't map 1:1 onto the AMQP Sender for Event Mesh either. AMQP has real `Max. Number of Retries` and `Dead Message Queue` fields directly on the queue — a genuinely different (adapter/broker-managed, separate-queue) model from JMS's blunt-checkbox-plus-build-it-yourself one. There's no `Acknowledge Mode` field on either adapter — acknowledgement on both is automatic, tied to whether the iFlow run completed successfully, not a setting you pick. See `amqp_vs_jms_reference.md` (Day 4.3) for the detail.

## Field-by-field

### Retry Interval + Exponential Backoff + Maximum Retry Interval

- **Retry Interval** is the *initial* delay before the first redelivery.
- **Exponential Backoff** doubles each subsequent interval until it hits Maximum Retry Interval.
- Effective backoff schedule with Retry Interval=60s, Maximum Retry Interval=3600s, for a message correctly classified as transient:

| Attempt | Delay before this attempt | Cumulative elapsed |
|---|---|---|
| 1 (first delivery) | 0s | 0s |
| 2 | 60s | 60s |
| 3 | 120s | 180s |
| 4 | 240s | 420s |
| 5 | 480s | 900s (15 min) |
| 6 | 960s | ~1860s (31 min) |
| ... | keeps doubling, capped at 3600s | until retries stop |

Once retries stop, the message ends up `Failed` (or `Blocked`, if Dead-Letter Queue is enabled) — see below.

### Dead-Letter Queue — real one vs. adapter checkbox

**The real one** is just a queue you create and name yourself (e.g. `roi.orderhub.dlq.<initials>`), populated only by your categorization script's Bypass branch routing to it via a JMS receiver adapter, then swallowing (Message End Event), **on the first attempt** — not after any number of retries. There's no name field on the adapter for it.

**The adapter's own `Dead-Letter Queue` checkbox** (Connection tab, Non-Exclusive queues only) marks a message `Blocked` in the *same* source queue once retries exhaust, instead of leaving it `Failed`. It's a status change for the transient-but-never-recovers case, not a replacement for routing permanent failures to your real DLQ immediately.

DLQ naming convention:
```
roi.orderhub.queue       →  roi.orderhub.dlq      (your own queue, your own naming)
roi.orderhub.retry       →  roi.orderhub.retry.dlq
```

Or use a *single shared DLQ*: `roi.orderhub.dlq` (the team's convention) — all DLQ traffic converges there with the envelope's `originalEntryPoint` field telling consumers where the message came from.

### Acknowledgement — automatic, not a setting

There's no acknowledgement-mode dropdown on the JMS Sender. What actually happens: the adapter acknowledges a message to the broker when the iFlow run that consumed it completes successfully (Message End Event, including the swallow-after-DLQ-enqueue path). If the run ends via an Error End Event, no acknowledgement is sent and the broker redelivers. This is effectively always "client acknowledgement" behavior — it's just not a mode you select, same as the AMQP adapter (`amqp_vs_jms_reference.md`).

## The redelivery counter

Every redelivered message carries `SAPJMSRetries` (an integer header, populated only for Non-Exclusive consumers — never available on Exclusive queues), tracking how many times the broker has redelivered it. Useful for observability — an alert on "a transient-classified message has retried an unusually long time" — but it's not part of the Retry/Bypass decision itself. That decision is made once, from the error's nature, before there's any retry count to look at.

## When to escalate during retry

A message correctly classified as transient can legitimately retry for a long time. If ~30 minutes (or longer) of silent retry isn't acceptable for a given flow, escalate independently of the per-message mechanism:

1. Use a *separate* monitoring iFlow that polls the source queue depth.
2. Alert when depth > N or message age > M minutes (Cloud ALM rule), or on a message's `SAPJMSRetries` climbing unusually high.
3. This is independent of the per-message retry mechanism; the queue-level signal catches "many messages backed up" while individual messages are still legitimately retrying.

Don't try to escalate inside the Exception Subprocess on every early attempt — you'll get N alerts per failure (one per retry).

## Coordination with the subprocess

The subprocess runs on **every** attempt, not once at the end — there's no separate broker-side phase that hands off only after exhaustion:

| Subprocess responsibility | Adapter/broker responsibility |
|---|---|
| Classify the error (transient vs. permanent) immediately, on this attempt | Time the delay before the next redelivery |
| Rethrow (Retry) or route to the real DLQ (Bypass) based on that classification | Increment `SAPJMSRetries` on each redelivery; mark `Failed`/`Blocked` once retries stop |
| Build the DLQ envelope for the Bypass path | Send the ACK when the subprocess ends via Message End Event |

If you find yourself wanting the subprocess to count attempts before deciding, you're solving the wrong problem — the decision is about the error's *nature*, not its *age*. Tune Retry Interval / Exponential Backoff for how long a transient failure is allowed to keep trying; that's separate from whether it should be trying at all.

## Common misconfigurations

| Mistake | Symptom | Fix |
|---|---|---|
| Categorization script mis-classifies a permanent error as transient | Goes through retries and ends up `Failed`/`Blocked` instead of reaching the real DLQ immediately | Fix the classification — permanent failures skip straight to Bypass, not after any number of attempts |
| Categorization script mis-classifies a transient error as permanent | Genuinely-recoverable failures get pulled out of retry and dumped in the DLQ prematurely | Fix the classification the other way |
| `Maximum Retry Interval` < `Retry Interval` | Backoff has no effect | Maximum ≥ initial |
| Different classification rules on JMS Sender + AMQP Sender for the same logical flow | Inconsistent behavior depending on entry path | Standardize the transient/permanent rule set across all entry adapters |

## Cross-reference

| Topic | Where |
|---|---|
| Why retry config is critical for transient errors | `error_categories_reference.md` (transient row) |
| Retry queue (for "retry later, not now" use case) | `retry_queue_pattern.md` |
| What goes in DLQ vs retry queue | `dlq_envelope_schema.md` (classification field) |
| Alert suppression during in-flight retries | `alert_categories_reference.md` |
| The Retry/Bypass pattern itself, full detail | `week3/samples/day2_jms/exception_subprocess_wiring.md` |
