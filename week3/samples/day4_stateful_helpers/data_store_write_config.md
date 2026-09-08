# Data Store *Write* flow step — configuration reference

The *Write* step persists the current message under a key. On the Order Hub it's the cache-on-success step — **after** ProcessDirect completes, **before** JMS receiver enqueues. Never before the work.

## Fields

| Field | Lab value | Notes |
|---|---|---|
| **Data Store Name** | `ds_<your_initials>_OrderIdempotency` | Must match the *Get* step's name exactly |
| **Visibility** | *Integration Flow* | Same scope as the Get step |
| **Entry ID** | `${header.X-Idempotency-Key}` | Same key the Get step looked up |
| **Retention Threshold for Alerting (sec)** | leave default | Ops-side; not relevant for the lab |
| **Expiration Period (sec)** | `604800` | 7 days. Mandatory — never deploy a Write step with no TTL |
| **Encrypt Stored Message** | Yes (recommended) | Keeps payload at rest encrypted on tenant disk |
| **Overwrite Existing Message** | No | One-shot cache; if you see an "entry already exists" error in the MPL you've got a real race condition to handle, not a config to relax |
| **Include Message Headers** | No | The cached envelope is self-contained; don't bloat the entry with headers |

## What gets written

The Write step persists **whatever's currently in `message.body`** under the configured Entry ID. So the body must contain *the response envelope*, not the canonical XML you handed to ProcessDirect, and not the inbound JSON.

The trick: shape the body around the Write step using Content Modifiers.

```
ProcessDirect returns (body = canonical XML)
    │
    ▼
Content Modifier
    Property: canonicalOrderXml = ${in.body}    ← snapshot XML for JMS
    Body:     <use a JSON template referencing headers>
                {
                  "status": "accepted",
                  "orderSequence": "${header.X-Order-Sequence}",
                  "orderId":       "${header.orderId}"
                }
    │
    ▼
Data Store: Write                                ← persists the JSON envelope
    │
    ▼
Content Modifier
    Body: ${property.canonicalOrderXml}          ← restore XML for JMS
    │
    ▼
JMS Receiver → roi.orderhub.outbound.<initials>
```

The `roiam_buildResponseEnvelope.groovy` script in this folder is an alternative to the first Content Modifier — handy if you want logging/edge handling around the envelope construction.

## Why "after ProcessDirect, before JMS"

| Position | Behavior |
|---|---|
| Write **before** the work | Caches a success response that hasn't been earned yet. Translator fails → no JMS, but cache says "accepted". Replay returns success for an order that was never processed. **Wrong** |
| Write **after** the work but **before** JMS | Cache is set only if the synchronous part succeeded. If JMS enqueue fails, the cache is set but the order didn't go through — replay returns the cached success. Acceptable trade-off because JMS receiver failures are rare and we want at-most-once for the synchronous portion. (Document the rare edge case.) |
| Write **after** JMS | Cache is set only if everything succeeded. Best correctness; cost is that under load, JMS broker latency briefly widens the duplicate-processing window. Fine for our lab volume |

The lab puts Write between ProcessDirect and JMS. Production can move it after JMS if duplicates-on-JMS-failure is a concern.

## Common Write-step mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Write step at the start of the flow | Repeated retries within TTL all return the original incorrect/stale response | Move to after the success path |
| Expiration Period blank or 0 | Entry never expires; Data Store fills tenant quota over weeks | Set a TTL appropriate to the business window (7 days for idempotency keys is sensible) |
| Body is the canonical XML, not the response envelope | Cached "response" contains XML instead of the JSON the caller expects on replay | Wrap the Write step with Content Modifiers to shape the body |
| Overwrite Existing Message = Yes used as a workaround for some other bug | Hides the real concurrency issue; the *second* call still re-processes despite the first having written the cache | Investigate the race; don't just allow overwrite |
| Encrypt Stored Message = No on PII-bearing payloads | Operations browsing the Data Store sees PII in plaintext | Always Yes when the envelope contains anything customer-identifying |

## Cockpit verification

After a happy-path run, open *Monitor → Manage Stores → Data Stores → ds_<initials>_OrderIdempotency → Entries*. You should see:

- One row per unique `X-Idempotency-Key`.
- Click the row → *Payload* tab shows the JSON envelope.
- *Expires At* shows ~7 days in the future.
- *Created At* matches the MPL timestamp of the Write step.

If after a happy-path run the entries list is empty, the Write step never executed — almost always because an earlier step threw an exception that wasn't caught by the success path. Check the MPL for that run.
