# Number Range — `nr_<your_initials>_OrderSequence`

Atomic, persistent, formatted integer counter. Project naming: `nr_<initials>_<purpose>`. For the Order Hub: `nr_<your_initials>_OrderSequence`.

## Creating the artifact

*Design → Training (package) → Add → Number Range*.

| Field | Lab value | Notes |
|---|---|---|
| **Name** | `nr_<your_initials>_OrderSequence` | Lowercased initials. The `<initials>` infix isolates trainees on the shared tenant; in production drop it |
| **Description** | `Sequential reference number for orders accepted by roi_<your_initials>_OrderHub.` | Visible to ops |
| **Min** | `1` | First value the range will issue |
| **Max** | `99999999` | Generous — covers years of orders at thousands per day |
| **Field Length** | `4` | Padding width. `ORD-0001`, `ORD-0002`, ... `ORD-9999`, then naturally `ORD-10000`. The padding applies only up to the field length |
| **Format** | `ORD-{nnnn}` | `{nnnn}` matches Field Length=4. Use `{nnn}` for 3, `{nnnnnnn}` for 7, etc. |
| **Rotate** | **No** | Wraps to Min after Max. For business references, never Yes — reuse = duplicates |
| **Current Value** | `1` (default) | Visible in *Monitor → Manage Stores → Number Ranges*; resettable in Dev/QA |

Save. Deploy. The artifact is now usable from any iFlow on the tenant.

## Using the Number Range step in an iFlow

Drop a *Number Range* flow step on the canvas (under *Persistence* in the palette).

| Field | Lab value | Notes |
|---|---|---|
| **Number Range Name** | `nr_<your_initials>_OrderSequence` | Exact match. Typos give a runtime error |
| **Property/Header** | *Header* — `X-Order-Sequence` | **Must be a header** — properties don't propagate through ProcessDirect, and we want the sequence visible to the Translator iFlow |

On execution the runtime atomically:
1. Calls the Number Range service.
2. Reads + increments the current value.
3. Formats per the Format string.
4. Writes to the configured header/property.

**Atomic** = no two concurrent runs ever get the same value.

## Position in the Order Hub canvas

```
Idempotency check (Get + Router)
    │  (default branch — cache miss)
    ▼
Number Range step → X-Order-Sequence = ORD-NNNN
    │
    ▼
ProcessDirect → Translator
```

The Number Range step lives **after** the idempotency check (so cache-hits don't burn sequence numbers) and **before** ProcessDirect (so the translator can see `X-Order-Sequence` in the canonical XML construction).

## Gotchas

| Gotcha | Effect | Mitigation |
|---|---|---|
| Format=`ORD-{nn}` with Max>99 | At value 100, format produces `ORD-100` (no truncation but no padding either); some integrations parse on width | Make Format width >= log10(Max) |
| Rotate=Yes | At Max+1 = Min: duplicate sequence number issued | Always No for business refs |
| CTM transport carries Current Value | QA imports Dev's "current value 412" — first QA order is `ORD-0413` | Reset to 1 in QA after transport. Document in the deploy runbook |
| Resetting current value mid-production | New orders collide with historical sequence numbers; downstream gap-detection breaks | Don't. If you must, document with a ChangeLog entry |
| Skipping numbers by editing current value forward | Gap-detection downstream flags missing orders that don't exist | Same — document explicitly |
| Calling the Number Range step in the Exception Subprocess to assign a "failed order" sequence | Burns a sequence on every failure; analytics now have phantom orders | Don't assign sequences to failures. Use a separate ID scheme for error tracking |

## Why a Number Range vs. UUID vs. timestamp

| Approach | Use when |
|---|---|
| **Number Range** | Business-visible reference humans will read aloud (order number, claim number, ticket ID). Gap-free under normal ops. Atomic. Format-controlled |
| **UUID** | Internal correlation IDs. No central bottleneck. Untraceable to humans |
| **Timestamp** | Sortable per-message tag where collisions are tolerable (e.g. log marker). Not for IDs |

Hybrid pattern: business reference from Number Range (`ORD-0001`) + internal correlation from UUID (`correlationId: 5f3a-...`). Caller and ops both get the view they need.

## Cockpit operations

*Monitor → Manage Stores → Number Ranges → nr_<your_initials>_OrderSequence*:

- View current value.
- **Edit current value** — Dev/QA convenience; production should be locked down via role assignment.
- Delete the artifact (cascades to the range; iFlows referencing it will error at runtime).
- Audit log of who edited the value when.

After every lab session, current value moves. Don't reset between exercises unless an exercise explicitly tells you to — the cookbook expects continuity.
