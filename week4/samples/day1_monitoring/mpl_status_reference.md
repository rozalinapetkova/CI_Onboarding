# MPL statuses — what they mean, how to provoke, when to alert

The 8 statuses an MPL entry can have. Operations sees the status first; the rest of the page is supporting detail. Most teams know two of these well and treat the other six as exceptions.

## Reference table

| Status | What it means | Provoke it by | Alert? |
|---|---|---|---|
| **Pending** | Accepted but not yet picked up. Stuck consumer, sender buffer, queue depth growing | Undeploy a JMS consumer iFlow, send a message via its producer — producer reports Completed, consumer side shows Pending | Yes if it persists beyond expected SLA |
| **Processing** | Currently running. Should be short-lived | Add `sleep(20000) { interrupted -> /* */ }` in a script step, send a message, refresh the Monitor immediately | No, except for ones stuck longer than the iFlow timeout |
| **Completed** | Run finished without an exception bubbling up | Any happy-path call | **No alert** — but be aware this hides HTTP error-suppression |
| **Failed** | An exception reached the iFlow boundary | Send malformed JSON to a parser-bearing step with no Exception Subprocess | Yes, always |
| **Retry** | A retry policy is active; next attempt scheduled | Undeploy the receiver target the iFlow calls; the JMS consumer raises and enters its retry policy | Alert on retry **count**, not on the Retry status itself |
| **Escalated** | All retries exhausted; message moved (e.g. to DLQ) | Same as Retry, but exhaust max attempts; the message lands in the configured DLQ | Yes — this is the human-attention status |
| **Discarded** | Intentionally dropped (idempotency duplicate, filter step) | Replay the same `X-Idempotency-Key` on the Order Hub; second call returns cached envelope and the run is Discarded | Usually no; log/count for trend analysis |
| **Abandoned** | Tenant restart killed the run mid-execution | Trainer-only: restart the tenant worker mid-run | Yes — should be rare; investigate root cause |

## The Completed trap

A run can be `Completed` and still represent a business failure. Examples:

- Receiver call returned HTTP 500, but "Throw Exception on Failure" was unchecked and the iFlow branched on `${header.CamelHttpResponseCode}` to swallow it.
- The iFlow caught an exception and quietly set an error property without re-throwing.
- A Filter step routed the message into a dead-end Sub-process that calls End without raising.

**Alerting policy:** never alert on Completed alone. If you have an iFlow that "completes" with backend errors, fix the iFlow (re-raise, or move the branch into a Subprocess that emits an Escalated MPL entry). Do not paper over the gap by parsing message body in your alert rules.

## Pending vs Processing — the difference

Both look "in motion" but mean different things:

- **Pending** = the iFlow hasn't started its first step yet. Queue depth, broker connection, consumer not deployed.
- **Processing** = the iFlow is mid-flight. Look at the *Run Steps* tab for the active step.

If you see a wave of Pending entries, the issue is upstream of the iFlow logic itself.

## What the Monitor shows you per status

| Tab | Pending | Processing | Completed | Failed | Retry | Escalated | Discarded | Abandoned |
|---|---|---|---|---|---|---|---|---|
| **Run Steps** | empty | live, growing | full | full | full (current attempt) | full (last attempt) | partial | partial |
| **Attachments** | none | partial | full (if Info+) | full (if Info+) | full | full | partial | partial |
| **Properties** | minimal | partial | full | full | full | full | partial | partial |
| **Error Information** | none | none | none | exception + stack | exception | exception + retry exhaustion | none | runtime fault |

The *Error Information* tab is where you'll spend most of your time on Failed / Escalated runs.

## Filtering by status

Operations rarely browses by timestamp alone. Their typical workflow:

1. Open *Message Processing*.
2. Filter status = `Failed` + `Escalated`, time range = "last 1 hour".
3. Search by `correlationId` or `orderId` once they have a customer-reported reference.

If your iFlow doesn't make `correlationId` and `orderId` searchable, step 3 fails. See `searchable_headers_config.md`.
