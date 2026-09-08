# Storage quotas & cleanup — Data Store, Number Range, Global Variable

Per-tenant limits and the operational queries you'll use when one of them starts to fill.

## Quotas

| Artifact | Typical quota (Standard plan) | Hard limit |
|---|---|---|
| Data Store — total payload across all stores | ~32 GB | Tenant-dependent |
| Data Store — per-entry size | recommended < 1 MB | 25 MB hard limit |
| Data Store — entry count | no fixed cap; bounded by total bytes | Tenant-dependent |
| Number Range artifacts | no fixed cap | n/a |
| Number Range — value range | up to 999999999999 (12 digits) | Configurable per range |
| Global Variables | no fixed cap | small per-value size (~4 KB) |

Quotas vary by service plan and tenant tier. Confirm in the *Capacity* tab of *Manage Integration Content* on your tenant. Don't hard-code limits in iFlow logic; check the cockpit.

## Where to watch

*Monitor → Manage Stores → Overview*:
- Total Data Store usage (GB).
- Entry count per Data Store.
- Number Range count.
- Variable count.

Set a custom alert (Week 4 covers this) for Data Store usage exceeding 80% — that's the threshold where you start cleaning, not the threshold where you're in trouble.

## Cleanup queries you'll actually use

### List Data Stores by size

*Monitor → Manage Stores → Data Stores* sorted by Size descending. The top of the list is where to focus cleanup.

### Bulk delete stale entries by prefix

*Manage Stores → Data Stores → ds_<name> → Entries → Filter by Entry ID prefix → Select All → Delete*.

Caveat: deleting entries in the middle of an idempotency window breaks idempotency for those keys. Coordinate with whoever owns the integration before bulk-deleting.

### Reset a runaway TTL-less store

If a store has no TTL and is growing:

1. Fix the iFlow's Data Store Write step to add a TTL. Redeploy.
2. Existing entries still have no TTL — they won't expire on their own.
3. Bulk-delete existing entries via cockpit, or wait if the business can afford to keep them.

### Identify what's writing to a store

*Manage Stores → Data Stores → ds_<name> → Entries → click entry → Source*. The MPL run that created it is linked. Click through to see which iFlow.

## Operational sizing rules of thumb

- **Idempotency keys**: 1 KB average entry size, 7-day TTL, 10,000 orders/day → 70k entries × 1 KB = 70 MB. Negligible.
- **Retry queue**: 10 KB average payload, 1-day TTL, 0.1% retry rate of 10,000 orders/day → 10 entries × 10 KB = 100 KB. Negligible.
- **Aggregation buffer**: 5 KB × 1000 buffered messages × 5 batches × 1-hour TTL → 25 MB. Modest.
- **Cached reference data**: 100 KB × 1 entry × 4 stores × indefinite TTL → 400 KB. Negligible.

The only realistic way a Data Store exceeds quota is **missing or absurdly long TTL** on an idempotency-class store. Set TTL.

## Per-entry size — what to do with large payloads

If a payload routinely exceeds 1 MB:

1. **Don't store the full payload.** Store a reference (e.g. JMS message ID, downstream API response ID, file location).
2. **Strip non-essential fields.** Cache only what's needed on replay (response envelope, not the full canonical XML).
3. **Compress.** Gzip the body before Write; ungzip after Get. Adds latency but reduces footprint.
4. **Re-think the pattern.** If you're caching a 5 MB response, maybe what you actually want is a downstream-supplied idempotency-aware API, not a cache.

The 25 MB hard limit is rarely a problem in well-designed integrations. If you're hitting it, you're using Data Store for the wrong thing.

## Number Range capacity

Functionally unlimited. A range with Max=99999999 at 10,000 increments/day runs for 27 years before exhausting. Not a concern.

The Number Range *service* has rate limits — under sustained 1000+ RPS, you'll see latency on the increment call. Solutions exist (pre-allocate batches via a script that reserves N values at once) but aren't needed at lab volume.

## Global Variable capacity

Functionally unlimited count. Each value is small (single string, typically < 1 KB). No quota concern in practice.

The risk with Globals isn't capacity — it's losing data through non-atomic writes. See `global_variable_when_to_use.md`.
