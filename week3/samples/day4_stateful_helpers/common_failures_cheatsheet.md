# Stateful artifacts — symptoms and causes

## Data Store / idempotency failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Every call is "fresh" — Number Range advances each retry, JMS enqueues twice for the same idempotency key | Data Store Get step uses `${exchangeId}` as the key (or some other per-run unique value) | Change Entry ID to `${header.X-Idempotency-Key}` |
| First call returns the iFlow's error JSON instead of running the order | "Throw Exception on Failure" is checked on the Get step — cache miss is firing the Exception Subprocess | Uncheck it. Branch on the found-property via Router instead |
| Cache hit returns an empty body | Get step's "Output Body" is set to *As Property*, not *As Body*; Router's true-branch never sets the body back | Output Body = *As Body*; or restore from the property in the true-branch's Content Modifier |
| `${property.ds_found}` is always null in the Router | Tenant version uses a different property name (e.g. `DataStore.found`); your Router condition checks the wrong name | Run a test, inspect *Run Steps → Properties* tab on the Get step, use the actual name |
| Data Store entries pile up forever | Write step's Expiration Period is 0 or blank | Set TTL (604800 = 7 days for idempotency) |
| Cache returns success but the order never made it downstream | Write step is *before* ProcessDirect/JMS; an error after Write left a cached success that wasn't earned | Move Write to after the success path |
| Two concurrent calls with the same key both proceed to ProcessDirect | Per-entry locking helps but doesn't fully prevent the check-then-write race at high concurrency | At lab volume, acceptable. At production volume, push idempotency to the downstream API |
| `EntryAlreadyExists` exception under load | Overwrite=No + concurrent writes for the same key | Investigate the race; don't relax Overwrite=Yes as a workaround |
| Entries appear under Entry IDs you didn't expect (e.g. raw camelExchangeId-format strings) | Some step downstream is writing to the same store with a different key scheme | Audit all Data Store Write steps in all iFlows that share this store name |
| Cockpit shows Data Store grew 5 GB overnight | Likely a TTL-less store + traffic spike | Add TTL, bulk-delete stale entries |

## Number Range failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Two orders have the same `ORD-NNNN` | Rotate=Yes hit the Max; range wrapped | Change Rotate to No, raise Max if needed |
| `ORD-100` next to `ORD-9999` — width inconsistent | Format `{nnnn}` only pads up to 4 digits; beyond that the format grows naturally | Either accept (it's documented behavior) or raise Field Length and Format width |
| After CTM, QA's first order is `ORD-0413` instead of `ORD-0001` | Number Range definition transported but operations reset hadn't been done | Reset current value via *Manage Stores* after each transport |
| Number Range step throws "range not found" | The range artifact wasn't deployed, or name typo | Confirm artifact deployed (*Started* in Manage Integration Content); verify spelling exactly |
| Number Range advances even on cache hits | The Number Range step is *before* the Data Store Router | Move Number Range step to after the cache-miss branch |
| Number Range increment latency causes timeouts under load | Rare. Pre-allocation pattern needed at scale | Out of scope for the lab; see day-module note |
| Operations reset the current value mid-production "to skip ahead" | Downstream gap detection now sees missing sequences | Document any manual NR adjustments in the iFlow's ChangeLog |

## Global Variable failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Counter values drift below reality | Two concurrent writes — second clobbers first | Don't use Globals as counters. Use a Number Range |
| Last-success timestamp resets to 1970 | The variable doesn't exist yet, and the read code didn't default-handle missing | `accessor.getVariable(name) ?: "1970-01-01T00:00:00Z"` |
| Shared state between iFlow A and iFlow B intermittently inconsistent | Globals aren't a transaction boundary; ordering of writes by different iFlows is undefined | Use JMS or Data Store as the integration point |
| Variable disappeared after redeploy | An ops user deleted it from *Manage Stores* | Documented operational risk; rely on read-side defaults |
| Variable value mysteriously changes | Multiple iFlows write to the same variable name | Audit; rename to namespace by iFlow |

## Transport / CTM failures

| Symptom | Likely cause | Fix |
|---|---|---|
| iFlow deployed in QA but runtime says "data store not found" | Data Store definition wasn't in the transported package | Re-export the package including all referenced artifacts |
| Idempotency works in Dev, fails in QA | Externalized Parameter (e.g. the Data Store name) not configured in QA | Configure parameters post-deploy in QA |
| First QA order has wrong sequence | NR current value not reset after CTM | Reset via *Manage Stores* |
| OAuth2 calls fail in QA after CTM | Credentials not re-entered in QA's Security Material | Add credentials with same alias as Dev, but QA-specific secrets |

## "Looks fine but isn't" — silent failures

These produce no errors, no rejected messages, no alerts. Only an attentive reader of the MPL or the Data Store would spot them.

1. **Cache hit returns *yesterday's* envelope with *yesterday's* sequence number.** The caller resent a successfully-processed order. The cache works — but the caller's UI shows the old reference. Document this in the caller's UI: "Order already accepted as ORD-0042 on 2026-06-21".

2. **Cache hit returns a successfully-processed-but-now-cancelled order's envelope.** Cancellation should invalidate the cache; if it doesn't, replays return a stale "accepted" status for an order that's now in a different state. Cancellation flow must Delete the corresponding Data Store entry.

3. **Number Range advanced between the Router and the Number Range step.** If the iFlow has a path where Number Range is called but the path doesn't complete (e.g. error before ProcessDirect), the sequence is burned without being assigned. Acceptable at low volume; pattern to watch in audits — "missing ORD-0042 in the JMS queue, the order was rejected after NR but before publish."

4. **Data Store entry's TTL is 7 days, but business retention rule says 30 days.** Operations reads a 14-day-old replay attempt, fails the idempotency check, processes the order again, customer is double-billed. Match TTL to the business window, not a convenient default.

5. **Two iFlows in different packages write to the same Data Store with same key namespacing.** Cache pollution across business domains. Use distinct Data Store names per iFlow unless cross-iFlow sharing is intentional.

6. **Number Range visible to a colleague's Order Hub copy.** On the shared lab tenant, `nr_<your_initials>_OrderSequence` is yours; a colleague's `nr_<their_initials>_OrderSequence` is theirs. But if both name with the same `<initials>` due to a typo, increments interleave and both Order Hubs see bizarre sequence values. Verify names on the shared tenant.

## When in doubt

For every Data Store / Number Range / Global question, the cockpit is authoritative:

- **What's actually in the store?** *Monitor → Manage Stores → Data Stores → Entries*.
- **What value is the Number Range at?** *Monitor → Manage Stores → Number Ranges*.
- **What did the iFlow see when it called the Get step?** MPL → Run Steps → Get step → Properties tab.
- **What did the iFlow write to the Data Store?** MPL → Run Steps → Write step → Body tab.

The runtime tells you, with timestamps. Trust the runtime over the spec.
