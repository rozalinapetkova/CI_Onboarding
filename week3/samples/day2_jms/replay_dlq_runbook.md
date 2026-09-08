# Runbook — Replay messages from the DLQ

When messages land in `roi.orderhub.dlq.<initials>`, someone has to decide: replay, discard, or escalate. This runbook covers the mechanics. The judgment is on you.

## Before you replay anything

**Replay without fixing the root cause is a loop.** A Bypass-class message that landed in the DLQ for HTTP 400 will fail the same way on replay. A Retry-class message that exhausted 3 retries during a downstream outage will succeed on replay — *if* the outage is over.

Three questions before replay:

1. **What category was the failure?** Check the message's MPL `errorCategory` property (set by `roiam_categorizeError.groovy`) — `Retry` or `Bypass`.
2. **Has the underlying cause been resolved?** Downstream restored, OAuth credential fixed, schema bug shipped, etc.
3. **Is the payload still valid?** Stale orders past their fulfilment window, deduplicated upstream, or already-replayed once — these need manual review, not blind replay.

If any of these is "no" or "don't know", escalate first. Do not replay.

## Manual replay — cockpit *Move To...*

For small numbers (1–10 messages):

1. *Monitor → Message Queues → `roi.orderhub.dlq.<initials>`*.
2. Click a message to open it. Inspect:
   - Body (the original canonical XML).
   - Headers: `X-Error-Category`, `X-DLQ-Reason`, `CamelHttpResponseCode`, `correlationId`.
   - The `categorization` attachment if it was preserved.
3. Confirm step 1–3 of "Before you replay anything".
4. Select the message(s) → *Actions → Move To...* → choose `roi.orderhub.outbound.<initials>`.
5. The consumer iFlow picks it up within seconds.
6. Watch *Monitor → Message Processing* for the new run. It should complete this time.

If it fails again with the same 4xx, **stop replaying**. The category was Bypass and the root cause isn't fixed.

## Batch replay — for >10 messages, a dedicated iFlow

For larger DLQ volumes, build a one-shot replay iFlow:

```
JMS sender (roi.orderhub.dlq.<initials>) ──► Content Modifier (clear error headers) ──► JMS receiver (roi.orderhub.outbound.<initials>)
```

- **One-shot:** deploy, let it drain the DLQ, undeploy. Do not leave it running.
- **Clear `X-Error-Category` and `X-DLQ-Reason`** before re-enqueue — otherwise the replayed message still carries error metadata that confuses tracing.
- **Concurrent Processes = `1`** — replaying is bursty enough as-is, don't compound.
- **No DLQ on this iFlow** — if a replay fails, you want it to land back in the original DLQ (auto-DLQ) so you don't loop forever.

The replay iFlow is **not** part of the normal Order Hub topology. It exists as a deployable artifact in the team's repo and gets deployed only when needed.

## Discard

If the message is stale or the root cause is "this should never have been accepted":

- *Monitor → Message Queues → `roi.orderhub.dlq.<initials>`* → select → *Delete*.
- **Document the discard.** Confluence page or runbook log entry: which `correlationId`s, why discarded, who authorized.

Discarding silently is the operational debt that bites later when finance asks "what happened to order C-3001 on the 14th?"

## Escalate

- The DLQ has >50 messages and you don't know why.
- The same `correlationId` appears in the DLQ more than once (replay loop).
- The category is `Retry` but the message has been in the DLQ for hours — means even auto-retry exhausted; downstream may have a longer outage than expected.
- Anyone has manually changed an iFlow in production without a CR — needs investigation, replay later.

## Things this runbook is NOT

- **Not a fix.** Replay restores delivery; it does not fix the bug that caused the DLQ landing.
- **Not idempotent for non-idempotent downstreams.** If the downstream is *not* idempotent (some 4xx came back after partial processing), replay can double-process. Confirm idempotency before any batch replay. (Day 3.4's Data Store idempotency pattern is what makes batch replay safe for the Order Hub.)
- **Not a substitute for monitoring.** If you only learn about the DLQ during this runbook, alerting is broken. *Alert Notification → DLQ depth > 0* should page on-call. (Week 4.)

## Lab demonstration

In the lab (Section 11 step 7), trainee replays a Bypass-class DLQ message that hasn't been root-caused. It fails the same way and returns to the DLQ. The lesson: **replay only after the fix**.
