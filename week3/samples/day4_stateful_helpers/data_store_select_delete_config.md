# Data Store *Select* and *Delete* — configuration reference

Less common than Get/Write, but worth knowing because they're how operations and batch-replay iFlows talk to the store.

## Select

Returns a list of entries matching a query — useful for batch operations (retry queue replays, time-window aggregation, "give me everything for customer X").

### Fields

| Field | Example value | Notes |
|---|---|---|
| **Data Store Name** | `ds_<your_initials>_OrderIdempotency` | Same store |
| **Visibility** | *Integration Flow* | Same scope |
| **Number of Polled Messages** | `100` | Hard cap per Select call. Tune for downstream throughput |
| **Get Options → Delete on Completion** | No (default) | Yes if you want a destructive read (rare for idempotency stores; common for retry queues) |
| **Sort Order** | Oldest First | For FIFO replay semantics |

### What you get back

The Select step produces a **multipart message** where each part is one stored entry. Downstream:

- *Splitter* (Iterating, on multipart): one iteration per entry.
- Each iteration sees one entry's body in `message.body` and the entry's metadata in headers (`SAP_DataStoreEntryID`, `SAP_DataStoreCreatedAt`, etc.).

### Lab-relevant use case (not in Day 3.4 itself)

A scheduled batch-replay iFlow could *Select* all entries from `ds_<initials>_OrderRetryQueue` whose `Created At` is older than 5 minutes, then iterate and replay. We don't build this in Day 3.4 — it's mentioned to show *why* Select exists.

## Delete

Removes an entry by key.

### Fields

| Field | Example value | Notes |
|---|---|---|
| **Data Store Name** | `ds_<your_initials>_OrderIdempotency` | Same store |
| **Visibility** | *Integration Flow* | Same scope |
| **Entry ID** | `${header.X-Idempotency-Key}` | Specific entry |
| **Throw Exception on Failure** | No | Unless the absence of the entry means something's wrong |

### When to use

| Use case | Right call |
|---|---|
| Idempotency key TTL expired, but caller knows they want a fresh attempt now | Delete then continue. Document why |
| Operations needs to flush a poisoned cache entry | Use the cockpit (*Monitor → Manage Stores → Data Stores → Entries → Delete*) — not a flow step |
| Retry queue: entry successfully replayed | Delete on Completion = Yes on the Select that read it (cleaner than a separate Delete) |
| Test cleanup | Use the cockpit; don't ship test-cleanup flow steps to production |

## Cockpit-driven equivalents

For everything Select and Delete do via flow steps, the cockpit's *Monitor → Manage Stores → Data Stores* offers a manual UI:

- **Entries** tab → filter, paginate, click into.
- Per-entry: View, Download, Delete.
- Bulk delete by Entry ID prefix.

Use the cockpit for ad-hoc ops work. Use flow steps for repeatable, in-iFlow logic.

## Common Select/Delete mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Select with no cap | Pulls 50,000 entries on a hot store; downstream OOMs | Always cap. Page if needed |
| Select + iterate + Delete-per-entry instead of Select-with-Delete-on-Completion | Two round-trips per entry; visible latency hit at scale | Use Delete on Completion in the Select |
| Using Delete as "clean up the test entry I just made" in the same iFlow | Test artifacts in production code | Test cleanup belongs in tests, not in the iFlow |
| Forgetting Sort Order on Select | Random order; replay may be out-of-sequence | Set explicitly (Oldest First for FIFO) |
