# Replay safety — what makes a DLQ entry safely re-injectable

A DLQ that nobody replays is a graveyard. A DLQ that gets carelessly replayed is a duplicate-message machine. The goal: every envelope in the DLQ must be safely re-injectable into the main process *without* causing duplicates, partial double-processing, or out-of-order side effects.

## The replay flow

```
[DLQ entry (envelope)]
        ↓
[Replay iFlow]
        ↓
[Script: unwrap envelope → restore headers + body]
        ↓
[Verify: classification was fixable; PD/SecMat now valid; consumer reachable]
        ↓
[Publish to originalEntryPoint's equivalent main-process queue]
        ↓
[Main process picks up as normal; idempotency check on downstream-side]
        ↓
[Result: success → DLQ entry archived; failure → new DLQ envelope with replayAttempts++]
```

Two things make this safe:
1. **Consumer-side idempotency** — downstream rejects duplicates on `correlationId` / `ce-id`
2. **Replay-side restraint** — replay only fires for *known-fixable* classifications

## Consumer-side idempotency — what the downstream must do

Replay is only as safe as the consumer's idempotency. If the consumer happily processes the same `correlationId` twice, replay creates duplicates.

The Order Hub's downstream contract requires the consumer to dedupe on `correlationId`. Concretely:

| Storage | Used for | TTL |
|---|---|---|
| Data Store `roi_orderhub_event_dedup` | Event entry path (Day 4.3) | 7 days |
| Data Store `roi_orderhub_idem_cache` | HTTP entry path (Week 3) | 24 hours |
| Downstream-system-owned dedup | Final destination check | 30+ days |

When a replayed message reaches the consumer:
- Consumer sees `correlationId` already in `roi_orderhub_event_dedup` (because the original failure was *after* the dedup write, e.g., during downstream call)
- Consumer skips reprocessing, logs as `replay-skipped-already-processed`, succeeds

The seven-day TTL on dedup is sized for "replay within a week of failure is supported; older than that, talk to the team".

## What "safely replayable" means per classification

| Classification | Replay safety | Replay strategy |
|---|---|---|
| `poison` | **NOT** safely replayable as-is | Replay only after the envelope's `originalBody` has been *manually corrected*. Tooling should require explicit operator action; never auto-replay poison |
| `configuration` | Safely replayable *after fix* | Wait for operator to confirm PD/SecMat fixed; then auto-replay batch |
| `transient` | Safely replayable | Auto-replay after a delay if the cause was outage. Should already be in retry queue; appearance in DLQ implies retry queue exhausted (escalate) |
| `business` | NOT replayable | Business rejection is by design; replaying doesn't change the rejection outcome. Wrong destination — should be in reject queue |
| `runtime` | Conditionally replayable | If cause was tenant restart: yes. If OOM on a 1GB payload: no — replaying fails identically |
| `unknown` | NOT replayable until reclassified | The presence of unknown means the classification heuristic didn't recognize the error class. Investigate first, update heuristic, then replay |

## The replay iFlow design

A separate iFlow, `roi-orderhub-replay`:

```
[Timer or Manual Trigger]
       ↓
[JMS Sender: roi.orderhub.dlq]
       ↓
[Script: roiam_parseEnvelope]
       ↓
[Router: by classification]
   ├── poison         → halt, require human approval per message
   ├── configuration  → check PD/SecMat health, if OK proceed; else halt
   ├── transient      → proceed (with delay)
   ├── business       → halt (don't replay)
   ├── runtime        → operator decision required
   └── unknown        → halt
       ↓
[Script: roiam_restoreEntryShape]   ← inverts buildDlqEnvelope
       ↓
[Publish to main entry queue]
       ↓
[Conditional: archive DLQ entry on success, re-DLQ with replayAttempts++ on fail]
```

The replay iFlow does **not** auto-fire on everything in the DLQ. It pre-filters by classification and replay attempts.

## What the replay script restores

`roiam_restoreEntryShape.groovy` (the inverse of `roiam_buildDlqEnvelope.groovy`):

1. Parse envelope JSON
2. Set body = `originalBody` (decode from base64 if `Content-Encoding: base64` was in originalHeaders)
3. Restore each header from `originalHeaders` onto the new message
4. Add tracking headers: `replay.replayedAt`, `replay.replayAttempt`, `replay.originalDlqMessageId`
5. Publish to a queue matching `originalEntryPoint`'s shape — e.g., `originalEntryPoint = amqp:...` → publish to `roi.orderhub.queue` (the shared internal queue)

## The replayedBy header

Replay introduces a new header so that downstream telemetry can distinguish a replay from a first-time message:

| Header | Value | Used by |
|---|---|---|
| `replay.replayedAt` | ISO 8601 timestamp | Audit log |
| `replay.replayedBy` | `roi-orderhub-replay` (iflow id) | Audit log; lets the main iFlow's MPL show "this was a replay" |
| `replay.replayAttempt` | integer (1, 2, ...) | Capping logic — replay attempts > 3 should escalate to human |
| `replay.originalDlqMessageId` | broker-side message id of the DLQ entry | Linking back to forensics |

Downstream idempotency check uses `correlationId`, which is unchanged. The `replay.*` headers are purely informational.

## Replay attempt cap

```
if (envelope.replayAttempts >= 3) {
    halt;   // requires human intervention
}
```

Three is enough to absorb a flaky downstream; beyond three, the issue is structural and needs human eyes.

## What NOT to do in replay

| Anti-pattern | Why bad |
|---|---|
| Re-execute the entire iFlow against `originalBody` directly without going through the main entry queue | Loses idempotency guarantees the entry-path scripts enforce; may bypass schema validation |
| Modify `originalBody` in the replay script | Hides what actually happened; if the modified body fails, the DLQ entry no longer corresponds to a real production failure |
| Replay on a fixed schedule with no human gate for poison | Will replay malformed messages indefinitely as the downstream rejects them |
| Delete the DLQ entry before confirming replay succeeded | If replay fails mid-flight, you've lost the evidence |
| Auto-replay configuration-class without verifying the config is fixed | Re-fires the same alert; ops sees no progress |
| Strip the `correlationId` on replay to "pretend it's a new message" | Defeats downstream dedup; creates real duplicates |

## The "replay-safe" contract

When designing an iFlow's main process, ask: *can the Exception Subprocess capture enough context that this message can be safely replayed later?* If the answer is no, the iFlow has a design problem — usually one of:

| Symptom | Fix |
|---|---|
| Body is consumed by an HTTP-Reply step before failure point — can't capture original | Capture body to a property at iFlow entry (Content Modifier saves to `originalBody` property) |
| Headers like `ce-id` already stripped by mapping step | Capture all critical headers at entry, before mapping |
| Downstream isn't idempotent | Fix downstream first; replay-safety is impossible otherwise |
| Mapping has side effects on a Data Store | Move side effects to after the downstream call, OR ensure the side-effect is idempotent (write-if-absent) |

Designing for replay forces the iFlow toward better hygiene: capture context early, side effects late, idempotency throughout. This is the discipline. The DLQ envelope is the artifact that proves you got it right.

## Cross-reference

| Concern | Where |
|---|---|
| Envelope schema fields | `dlq_envelope_schema.md` |
| Dedup store TTL and key | `pd_vs_security_material_vs_data_store.md` (Data Store section) |
| Why dedup write goes at END of flow | `event_subscription_flow_diagram.md` |
| How the consumer enforces idempotency | Week 3 module (idempotency cache pattern) |
