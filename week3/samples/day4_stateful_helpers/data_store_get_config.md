# Data Store *Get* flow step — configuration reference

The *Get* step looks up a Data Store entry by key. On the Order Hub it's the idempotency guard's gate — first step after `roiam_logIncoming`, immediately before the Router.

## Fields

| Field | Lab value | Notes |
|---|---|---|
| **Data Store Name** | `ds_<your_initials>_OrderIdempotency` | Auto-created on first deploy. Tenant-scoped. Naming: `ds_<initials>_<purpose>` |
| **Visibility** | *Integration Flow* | Other option is *Global* (tenant-wide). Keep iFlow-scoped unless another iFlow legitimately reads the same key |
| **Entry ID** | `${header.X-Idempotency-Key}` | The lookup key. **Never** `${exchangeId}` — that changes every run |
| **Throw Exception on Failure** | **No** | Critical. Default is Yes; that turns a normal cache-miss into an exception that fires the Exception Subprocess. Uncheck so the Router can branch on found/not-found |
| **Get Options → Delete on Completion** | No | Don't delete — we want repeated calls with the same key to keep hitting the cache for the full TTL |
| **Output Body** | *As Body* | Replaces the incoming body with the stored payload. The Router then either returns this body as the response, or discards it and continues |
| **Status (header)** | `SAP_DatastoreEntryFound` | Set automatically by the runtime — `true` or `false`. It's a **header**, not a property, and the name is fixed, not tenant-dependent |

## What gets written into the message

On **found**:
- Body = the stored payload (the JSON response envelope).
- Header `SAP_DatastoreEntryFound` = `true`.
- Original body is **lost** — if you need the inbound payload later, snapshot it to a property first.

On **not found** (with Throw Exception on Failure = No):
- Body = unchanged from inbound.
- Header `SAP_DatastoreEntryFound` = `false`.

## Where it sits in the canvas

```
HTTPS Sender ─► Content Modifier (set correlationId, orderId, X-Idempotency-Key check)
            ─► Script: roiam_logIncoming    (from sc_<initials>_OrderHubHelpers)
            ─► Data Store: Get               ← THIS STEP
            ─► Router on ${header.SAP_DatastoreEntryFound}
                ├─ 'true'  ─► End (return cached body, response 202)
                └─ default ─► Number Range → ProcessDirect → ... → Data Store Write
```

## Snapshot pattern when you need the original body

If your downstream path needs the inbound JSON (not the cached payload), snapshot before the Get step:

```
Content Modifier
    Property: inboundOrder = ${in.body}      (Type: Expression, Source: ${in.body})
    Type:     java.lang.String
─► Script: roiam_logIncoming
─► Data Store: Get
─► Router
    ├─ 'true' branch:  Body already = cached envelope ─► End
    └─ default branch:
         Content Modifier (Body = ${property.inboundOrder})  ← restore
         continue to Number Range, ProcessDirect, etc.
```

Without the snapshot, on cache-miss the downstream sees the body the Get step *replaced* with — and on most versions that's the empty/null body when no entry was found. The snapshot makes the inbound payload available in both branches.

## Common Get-step mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Throw Exception on Failure = Yes | First cache-miss fires the Exception Subprocess instead of processing the order | Uncheck. Use a Router |
| Entry ID = `${exchangeId}` | Every lookup misses; store grows but never serves | Use the business idempotency key |
| Entry ID = `${header.correlationId}` | Same key for retries with a fresh business intent collapses two real orders into one | Use a header the *caller* generates per intent (`X-Idempotency-Key`), not per call (`correlationId`) |
| Delete on Completion = Yes | First retry within TTL still re-processes — cache served once then evaporated | Keep No for idempotency |
| Visibility = Global without naming convention | Two iFlows clash on the same key by accident | Either scope to iFlow or namespace the key (`orderHub:${key}`) |

## Cockpit visibility

*Monitor → Manage Stores → Data Stores → ds_<initials>_OrderIdempotency → Entries* — browse, filter by Entry ID prefix, click into an entry to view payload + properties + *Expires At* timestamp.
