# Log levels — None / Error / Info / Debug / Trace

The iFlow's deployable **Log Configuration** controls what the runtime captures. Set this in *Manage Integration Content → iFlow → Configure → Log Configuration*. It is a runtime setting, not a design-time property — it can be changed without redeploying the iFlow.

## Levels at a glance

| Level | What's captured | When to use | Cost on tenant log store |
|---|---|---|---|
| **None** | Nothing. `messageLogFactory.getMessageLog(message)` returns `null` | Never for the Order Hub. Acceptable for high-volume noise iFlows that have separate observability | Free |
| **Error** | Only failed runs. MPL entry plus the exception | Default for stable, low-attention iFlows | Low |
| **Info** | Every run. Attachments and properties you set are retained | Production iFlows you actively monitor — including the Order Hub | Medium |
| **Debug** | Info + every step boundary in the Run Steps view | Debugging a specific issue; revert when done | High |
| **Trace** | Debug + full message payload at every step boundary | Reproducing a hard bug. Never leave on | Severe — payloads stored in the tenant log store |

## The None-level null guard

When level is **None**, `messageLogFactory.getMessageLog(message)` returns `null`. Every script that calls MessageLog methods must guard against this:

```groovy
def messageLog = messageLogFactory.getMessageLog(message);
if (messageLog != null) {
    messageLog.addAttachmentAsString("incoming-payload", payloadString, "application/json");
    messageLog.setStringProperty("orderId", orderId);
}
```

Without the guard, operations sets the iFlow to None and your script throws NPE on the next message. The guard is non-negotiable for any script that calls `messageLog.*`.

## Production rule for the Order Hub

| Environment | Level | Rationale |
|---|---|---|
| Dev | Info | All runs visible to the developer |
| QA | Info | All runs visible to QA + the cohort |
| Prod | Info | Order Hub is high-attention; we want full attachments and properties on every run |

**Debug** and **Trace** are temporary investigation tools. Allowed in any environment for a documented incident; must be reverted when the investigation closes. Recorded in the iFlow's changelog as: "Trace enabled 2026-06-21 14:00, reverted 2026-06-21 16:45 (INC-1234)".

## Cost breakdown — why Trace is "severe"

Trace stores the **full message body at every step boundary**. For a 50-step iFlow processing a 100 KB payload:

- Info: ~5 KB per run (properties + a few attachments you chose).
- Debug: ~20 KB per run (step boundary metadata, no payloads).
- Trace: 50 × 100 KB = **5 MB per run**.

At 10,000 messages/day, Trace burns 50 GB of tenant log store **per day**. The tenant log store has a fixed quota; once it's full, older messages roll off. Real bugs become unsearchable because you Traced over them.

## Costs that aren't obvious

- Trace captures payload **even after the script has set the body to null or replaced it**. There is no way to "redact a field" at Trace level — the runtime snapshots whatever the body is at each boundary.
- If your payload contains credentials, PII, or signed tokens, Trace stores them in the tenant log. Other developers and operators on your tenant can read them. **Don't Trace anything with secrets.**
- The cockpit's response time gets sluggish when the log store nears capacity. Operations sees an unrelated slowdown and starts asking why.

## How to change log level on a deployed iFlow

1. *Manage Integration Content → iFlow → Configure → Log Configuration*.
2. Choose new level (None / Error / Info / Debug / Trace).
3. Click *Save*. Effect is immediate — no redeploy.

If you don't see the *Configure* button, you don't have edit permission on this iFlow. Ask operations.

## How to verify the level took effect

After changing level to Info or higher:

1. Send a happy-path call.
2. Open *Monitor → Message Processing → click the new entry → Attachments tab*.
3. Expect: your attachments are present.

If you set Info and the Attachments tab is empty for new runs, something blocked the level change — usually a tenant-wide policy. Confirm via the cockpit's *Configure* page, not by inference.

## Don't log secrets

Repeat from Week 2: the tenant log store is multi-developer. Anyone with monitor read access on the tenant reads your attachments. **Strip authorization headers, OAuth tokens, API keys, customer PII from MessageLog attachments.** When in doubt, attach only the canonical/business payload, not the raw HTTP envelope.
