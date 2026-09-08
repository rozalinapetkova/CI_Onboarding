# Data Store — `CustomerEcho`

Data Store is **tenant-local key-value persistence**. Backed by HANA. Used for idempotency keys, async correlations, audit trails, small reference data.

## Configuration on the Data Store Write step

| Setting | Value | Notes |
|---|---|---|
| Data Store Name | `CustomerEcho` | Convention: PascalCase, no `ds_` prefix on the *iFlow-local* form. The tenant-wide `Manage Stores` view shows it under the iFlow's namespace. |
| Visibility | `Integration Flow` | Day 1.4 default. Use `Global` only when multiple iFlows must share entries. |
| Entry ID | `${header.customerId}` | Camel simple expression. Will be `C-1001` for the happy path. |
| Retention Threshold (days) | `7` | Day 1.4 default. Long-term audit uses 30+. |
| Encrypted Storage | `true` | Always on. Free; no reason to turn off. |
| Overwrite Existing Message | `true` | The lab is upsert semantics — last-write-wins by customerId. |

## Pitfalls

1. **Empty Entry ID** — if `customerId` is missing from the header allow-list (see `processdirect_handoff.md`), the key resolves to empty string. Every call overwrites the same row. Looks fine in tests with one customer; broken at scale.
2. **`Overwrite Existing Message = false` with a duplicate key** — throws `MessageStoreException`. Catch in an Exception Subprocess (Week 4) if you actually want write-once semantics.
3. **30-day retention** doesn't mean "kept for 30 days no matter what". The tenant background sweeper runs roughly daily; entries past their threshold disappear on the next sweep. If you need precise expiry, use Number Range or external persistence.

## How to inspect

Cockpit → **Monitor → Manage Stores → Data Stores → `CustomerEcho`**. Click an entry to see headers + payload. Cannot edit through the UI — only delete.

## When NOT to use Data Store

- Anything you need to query by something other than the key. Data Store is key/value, full-stop.
- Anything that needs cross-tenant visibility — use an external HANA service.
- High-volume idempotency (>10K writes/min sustained) — use Number Range or external Redis/HANA.
