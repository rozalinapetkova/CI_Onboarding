# Header allow-list — the one bug every ProcessDirect cohort hits

## The rule

ProcessDirect propagates the **body** automatically. **It does NOT propagate headers automatically.** It does not propagate properties at all.

Each ProcessDirect adapter (caller's receiver, callee's sender) has an **Allowed Headers** field. **Default: empty. Empty means no headers cross the boundary.**

A header makes it from caller to callee only if:

1. It is present on the caller's message at the moment of the ProcessDirect call.
2. The **caller's** ProcessDirect receiver Allowed Headers list includes its name.
3. The **callee's** ProcessDirect sender Allowed Headers list includes its name.

Miss any of the three, header is gone.

## The lab's five headers

For today's Order Hub + Translator chain:

| Header | Set by | Why it must propagate |
|---|---|---|
| `correlationId` | HTTPS sender / first Content Modifier | Cross-iFlow tracing in MPL; without it the translator run looks orphaned |
| `orderId` | First Content Modifier (read from JSON body) | Lets the translator log a meaningful identifier |
| `X-Order-Format` | First Content Modifier (set to `json` in lab) | Tells the translator which branch of the Router to take |
| `X-Idempotency-Key` | Day 3.4 — set after Data Store check | Tomorrow's idempotency pattern; allow-list now so it Just Works tomorrow |
| `X-Order-Sequence` | Day 3.4 — set from Number Range | Same — pre-allow-listed for tomorrow |

Pre-allow-listing `X-Idempotency-Key` and `X-Order-Sequence` today is deliberate: it avoids "the iFlow worked yesterday and broke today after a header rename" debugging.

## Setting it in the cockpit

ProcessDirect adapter → *Connection* (or *Processing*) tab → *Allowed Headers* field. Comma-separated, **case-sensitive**, no wildcards:

```
correlationId,orderId,X-Order-Format,X-Idempotency-Key,X-Order-Sequence
```

| Form | Works? |
|---|---|
| `correlationId, orderId` (space after comma) | Tolerated, but team style is no spaces — easier to diff |
| `*` (wildcard) | **Not supported.** Explicit names only |
| `correlation-id` (renamed mid-flight) | Header would have to actually be named that. Match the actual header name |

## In the iFlow XML

ProcessDirect adapter blocks in iFlow XML contain a property:

```xml
<bpmn2:property>
  <bpmn2:key>allowedHeaders</bpmn2:key>
  <bpmn2:value>correlationId,orderId,X-Order-Format,X-Idempotency-Key,X-Order-Sequence</bpmn2:value>
</bpmn2:property>
```

If you're hand-editing iFlow XML to keep two adapters in sync, this is the line to keep identical between caller's receiver and callee's sender.

## Properties — the absolute rule

**Properties never cross a ProcessDirect boundary. There is no setting that changes this.**

If you have a property `errorCategory` on the caller and want it on the callee:

```groovy
// caller side, immediately before the ProcessDirect call
message.setHeader("X-Error-Category", message.getProperty("errorCategory"));
```

And allow-list `X-Error-Category`. On the callee:

```groovy
// callee side, first step after ProcessDirect sender
message.setProperty("errorCategory", message.getHeaders().get("X-Error-Category"));
```

The lift-to-header-then-restore-to-property pattern is a fixture of any ProcessDirect-heavy iFlow.

## How to verify it's working

After the call:

1. *Monitor → Message Processing → callee's run → Headers* tab.
2. Confirm every header in your allow-list is present.
3. If a header is missing, check (in order): caller's Allowed Headers, callee's Allowed Headers, whether the header was actually set on the message before the call.

A missing header is **silent** — no error, just absent. Always verify in the MPL after wiring a new ProcessDirect link.

## The Symptom → cause shortcut

| Symptom | Cause |
|---|---|
| Callee MPL shows the body but `correlationId` is empty | Allow-list missing or caller never set the header in the first place |
| Callee MPL shows some allow-listed headers but not others | Asymmetric lists between caller and callee. Diff them |
| Property `foo` on caller is null on callee | Properties don't propagate. Lift to a header |
| Callee MPL link from caller MPL is broken (no "Continues to" link) | `correlationId` not allow-listed. The MPL uses correlationId to link runs |
