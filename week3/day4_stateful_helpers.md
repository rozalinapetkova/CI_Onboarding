# Day 3.4 — Stateful Helpers: Data Store, Number Ranges & Globals

> **Goal of the day.** Add memory to the Order Hub. By end of day, your producer iFlow rejects duplicate orders by checking a **Data Store** entry keyed on `X-Idempotency-Key`, every accepted order gets a sequential reference number from a **Number Range** named `nr_<your_initials>_OrderSequence` formatted as `ORD-{nnnn}`, and you can articulate when a **Global Variable** is appropriate vs. when it's almost certainly a design smell.

## 1. The three stateful artifacts at a glance

iFlows are otherwise stateless — every message run starts fresh. The three CI-managed stores that survive across runs:

| Artifact | What it stores | Lookup key | Lifetime | Concurrency |
|---|---|---|---|---|
| **Data Store** | Arbitrary message payloads keyed by string | One key per entry | Configurable (TTL) | Per-entry locking; safe |
| **Number Range** | A monotonically increasing integer | The Number Range name | Permanent (until reset) | Atomic next-value; safe |
| **Global Variable** | A small string value | Variable name | Permanent (until deleted) | **Last writer wins — no atomicity** |

These are **tenant-scoped** — accessible from any iFlow on the tenant, transported with the iFlow they belong to (Data Store / Number Range) or as a separate artifact (Globals).

## 2. Data Store — the workhorse

A **Data Store** is a key/value persistence area for message payloads. Each iFlow can have its own Data Store, or share one tenant-wide. Capabilities:

- **Write** (`Write` flow step) — store a payload under a key, optionally with TTL.
- **Read** (`Get` flow step) — fetch a payload by key, optionally delete after read.
- **Select** (`Select` flow step) — fetch by query (e.g. all entries with key prefix).
- **Delete** (`Delete` flow step) — remove an entry.

### Data Store flow steps and what they do

| Flow step | Behavior on key found | Behavior on key not found |
|---|---|---|
| **Write** | Overwrite (or append, depending on Overwrite flag) | Create new entry |
| **Get** | Return payload + headers/properties as configured | Throws an exception by default — or sets a property if "Throw Exception on Failure" is unchecked |
| **Select** | Return list of matching entries | Returns empty list |
| **Delete** | Remove | Throws / no-op depending on flag |

### Use cases

- **Idempotency** — store `X-Idempotency-Key → response` on first call; on subsequent call, if the key is found, return the stored response and skip processing. *Today's lab.*
- **Retry queue** — when a downstream is briefly down, store the message; a scheduled timer iFlow reads the Data Store entries and replays. (Less common now that JMS handles this; valid pattern when JMS isn't available.)
- **Aggregation** — collect messages with the same correlation ID over a time window, then process the batch.
- **Cached lookup** — store a slow-to-fetch reference data table for N hours; refresh on miss.

### Design notes

- **Keys must be deterministic and unique.** Using `${exchangeId}` is wrong — it's unique per run, never reused, so lookups always miss.
- **Set TTL.** Without expiry, the Data Store grows forever. Pick a TTL that matches the business semantics — for idempotency keys on orders, 7 days is generous; for transient retry queues, hours.
- **Don't store secrets** — Data Store entries are visible to operations.
- **Don't store > 1 MB per entry casually** — payload size adds up; the Data Store has a tenant quota.
- **Visibility** in *Monitor → Manage Stores → Data Stores* — operations can browse, query, and delete entries from the cockpit.

## 3. Idempotency pattern — the lab's centerpiece

The classic idempotency guard:

```
Sender ─► Get from Data Store (key = ${header.X-Idempotency-Key},
                                Throw Exception on Failure = NO)
        ─► Router on ${header.SAP_DatastoreEntryFound}
                ├─ true  ─► set body = stored response ─► End (return cached)
                └─ false ─► (process normally) ─► Write to Data Store
                            ─► (continue to ProcessDirect, JMS, etc.)
```

The **`X-Idempotency-Key`** is supplied by the caller — typically a UUID the caller generates per business intent. Two calls with the same key represent the same business operation; the iFlow guarantees at-most-once processing.

The **stored payload** is whatever you want returned on the cached path — usually the response body (sequence number, status, etc.). Pick a small JSON envelope:

```json
{ "status": "accepted", "orderSequence": "ORD-0042", "orderId": "C-3001" }
```

### What goes wrong

- **Caller doesn't send a key** — script the iFlow to generate a UUID *if* the header is missing. But then idempotency is gone — every call has a fresh key. Decide: reject (better for a public API) or fall back (better for internal systems).
- **TTL too short** — caller retries after the TTL window expires; iFlow reprocesses. Document the window publicly.
- **Race condition** — two concurrent calls with the same idempotency key both miss the store, both proceed, both write. The Data Store's per-entry locking helps but isn't bulletproof for "check-then-write" without an explicit `If-None-Match` semantic. For high-concurrency idempotency, the safer pattern is *atomic upsert with a uniqueness constraint downstream*. For our lab volume, the basic pattern is fine.

## 4. Number Range — the boring artifact you'll always need

A **Number Range** is a persistent counter with format/min/max/wrap configuration. You create the artifact with:

- **Name**: `nr_<your_initials>_OrderSequence` (project naming: `nr_<your_initials>_<purpose>` — the `<your_initials>` infix isolates trainees on the shared tenant).
- **Description**: prose for ops.
- **Format**: `ORD-{nnnn}` — the placeholder is `{nnnn}` for zero-padded N digits, `{nn}` for 2 digits, etc.
- **Min**: `1`.
- **Max**: `99999999` (large; enough for years of orders).
- **Field length**: number of digits (matches the format placeholder).
- **Rotate**: `Yes` / `No` — whether to wrap to Min after Max. For `nr_<your_initials>_OrderSequence`, **No** (you don't want to recycle order numbers).
- **Current value**: visible in *Monitor → Manage Stores → Number Ranges*; resettable by ops in dev/test.

### Pulling the next value

There is a dedicated **Number Range** flow step. Configure:

- *Number Range Name*: `nr_<your_initials>_OrderSequence`.
- *Property* / *Header* to write to: e.g. `X-Order-Sequence`.

The runtime calls the Number Range service, gets the next atomic value, formats it, writes it. **Atomic** — no two concurrent runs get the same number.

### Why use a Number Range vs. UUID vs. timestamp?

| Approach | Pros | Cons |
|---|---|---|
| Number Range | Sequential, human-readable, gap-free under normal operation, atomic | Cross-tenant transport requires care; resets in dev are deliberate |
| UUID | Trivially unique, no central bottleneck | Not human-readable; impossible to "guess the next one" |
| Timestamp | Sortable | Collisions on high-throughput; not human-readable across timezones |

For business-visible references (purchase order numbers, claim numbers, ticket IDs), **Number Range wins** — humans can quote them on the phone, they sort obviously, the format is enforced.

For internal correlation IDs, **UUID wins** — no central bottleneck, no transport surprises.

For our lab, the Order Sequence is "sort-of business visible" (the 202 response includes it) — Number Range is the right call.

## 5. Number Range gotchas

- **Number Ranges are tenant-local artifacts.** Transporting an iFlow that uses `nr_<your_initials>_OrderSequence` from Dev → QA via CTM does *not* automatically include the Number Range artifact unless it's in the package. Confirm before transport.
- **The current value transports too** — and that's almost always wrong. You want QA to start at 1, not at "the value Dev was at when transported". Reset in QA after transport. Operations procedure.
- **Format `{nn}` vs `{nnnn}`** — `{nn}` will truncate or wrap when the value exceeds 2 digits. Pick a generous width.
- **Max wrap** — if Rotate=Yes and you hit Max, you start over at Min, *issuing duplicate values*. Always Rotate=No for business references.
- **Concurrent peak** — under sustained load, the Number Range service has a small write latency per call (~5-10ms). Not usually a bottleneck, but on sustained 1000 RPS bursts you'll see it. Cache strategies (pre-allocate batches) exist; we won't lab them.

## 6. Global Variables — the tempting wrong answer

A **Global Variable** is a tenant-scoped name → string slot:

- Read: in a Content Modifier or Groovy via `${global.<name>}` / specific API.
- Write: via the *Write Variables* flow step (mode = *Global*).

Tempting uses (and why most are wrong):

- **"Last processed timestamp"** for a polling iFlow — *valid*. Globals were designed for this.
- **"Counter"** to track how many messages an iFlow has processed — *wrong*. Read-modify-write isn't atomic; under concurrency you'll lose updates. Use a Number Range or external counter.
- **"Current configuration value"** — *wrong*. Use a Value Mapping or Externalized Parameter; those are version-controlled and transport-aware.
- **"Cached token"** — *wrong*. OAuth2 token caching is the runtime's job, not yours.
- **"Shared state between iFlow A and iFlow B"** — *almost always wrong*. Use a Data Store entry with a known key, or pass via JMS, or pass via ProcessDirect headers.

The pattern that's *right* for Globals is exactly the one CURRICULUM-listed: **a high-water mark or last-success marker** for a periodic sync iFlow. Anything more complicated wants a different artifact.

For the Order Hub, Globals are not needed. We mention them so trainees recognize when a colleague suggests one — and can push back.

## 7. Read-modify-write atomicity — why this matters

| Artifact | Atomic operations |
|---|---|
| Data Store | Per-key locking on Write/Get/Delete; safe for parallel writers if each writes a *different* key. *Not* safe for "Get → modify → Write" of the same key under concurrency. |
| Number Range | Atomic next-value read. Each caller gets a unique number. |
| Global Variable | **Not atomic.** Concurrent writes silently lose. |

The Data Store gotcha: the natural idempotency check ("Get; if missing, Write") is **not** atomic across two concurrent runs. Two callers with the same key can both miss, both write. The runtime's per-entry locking helps but doesn't eliminate this race entirely. Mitigations:

- **Use a Number Range as a tiebreaker** — the second caller writes with a slightly later sequence and the consumer can de-dup downstream.
- **Push idempotency to the consumer** — the downstream API treats `X-Idempotency-Key` as the de-dup key with its own atomic upsert.
- **Accept the race for low-volume APIs** — at 5 RPS the race is unobservable; at 500 RPS it isn't.

For our lab volume, accept the race and document it.

## 8. Variable visibility, transports, and ops

The cockpit's *Monitor → Manage Stores* section has:

- **Data Stores** — list, browse entries, edit, delete.
- **Variables** — list, edit, delete (Globals).
- **Number Ranges** — list, edit current value (in Dev/QA only — production should be locked down).

These are **operational tools, not developer tools**. In production, only the on-call team should be editing these. In Dev/QA, you'll edit them all the time during testing — expect to reset Number Ranges, clear Data Stores, tweak Variables.

CTM transports include the *artifact definitions* of Data Stores, Number Ranges, and Globals attached to the package — but **not** the runtime data (entries, current value, variable value). This is correct: you don't want production order numbers to bleed into Dev. But it means **post-transport setup** is part of the deployment runbook (covered in Week 4).

## 9. Storage limits & quotas

| Artifact | Tenant quota (typical) |
|---|---|
| Data Store entries | ~32 GB total across all stores |
| Per-entry size | 25 MB hard limit; aim for < 1 MB |
| Number Ranges | Unlimited count; each holds one value |
| Global Variables | Unlimited count; each holds one small string |

Watch the **Data Store quota** — runaway TTL-less stores fill 32 GB faster than you'd think. Set TTL on every entry by default; remove only when you have a documented reason.

## 10. The Order Hub state model after today

```
Inbound POST
    │
    ▼
roiam_logIncoming (from sc_<your_initials>_OrderHubHelpers)   ← Day 3.3
    │
    ▼
Get from Data Store (key = X-Idempotency-Key)                 ← TODAY
    │
    ├─ found ─► return cached response ─► End (202 + cached body)
    │
    └─ not found ─► continue
    │
    ▼
Number Range Step → X-Order-Sequence = ORD-NNNN               ← TODAY
    │
    ▼
ProcessDirect → roi_<your_initials>_OrderTranslator           ← Day 3.3
    │
    ▼
Write to Data Store (key = X-Idempotency-Key,                 ← TODAY
                     value = response envelope,
                     TTL = 7 days)
    │
    ▼
JMS receiver → roi.orderhub.outbound.<your_initials>          ← Day 3.2
    │
    ▼
Set response body + 202 → End
```

Notice the **Write to Data Store happens AFTER ProcessDirect succeeds** — you only cache on success. If the translation throws, no Data Store write, the next retry will reprocess. Correct semantics.

## 11. Common mistakes

- **Writing the Data Store *before* the work** — caches a response that doesn't exist yet. Always cache after success.
- **Using `${exchangeId}` as the Data Store key** — each run has a fresh exchange ID, so lookups always miss; the store grows but never serves anyone.
- **No TTL on Data Store entries** — runaway storage growth.
- **Number Range Rotate=Yes for business references** — eventual duplicates.
- **Editing a Number Range's current value in production "to skip a few"** — gap-detection downstream now thinks orders were lost. If you need to skip, document it explicitly with a ChangeLog entry.
- **Using a Global Variable as a counter** — lost updates under concurrency.
- **Storing secrets in a Data Store** — operations can browse it. Don't.

---

## Hands-on lab — Idempotency guard + sequence number on the Order Hub

> Time: ~3 hours. Goal: add a Data Store-backed idempotency check and a Number Range-backed sequence number to `roi_<your_initials>_OrderHub`. By end of lab, repeated calls with the same `X-Idempotency-Key` return the cached response without re-enqueueing JMS, and every accepted order has an `ORD-NNNN` sequence visible in the response and the canonical XML body.

### Setup

- `roi_<your_initials>_OrderHub` from Day 3.3 (with ProcessDirect call to translator + JMS enqueue + `sc_<your_initials>_OrderHubHelpers` reference).
- Permission to create Data Store and Number Range artifacts.

### Steps

1. **Create the Number Range artifact `nr_<your_initials>_OrderSequence`.**
   - In the *Training* package (or in your iFlow's package), *Add → Number Range*.
   - Name: `nr_<your_initials>_OrderSequence`.
   - Description: `Sequential reference number for orders accepted by roi_<your_initials>_OrderHub.`
   - Min: `1`
   - Max: `99999999`
   - Format: `ORD-{nnnn}`
   - Field length: `4` (will pad to 4 digits — `ORD-0001`, `ORD-0002`, etc., and grow naturally beyond when needed)
   - Rotate: **No**
   - Save and deploy the artifact.

2. **Add the Number Range step to `roi_<your_initials>_OrderHub`.**
   - Open `roi_<your_initials>_OrderHub`.
   - Insert a *Number Range* flow step **after** the idempotency check (which you'll add in step 3) but **before** the ProcessDirect call.
   - *Number Range Name*: `nr_<your_initials>_OrderSequence`.
   - *Header* (or *Property*): write to **header** `X-Order-Sequence` — needs to be a header so the ProcessDirect allow-list propagates it to the translator (allow-list already includes `X-Order-Sequence` from Day 3.3).

3. **Add the Data Store idempotency check at the start.**
   - Right after the `roiam_logIncoming` script, add a *Data Store Get* flow step.
   - **Data Store Name**: `ds_<your_initials>_OrderIdempotency` (will be created on first deploy).
   - **Entry ID**: `${header.X-Idempotency-Key}`.
   - **Throw Exception on Failure**: **uncheck** — we want to handle "not found" with a router, not a throw.
   - On success, the runtime automatically sets a **header** — `SAP_DatastoreEntryFound` — to `true` or `false`. It's a header, not a property, and the name is fixed (not tenant-dependent).
   - Add a *Router* after the Get step:
     - Branch 1: `${header.SAP_DatastoreEntryFound} = 'true'` → set HTTP response code 202 → End. (Returning the cached body that the Get step put in `message.body`.)
     - Branch 2: default → continue to Number Range + ProcessDirect + JMS path.

4. **Reject calls without an idempotency key (or generate one).**
   - In the input Content Modifier (right before the `roiam_logIncoming` script), check whether `X-Idempotency-Key` is present.
   - For the lab, **reject** if missing — set the response body to `{ "error": "X-Idempotency-Key header required" }`, response code 400, and route to End. Use a Router or a small Groovy script.
   - Lifelong-lab caveat: in production, you'd document this in the iFlow's API contract / OpenAPI.

5. **Add the Data Store Write at the end of the success path.**
   - Right **after** the ProcessDirect call (canonical XML now in body), but **before** the JMS receiver, write the response envelope to the Data Store.
   - You need the *response envelope* in the body, not the canonical XML, so wrap with a Content Modifier:
     ```json
     { "status": "accepted", "orderSequence": "${header.X-Order-Sequence}", "orderId": "${header.orderId}" }
     ```
     — store this as a property `responseEnvelope` first, then keep the canonical XML in the body for JMS.
   - Insert a *Data Store Write* step:
     - **Data Store Name**: `ds_<your_initials>_OrderIdempotency`.
     - **Entry ID**: `${header.X-Idempotency-Key}`.
     - **Body** to store: from property `responseEnvelope`. (You'll need a Content Modifier to swap body ↔ property around the Write step. Alternative: write a small Groovy script that calls the Data Store API directly — but we'll keep it declarative.)
     - **TTL**: `604800` seconds (7 days).
     - **Overwrite Existing Message**: *No* (we want a one-shot write).

6. **Set the response.**
   - At the very end of `roi_<your_initials>_OrderHub` (after the JMS receiver), set the body to the `responseEnvelope` property and response code to `202`.
   - Save → version → deploy.

7. **Test the happy path.**
   ```bash
   IDEMPOTENCY_KEY=$(uuidgen)
   curl -X POST "<runtime-url>/http/orderhub/orders/<your-initials>" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -H "X-Idempotency-Key: $IDEMPOTENCY_KEY" \
        -d '{ "orderId": "C-3001", "customer": "Acme GmbH", "totalAmount": 1500, "lines": [{"sku": "S-1", "quantity": 2, "unitPrice": 750}] }'
   ```
   - Confirm 202 with body `{ "status": "accepted", "orderSequence": "ORD-0001", "orderId": "C-3001" }`.
   - In *Monitor → Manage Stores → Number Ranges → nr_<your_initials>_OrderSequence*, confirm current value `1` → `2` after the call.
   - In *Monitor → Manage Stores → Data Stores → ds_<your_initials>_OrderIdempotency*, confirm an entry with key matching `$IDEMPOTENCY_KEY`.

8. **Test the idempotency guard.**
   - Re-run the **same `curl` with the same `$IDEMPOTENCY_KEY`** (don't regenerate it).
   - Confirm 202 with the *same* `orderSequence: ORD-0001` — proving the cached response is being returned.
   - In *Monitor → Message Processing*, confirm the *second* run was short — it didn't pull a new Number Range value, didn't call ProcessDirect, didn't enqueue JMS.
   - In *Monitor → Manage Stores → Number Ranges*, confirm the current value did **not** advance.

9. **Test a fresh call (different key).**
   - New `$IDEMPOTENCY_KEY` (`uuidgen` again).
   - Same payload otherwise.
   - Confirm 202 with `orderSequence: ORD-0002` — sequence advanced.
   - Confirm a *new* Data Store entry under the new key.

10. **Test the missing-key rejection.**
    ```bash
    curl -X POST "<runtime-url>/http/orderhub/orders/<your-initials>" \
         -H "Authorization: Bearer <token>" \
         -H "Content-Type: application/json" \
         -d '{ "orderId": "C-3002", "customer": "Beta SE" }'
    ```
    - Expect 400 with `{ "error": "X-Idempotency-Key header required" }`.

11. **Inspect the Data Store from the cockpit.**
    - *Monitor → Manage Stores → Data Stores → ds_<your_initials>_OrderIdempotency → Entries*.
    - Click into one entry — see the stored JSON envelope.
    - Note the *Expires At* timestamp ~7 days out — TTL working.

### Failure cases to provoke

- **Use `${exchangeId}` as the Data Store key** instead of `${header.X-Idempotency-Key}` — verify lookups always miss, store grows monotonically, idempotency does nothing. Fix.
- **Set TTL to 0** (or omit it) — entries never expire. After a few hundred lab runs, the store starts looking unhealthy. Lesson: always TTL.
- **Set Number Range Rotate to Yes with Max=10** — pump 11 orders, watch the 11th get sequence `ORD-0001`. Eventual duplicate. Lesson: always Rotate=No for business refs.
- **Skip the "Write Data Store after ProcessDirect succeeds" rule** — write *before* the work. Cause a translator failure. Notice the cache holds a response for an order that never made it to JMS. Replay returns the wrong success message. Fix the order of steps.
- **Reset the Number Range to `1` mid-test** — *Monitor → Manage Stores → Number Ranges → Edit*. Send a fresh order. Watch it get `ORD-0001` — duplicate of the first order's sequence. Lesson: never reset NR in production.

---

## Reference card excerpt — Day 3.4

- **Data Store** — keyed payload persistence. Set **TTL**. Use deterministic keys. Visible in *Monitor → Manage Stores*.
- **Number Range** — atomic counter with format. Naming `nr_<your_initials>_<purpose>`. Format `ORD-{nnnn}`. **Rotate=No** for business refs.
- **Global Variable** — small string slot. Right answer for **last-success markers** in polling iFlows. Wrong answer for counters, configs, secrets, shared state.
- **Idempotency pattern**: Get (no throw) → Router → on found return cached → on miss process → Write after success.
- **Cache the response *after* the work succeeds**, never before.
- **TTL is mandatory** on Data Store entries. 7 days for idempotency keys is a sensible default.
- **Read-modify-write of Globals is not atomic.** Use a Number Range or Data Store.
- **Transports carry definitions, not runtime data.** Reset Number Ranges + clear Data Stores after Dev → QA promotion.
- **Don't store secrets in Data Store.** Operations can browse it.
- **Rejecting calls without `X-Idempotency-Key`** is the correct API contract for a public endpoint; falling back to an auto-generated UUID is the wrong default.
