# Making business identifiers searchable in Monitor

Operations searches the Monitor by **MPL properties**, not by message headers. A header set via `message.setHeader(...)` is visible in the *Run Steps → Headers* tab but **not** in the Monitor's top-level Search box. To make a value searchable, you must register it as an MPL custom property.

## Two ways to register

### A — Content Modifier "MPL custom header property" checkbox

For values that already live as message headers (most common case):

1. Add a Content Modifier step.
2. Open the *Message Header* tab.
3. Add or reference an existing header. Source can be Header, Property, Constant, XPath, etc.
4. Tick **MPL custom header property**.
5. Save and deploy.

After deploy, the header appears in *Monitor → Message Processing → Advanced Filter → Custom Header Properties*.

### B — `messageLog.setStringProperty(...)` from a Groovy script

For values computed inside a script:

```groovy
def messageLog = messageLogFactory.createMessageLog(message);
if (messageLog != null) {
    messageLog.setStringProperty("orderId", orderId);
    messageLog.setStringProperty("correlationId", correlationId);
    messageLog.setStringProperty("customerId", customerId);
}
```

The null-guard is mandatory — see `log_levels_reference.md`.

## When to use which

| Source of the value | Use |
|---|---|
| Inbound HTTP header (e.g. `correlationId`) | Content Modifier checkbox |
| Extracted from payload (e.g. `orderId` parsed from JSON) | Groovy script |
| Constant set per environment | Content Modifier with Constant source |
| Derived in code (e.g., business reference computed from multiple fields) | Groovy script |

Don't double-register. If the script already sets `orderId` as an MPL property, don't also tick the checkbox on a downstream Content Modifier referencing the same header — the value overwrites itself with no harm but adds confusion to the iFlow diagram.

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
- The checkbox wasn't actually saved. Re-open the Content Modifier; confirm.
- The script ran but `messageLog` was null. Add a property to verify presence; check log level.

## Anti-patterns

| Anti-pattern | Consequence |
|---|---|
| Setting a header but not ticking the checkbox | Header visible in Run Steps but not searchable |
| Registering 50+ properties "just in case" | Cockpit slows down; hits per-MPL limit; operations confused |
| Setting properties with PII or secrets | Tenant-wide log store sees them; multi-developer leak |
| Setting `orderId` differently in Producer vs Consumer iFlows | Operations can't find both halves of the trace under one search |
| Setting property names with spaces or special chars | Some chars get URL-encoded in the Monitor search box, behave unexpectedly |

Names: use `camelCase`, no spaces, no special chars. Match the existing project convention exactly across iFlows.
