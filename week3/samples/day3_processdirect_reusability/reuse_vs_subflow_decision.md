# Reuse mechanism — which one when

SAP CI offers four reuse mechanisms. They are not interchangeable. Picking the wrong one is the difference between "the iFlow is simple" and "we have eight subtly diverging copies of the same logic."

## The four mechanisms

| Mechanism | What it reuses | Boundary | Versioning |
|---|---|---|---|
| **Subflow / Local Integration Process** | Logic chunks within ONE iFlow | In-iFlow only | Same as containing iFlow |
| **ProcessDirect** | Whole iFlow logic — composition at the iFlow level | Cross-iFlow, in-memory, sync or async | Per iFlow version |
| **Script Collection** | Groovy scripts (and optionally JARs, config) | Resource artifact referenced by N iFlows | Per Script Collection version |
| **Message Mapping artifact** | Field mappings shared between iFlows | Resource artifact, referenced from Mapping flow step | Per Mapping version |

## Decision tree

```
Need to share something across iFlows?
├─ No (only within one iFlow)
│   └─► Local Integration Process / Subflow
│
└─ Yes
    ├─ Is it a Groovy script?
    │   └─► Script Collection
    │
    ├─ Is it a whole pipeline (parse, transform, validate)?
    │   ├─ Need durability between caller and callee?
    │   │   └─► No → ProcessDirect (in-memory)
    │   │       Yes → JMS (queue between caller and callee — Day 3.2)
    │   │
    │   └─ Need to invoke an external system?
    │       └─► HTTP receiver / OData / SFTP, not reuse at all
    │
    ├─ Is it a field-mapping?
    │   └─► Message Mapping artifact (referenced from Mapping step)
    │
    └─ Is it a value-mapping table (code list, lookup)?
        └─► Value Mapping artifact (separate cockpit area)
```

## Examples

### "I want to log incoming messages the same way in every consumer iFlow"
**→ Script Collection.** One `roiam_logIncoming.groovy` in `sc_<initials>_LoggingCommon`, referenced from every consumer.

### "I want every iFlow that touches Order data to validate against the canonical XSD"
**→ Script Collection.** A `roiam_validateCanonicalOrder.groovy` doing the validation, in a shared collection.

### "I want the Order Hub and the Audit iFlow both to translate vendor formats to canonical"
**→ ProcessDirect** into a single Order Translator iFlow. Both callers compose against `/orderTranslator/v1/translate`.

### "I want to expose a 'get partner details' function to several iFlows"
**→ ProcessDirect.** A `roi_partnerLookup` iFlow with an internal Partner Directory call, exposed at `/partnerDirectory/v1/lookup`. Or a Script Collection helper that wraps the Partner Directory accessor — depends on whether the logic is "an iFlow's worth" or "a function's worth."

### "My iFlow has a 30-step happy path and a 5-step retry branch that duplicates 4 of the happy-path steps"
**→ Local Integration Process.** Subflow containing those 4 steps, called from both branches via *Process Call*.

### "Vendor X and Vendor Y both map to the canonical Order, with 80% field overlap"
**→ Two separate Message Mappings.** Don't force-share — the 20% drift will grow speculative parameters in a shared mapping that no caller uses.

## Two-sentence defence — examples

> Q: Why ProcessDirect from the Order Hub into the Translator instead of just inlining the parsing logic?
>
> A: The Audit iFlow already calls the same translator over HTTPS, and the Regression iFlow needs to in Week 4 — having one translator iFlow with three callers beats three copies of the parsing logic. ProcessDirect is the right transport here because it's in-tenant, sync, and the body's the only thing we need to carry; allow-listing the four lab headers covers the trace context.

> Q: Why a Script Collection for `roiam_logIncoming` instead of just copying it into both iFlows?
>
> A: The producer and consumer both want the same logging shape, and we already know a third iFlow (the Audit one) will want it next sprint — putting it in `sc_<initials>_OrderHubHelpers` means one edit propagates to all three on the next collection deploy. The cost is one extra artifact to version; the savings is no risk of drift.

> Q: Why didn't you extract `roiam_categorizeError.groovy` into the Script Collection too?
>
> A: Only one iFlow uses it today (the consumer). Promoting now would speculate on a second consumer that may never appear; project rule is to extract on the second real use, not the first.

> Q: We have a 30-step iFlow, would Subflow help?
>
> A: Only if there's logic shared between branches *within* this iFlow — Subflow / Local Integration Process is a within-iFlow tool. If the logic should be shared across iFlows, it's ProcessDirect or Script Collection, depending on whether it's a pipeline or a function.

## Anti-patterns

| Anti-pattern | What's wrong | What instead |
|---|---|---|
| Pre-emptively extracting a "shared script" with one consumer | Speculative shared abstraction; grows parameters no one uses | Inline. Promote on second real consumer |
| Using ProcessDirect when the callee genuinely needs durability | Lose messages on JVM restart | JMS |
| Using JMS when ProcessDirect would do | Costs a queue, costs latency, costs ops | ProcessDirect for in-tenant sync composition |
| Subflow across iFlows | Doesn't work — Subflows are within-iFlow | ProcessDirect |
| Copying a Groovy file to N iFlows manually | Drift, hard rotation | Script Collection |
| Putting iFlow-specific logic in a Script Collection | Forces speculative shared contract | Inline |
| Version-pinning an iFlow's Script Collection reference | Defeats the reuse benefit (one collection deploy, all iFlows updated) | Use latest. Pin only for emergencies |
