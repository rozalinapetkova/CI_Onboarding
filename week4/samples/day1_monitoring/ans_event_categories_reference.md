# ANS event categories — `roi.<iflow-stem>.<reason>` naming convention

The category (event type) determines which subscriptions fire when an event lands in ANS. Following a strict convention means one subscription = one operations workflow.

## The convention

```
roi.<iflow-stem>.<reason>
```

| Segment | Meaning | Examples |
|---|---|---|
| `roi` | Project prefix — Resilient Order Integration | Fixed |
| `<iflow-stem>` | Short identifier for the iFlow emitting the event | `orderhub`, `idmprovisioning`, `masterdatasync` |
| `<reason>` | What happened | `dlq`, `poison`, `transport`, `subscription-down` |

## Registered categories for the Order Hub

| Category | Emitted when | Severity | Action |
|---|---|---|---|
| `roi.orderhub.dlq` | Message moved to DLQ after retry exhaustion | ERROR | Email + Teams to ops |
| `roi.orderhub.poison` | Payload malformed in a way no retry can fix (parser error before idempotency check) | ERROR | Email to dev team |
| `roi.orderhub.transport` | CTM transport event (deploy, rollback, parameter change) | INFO | Email digest |
| `roi.orderhub.subscription-down` | Event Mesh subscription lost connection (Day 4.3 onwards) | WARNING | Teams + auto-ticket |
| `roi.orderhub.idempotency-storm` | >10 idempotency duplicates in 5 minutes (caller misbehaving) | WARNING | Email to dev team |
| `roi.orderhub.latency-spike` | Run time exceeds p99 baseline by 3x | WARNING | Email digest |

## How to emit from an iFlow

Day 4.4 implements the actual emit step. Conceptually:

```groovy
import com.sap.it.api.asdk.runtime.HttpClientFactory;
import groovy.json.JsonOutput;

// Build the event body per ANS schema
def event = [
    eventType: "roi.orderhub.dlq",
    severity: "ERROR",
    category: "ALERT",
    subject: "Order Hub message escalated to DLQ",
    body: "correlationId=${correlationId}, orderId=${orderId}, attempts=${attempts}",
    resource: [
        resourceName: "roi_${initials}_OrderHub",
        resourceType: "iFlow",
        resourceInstance: "${tenantName}"
    ],
    tags: [
        correlationId: correlationId,
        orderId: orderId
    ]
];

def httpClient = new HttpClientFactory().newHttpClient();
// POST to ANS producer endpoint with OAuth2 — credential alias 'ans-producer'
// (Trainer pre-wires the credential and the OAuth Receiver in the iFlow editor.)
```

Don't hand-build this in Day 4.1 — the lab uses ANS's *Send Test Event* button.

## What goes in `tags` vs `body`

| Where | Use for |
|---|---|
| `tags` | Filterable values — `correlationId`, `orderId`, `customerId`. Subscriptions can match on these |
| `body` | Free-form human-readable context — message details, exception summary, retry count |
| `subject` | One-line summary for emails / Teams cards |

Don't put PII in `body` if the email destination is broader than the people allowed to see it. Tags are subject to the same rule — they ride along with every routed event.

## Anti-pattern: one giant category

Don't emit `roi.orderhub.error` for everything. The subscription filter is the only knob operations has — if every event is the same category, the only filter left is keyword matching on `body`, which is fragile.

**Right:** four narrow categories, four subscriptions, four action sets if needed.
**Wrong:** one mega category, one subscription, one inbox drowning in mixed alerts.

## Cross-iFlow consistency

When you build a second iFlow (`roi_<initials>_OrderHubConsumer`), it gets its own stem in the category:

- `roi.orderhubconsumer.dlq` — consumer-side DLQ event
- `roi.orderhub.dlq` — producer-side DLQ event

This lets operations route consumer and producer events independently. Helpful when one team owns the producer and another owns the consumer.

## Registering new categories

There's no central registry in ANS itself — categories are free strings. The project's registry is **this file plus the iFlow's changelog entry that introduces the new category**. Before adding a new category:

1. Confirm it doesn't overlap with an existing one. `roi.orderhub.error-generic` is a smell.
2. Document in this file's table.
3. Add to the iFlow changelog.
4. Tell the operations team — they may want a subscription before you start emitting.
