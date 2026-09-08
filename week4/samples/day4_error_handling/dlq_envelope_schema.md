# DLQ envelope schema — contract spec

The DLQ envelope is the structured JSON written to `roi.orderhub.dlq`. It is the contract between the producing iFlow (the one that failed) and the future consumers (replay iFlow, forensics dashboard, support tooling).

Treat this schema like a public API: fields are added, never removed without a major version bump.

## Why an envelope, not the raw failed payload

A DLQ that holds bare failed messages is a dead end. You lose:

- **What broke** — exception class, message, route id
- **When** — the failure timestamp (broker timestamps may be different)
- **Where it came from** — entry point (AMQP topic, HTTP path, JMS queue)
- **What correlationId tied to upstream** — needed to cross-reference with producer logs
- **Whether it's already been retried N times** — a re-delivered message looks identical to a first-time one

The envelope wraps the original body and headers with the error context. Replay tooling can then make informed decisions instead of guessing.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `envelopeVersion` | string | yes | Schema version. Currently `"1"`. Bump on breaking changes. |
| `correlationId` | string | yes | The traceable id across producer / iFlow / consumer. Falls back: `header.correlationId` → `header.ce-id` → generated UUID |
| `failedAt` | string (ISO 8601) | yes | When the subprocess captured the failure, with offset, e.g. `2026-06-22T14:32:08.123+02:00` |
| `originalEntryPoint` | string | yes | Where the message entered the iFlow. Format: `<protocol>:<identifier>` — e.g. `amqp:sap.s4.beh.salesorder.v1.SalesOrder.Created.v1`, `http:/orders`, `jms:roi.orderhub.queue` |
| `originalIflow` | string | yes | The iFlow id that produced the envelope. Lets the replay iFlow know where to re-inject. |
| `failedRouteId` | string | yes | Step / route id where the exception was thrown (from `CamelFailureRouteId`). Helps narrow blame between mapping, downstream call, etc. |
| `redeliveryCounter` | integer | yes | How many times the entry adapter re-delivered before the subprocess fired. `0` means first delivery. |
| `classification` | string (enum) | yes | One of `transient`, `poison`, `business`, `configuration`, `runtime`, `unknown` |
| `errorClass` | string | yes | Fully qualified class name of the exception, e.g. `groovy.json.JsonException` |
| `errorMessage` | string | no | The exception's `.getMessage()`. Truncated to 4096 chars if longer. |
| `originalHeaders` | object (string → string) | yes | All entry headers that aren't framework noise (no `Camel*`, no `Authorization`, no `Cookie`). Required for replay. |
| `originalBody` | string | yes | The body as captured at failure-time. Always present, may be empty string. For binary bodies, base64-encoded with a `Content-Encoding: base64` header marker (see Binary bodies). |
| `replayAttempts` | integer | no | Set only by a replay iFlow that re-DLQs an envelope. First write omits. |
| `replayHistory` | array | no | Set by replay iFlow when re-DLQing — list of `{timestamp, replayedBy, outcome}` |

## Field rules and gotchas

### `correlationId` must be stable across redeliveries

If a message is re-delivered 3 times before DLQ, the `correlationId` must be identical on all 4 DLQ envelopes (3 retries + final DLQ). Because:

- Replay tooling deduplicates on `correlationId`
- Forensics traces correlate iFlow runs through this id

The fallback chain in `roiam_captureErrorContext.groovy` guarantees this: it reads `correlationId` from headers first, which was set by the main process's `roiam_setCorrelationId_*` script — and CloudEvents `ce-id` (the second fallback) is also stable across redeliveries.

### `failedAt` is iFlow-local, not broker-local

The timestamp records when the *subprocess* captured the failure. The broker may have queued the original message hours earlier; that ages-in-queue figure is on the broker, not in the envelope.

### `originalEntryPoint` is for routing replays

The replay iFlow looks at this to decide which queue / endpoint to re-inject into. Don't shorten it ("AMQP" alone is useless — the topic matters).

### `originalHeaders` excludes secrets

Never write `Authorization`, `Cookie`, `Set-Cookie`, or anything `roiam_secret_*` to the envelope. The DLQ is visible to ops and support staff who shouldn't see credentials. `roiam_buildDlqEnvelope.groovy` enforces this via `shouldCaptureHeader()`.

### `originalBody` rules

- Always present as a string field (even if empty)
- Text bodies (JSON, XML): captured verbatim
- Binary bodies: encode as base64; add `"Content-Encoding": "base64"` to `originalHeaders` so the replay iFlow knows to decode
- Maximum recommended size: 1 MB. If the original payload is larger, store a digest (`sha256(originalBody)`) in the envelope and the payload in a Data Store (or S3-equivalent) with the digest as key

### `classification` drives downstream

This single field determines how the DLQ consumer handles the entry:

| Classification | DLQ consumer action |
|---|---|
| `poison` | Surface for human review; do NOT auto-replay |
| `configuration` | Page oncall; auto-replay only after operator marks PD/SecMat fixed |
| `transient` | Should not be in DLQ if retry queue is configured. If here, escalate to human |
| `business` | Should not be in DLQ (lives in reject queue). If here, classification heuristic needs update |
| `runtime` | Surface for human review; auto-replay safe only if redelivery counter == 0 |
| `unknown` | Same as `poison` — surface for human review |

## Sample envelope

See `sample_dlq_envelope.json` for a complete realistic example.

## Versioning

| Version | Status | Notes |
|---|---|---|
| 1 | Current | Fields as above |
| 2 (future) | Reserved | Will add `originatingTrace` for distributed tracing, possibly `replayInstructions` for the consumer |

Schema changes:

- **Additive (new optional field)** — same envelopeVersion; consumers ignore unknown fields
- **Breaking (rename, type change, removal)** — bump envelopeVersion; consumers route by version

## Why this lives in a markdown spec, not just in code

The spec is what makes the DLQ a contract instead of a buffer. Without a written schema:

- Each new iFlow producer drifts in its envelope shape → consumers can't be generic
- Replay tooling has to special-case per producer
- Support staff have to read source to find a field

With the spec, every iFlow writes envelopes that follow the same shape; the replay iFlow and dashboards can treat the DLQ as a uniform stream.
