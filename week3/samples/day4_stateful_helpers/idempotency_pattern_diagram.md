# Order Hub state model — canvas after Day 3.4

The Order Hub iFlow now combines Day 3.2 (JMS), Day 3.3 (ProcessDirect + Script Collection), and Day 3.4 (Data Store + Number Range).

## Canvas (ASCII)

```
                                                                    [Exception Subprocess: from Day 3.2]
                                                                          ▲
                                                                          │
                                                                    (thrown exception)
                                                                          │
HTTPS Sender (/http/orderhub/orders/<initials>)
    │
    ▼
Content Modifier  «set inbound headers»
    set headers: correlationId        = generate UUID if missing
                 orderId               = $.orderId from JSON body
                 X-Order-Format        = 'json' (or detect from Content-Type)
                 X-Idempotency-Key     = pass-through from HTTP header
    │
    ▼
Script: roiam_requireIdempotencyKey      ← rejects with 400 if key absent
    │
    ▼
Router  «branch on ${property.rejectAtSender}»
    │
    ├─ 'true' ──► End  (returns 400 body to caller)
    │
    └─ default ─►
    │
    ▼
Script: roiam_logIncoming               (from sc_<initials>_OrderHubHelpers)
    │
    ▼
Data Store Get
    Store:  ds_<initials>_OrderIdempotency
    Key:    ${header.X-Idempotency-Key}
    Throw Exception on Failure: No
    Output Body: As Body
    │
    ▼
Router  «branch on ${header.SAP_DatastoreEntryFound}»
    │
    ├─ 'true' ──► Content Modifier (Camel response code = 202)
    │             └─► End  (body already contains cached envelope)
    │
    └─ default ─►
    │
    ▼
Number Range step
    Range:  nr_<initials>_OrderSequence
    Target: header X-Order-Sequence
    │
    ▼
ProcessDirect Receiver  ← Day 3.3
    Address: /orderTranslator/v1/translate/<initials>
    MEP:     Request-Reply
    Allowed Headers: correlationId,orderId,X-Order-Format,X-Idempotency-Key,X-Order-Sequence
    │
    ▼   (body is now canonical XML)
    │
Script: roiam_buildResponseEnvelope
    snapshot body → property.canonicalOrderXml
    body becomes  → {"status":"accepted","orderSequence":"...","orderId":"...","correlationId":"..."}
    property.responseEnvelope = same JSON
    │
    ▼
Data Store Write
    Store: ds_<initials>_OrderIdempotency
    Key:   ${header.X-Idempotency-Key}
    Body:  current (the response envelope JSON)
    TTL:   604800 seconds (7 days)
    Overwrite: No
    Encrypt: Yes
    │
    ▼
Content Modifier  «restore canonical XML for JMS»
    body = ${property.canonicalOrderXml}
    │
    ▼
JMS Receiver  ← Day 3.2
    Queue:        roi.orderhub.outbound.<initials>
    Delivery:     Persistent
    Priority:     4
    │
    ▼
Content Modifier  «set 202 response»
    body = ${property.responseEnvelope}
    header CamelHttpResponseCode = 202
    │
    ▼
End
```

## Step order rationale

Each placement has a reason — moving any step breaks something:

| Step | Why here |
|---|---|
| `roiam_requireIdempotencyKey` first | Reject malformed callers as cheaply as possible, before any logging or store lookup |
| `roiam_logIncoming` before Data Store Get | Capture the inbound payload while it's still in the body. Get may replace the body with cached content |
| Data Store Get *before* Number Range | A cache hit shouldn't burn a sequence number. Sequence is a finite-ish resource; cache hits should be cheap |
| Number Range *before* ProcessDirect | The translator needs `X-Order-Sequence` to embed in the canonical XML |
| `roiam_buildResponseEnvelope` *after* ProcessDirect | The envelope references `X-Order-Sequence` (set by NR) and is built from headers + the success of the translation |
| Data Store Write *between* envelope build and JMS | Only cache responses we'll actually return. Caching before the translator runs would cache wishful thinking |
| JMS Receiver *after* Write | If JMS fails mid-batch, the cache is already set — replay returns the cached success. (Trade-off; alternative is move Write after JMS. See `data_store_write_config.md`) |
| Final Content Modifier | The body at this point is canonical XML (restored for JMS). Caller expects JSON envelope, so swap one more time before End |

## What's where on disk

| Artifact | Lives in |
|---|---|
| iFlow `roi_<initials>_OrderHub` | *Training* package, Integration Flow tab |
| Script Collection `sc_<initials>_OrderHubHelpers` | *Training* package, Script Collection tab |
| Data Store `ds_<initials>_OrderIdempotency` | Auto-created on first deploy; visible at *Monitor → Manage Stores → Data Stores* |
| Number Range `nr_<initials>_OrderSequence` | *Training* package, Number Range tab; visible at *Monitor → Manage Stores → Number Ranges* |
| JMS Queue `roi.orderhub.outbound.<initials>` | Auto-provisioned on first deploy; visible at *Monitor → Manage Stores → JMS Resources* |

## Idempotency happy path vs cache hit — MPL views

**Happy path (first call):**
```
HTTPS Sender → Content Modifier → roiam_requireIdempotencyKey → Router (default) →
roiam_logIncoming → Data Store Get (miss; SAP_DatastoreEntryFound=false) → Router (default) →
Number Range (ORD-0001) → ProcessDirect (translator run links via correlationId) →
roiam_buildResponseEnvelope → Data Store Write → Content Modifier →
JMS Receiver → Content Modifier → End
```

**Cache hit (replay):**
```
HTTPS Sender → Content Modifier → roiam_requireIdempotencyKey → Router (default) →
roiam_logIncoming → Data Store Get (hit; body=cached envelope; SAP_DatastoreEntryFound=true) →
Router (true branch) → Content Modifier → End
```

The cache-hit path is dramatically shorter — that's the whole point. Caller-observable behavior is identical (same 202, same envelope), but no ProcessDirect call, no Number Range burn, no JMS enqueue.

## Where to verify each artifact ran

| What | Where in MPL |
|---|---|
| Idempotency key check | Run Steps → `roiam_requireIdempotencyKey` step → Properties tab → `rejectAtSender` |
| Cache hit vs miss | Run Steps → Data Store Get → Headers tab → `SAP_DatastoreEntryFound` |
| Sequence number issued | Run Steps → Number Range → Headers tab → `X-Order-Sequence` |
| Translator round-trip | Run Steps → ProcessDirect → click through to translator run (linked by correlationId) |
| Response envelope built | Run Steps → `roiam_buildResponseEnvelope` → Attachments → `response-envelope` |
| Cache written | *Monitor → Manage Stores → Data Stores → ds_..._OrderIdempotency → Entries* — find entry by Entry ID |
| JMS published | Run Steps → JMS Receiver → success status |
