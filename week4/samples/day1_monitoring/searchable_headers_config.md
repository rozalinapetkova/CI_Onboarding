# Making business identifiers searchable in Monitor

Operations searches the Monitor by **MPL properties**, not by message headers. A header set via `message.setHeader(...)` is visible in the *Run Steps → Headers* tab but **not** in the Monitor's top-level Search box. To make a value searchable, you must register it as an MPL custom property.

## Registering a searchable property

Call `messageLog.addCustomHeaderProperty("<header name>", value)` from a Groovy script:

```groovy
def messageLog = messageLogFactory.getMessageLog(message);
if (messageLog != null) {
    messageLog.addCustomHeaderProperty("orderId", orderId);
    messageLog.addCustomHeaderProperty("correlationId", correlationId);
    messageLog.addCustomHeaderProperty("customerId", customerId);
}
```

The null-guard is mandatory — see `log_levels_reference.md`.

Do this in whichever script step already has the value on hand — the step that parsed `orderId` out of the payload, the step that generated/accepted `correlationId`, etc. No separate registration step is needed if the value-producing script just calls `addCustomHeaderProperty` itself.

## Not the same thing: `messageLog.setStringProperty(...)`

`setStringProperty` looks similar but does something different: it writes to that one script step's own *Properties* subsection in Monitor's detailed log view (Debug or Trace level only), not to a message-wide, searchable field. It is **not** an alternative way to make something searchable — only `addCustomHeaderProperty` does that. Use `setStringProperty` for step-local diagnostic values you want visible while actively debugging that step, never for anything operations needs to search by.

## When to register

| Source of the value | How to register |
|---|---|
| Inbound HTTP header (e.g. `correlationId`) | `addCustomHeaderProperty` in the script step that already reads/sets that header |
| Extracted from payload (e.g. `orderId` parsed from JSON) | `addCustomHeaderProperty` right after extraction, in the parsing script |
| Constant set per environment | `addCustomHeaderProperty` in any script step, value sourced from a parameter |
| Derived in code (e.g., business reference computed from multiple fields) | `addCustomHeaderProperty` right where it's computed |

Don't double-register. If one script already sets `orderId` as an MPL property via `addCustomHeaderProperty`, don't call it again for the same header in a later script — harmless, but adds noise to the iFlow diagram.

## Headers the Order Hub registers

Minimum for the lab:

| Header | Source | Why operations cares |
|---|---|---|
| `orderId` | parsed from inbound JSON payload | Business identifier — most-searched value |
| `correlationId` | set by `roiam_setCorrelationId.groovy` (Section 5) | End-to-end trace across iFlow hops |
| `customerId` | parsed from inbound payload | Triage — "all orders affected for Acme today" |
| `eventId` | set by Event Mesh subscription iFlow when chained (Day 4.3) | Distinguishes one of multiple events on the same order |

Add more as they become operationally useful. Don't pre-register fields nobody searches by — searchable properties have a per-MPL count limit (50 last we checked, but cockpit-enforced).

## Verification

After deploy, send a happy-path call and:

1. *Monitor → Message Processing → Advanced Filter → Custom Header Properties*.
2. Confirm `orderId`, `correlationId`, `customerId` appear in the dropdown.
3. Filter by `orderId = <your test value>`.
4. Expect: the run is found.

If the dropdown is missing a header you registered:

- Log Level might be **Error** — the property is only stored on Failed runs.
  Bump to Info, send a new run, recheck.
- The `addCustomHeaderProperty` call didn't actually run on this code path — check whether the value was null/empty and the call got skipped.
- The script ran but `messageLog` was null. Add a property to verify presence; check log level.

## Anti-patterns

| Anti-pattern | Consequence |
|---|---|
| Setting a header but never calling `addCustomHeaderProperty` for it | Header visible in Run Steps but not searchable |
| Registering 50+ properties "just in case" | Cockpit slows down; hits per-MPL limit; operations confused |
| Setting properties with PII or secrets | Tenant-wide log store sees them; multi-developer leak |
| Setting `orderId` differently in Producer vs Consumer iFlows | Operations can't find both halves of the trace under one search |
| Setting property names with spaces or special chars | Some chars get URL-encoded in the Monitor search box, behave unexpectedly |

Names: use `camelCase`, no spaces, no special chars. Match the existing project convention exactly across iFlows.
