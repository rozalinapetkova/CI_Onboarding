# Metering — worked examples

> Per the cookbook: counted per 250 KB of aggregated outgoing message size. JMS + ProcessDirect not counted. Splitter multiplies. Retries counted separately. Rule-of-thumb today: ≥1 receiver adapter = 1 message.

## Example 1 — Echo Service (Week 1 project)

Inbound HTTPS → Content Modifier → HTTPS receiver (validates country) → return JSON.

| Hop | Counted? | Reason |
|---|---|---|
| Inbound HTTPS sender | — | Senders aren't "outgoing" |
| HTTPS receiver to restcountries | ✅ 1 | Outbound to an external system |

**Total: 1 message per call.**

## Example 2 — Order Hub with ProcessDirect (Week 3 project)

HTTPS → Content Modifier → ProcessDirect to translator iFlow → Data Store Write → JMS producer → JMS consumer iFlow → HTTPS receiver to OMS.

| Hop | Counted? | Reason |
|---|---|---|
| HTTPS sender | — | Inbound |
| ProcessDirect to translator | — | **Not metered** |
| Data Store Write | — | Internal store |
| JMS to outbound queue | — | **Not metered** |
| (Consumer iFlow runs separately) | — | JMS hop not metered |
| HTTPS receiver to OMS (consumer side) | ✅ 1 | External call |

**Total: 1 message per business order**, even though 4 iFlow runs happened. *This is why ProcessDirect + JMS are the right composition tools.*

## Example 3 — Bulk file with splitter

SFTP sender picks up a 10,000-line CSV. Splitter emits one message per line. Each line is POSTed to a partner API.

| Hop | Counted? | Reason |
|---|---|---|
| SFTP sender | — | Inbound |
| Splitter | ✅ ×10,000 | Splitter multiplies |
| HTTPS receiver per line | (already counted) | Same outgoing message |

**Total: ~10,000 messages.** Aggregate carefully — splitter is the #1 silent metering surprise.

## Example 4 — Retries

A receiver call to a flaky partner times out. The HTTP receiver is configured for 3 retries.

| Attempt | Counted? |
|---|---|
| Initial | ✅ 1 |
| Retry 1 | ✅ 1 |
| Retry 2 | ✅ 1 |
| Retry 3 | ✅ 1 |

**Total: 4 messages**, even though the business intent was one call. Tune retries with metering in mind.
