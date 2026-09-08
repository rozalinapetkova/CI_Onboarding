# S/4HANA Cloud topic naming — convention and wildcards

Topic names on Event Mesh are slash-separated paths. SAP S/4HANA Cloud publishes events under a strict convention; knowing the shape lets you predict and subscribe with confidence.

## The convention

```
s4/sap/s4hanacloud/ce/<bounded-context>/v1/<EntityName>/<Verb>/v1
```

Read it left to right:

| Segment | Meaning | Why fixed |
|---|---|---|
| `s4` | Product family root | Distinguishes from SuccessFactors (`sf/...`), Field Service (`fsm/...`), etc. |
| `sap` | Vendor namespace | Reserved for SAP-published events |
| `s4hanacloud` | Product | Differentiates S/4HANA Cloud from on-prem S/4HANA |
| `ce` | CloudEvents | Indicates the payload follows CloudEvents spec |
| `<bounded-context>` | Business domain | `sales`, `finance`, `master`, `procurement`, `logistics`, `manufacturing` |
| `v1` | Context version | Bumps if the bounded-context boundaries get redrawn (rare) |
| `<EntityName>` | Business object | `SalesOrder`, `InvoiceDocument`, `BusinessPartner`, `PurchaseOrder` |
| `<Verb>` | What happened | `Created`, `Changed`, `Cancelled`, `Posted`, `Released` |
| `v1` | Event payload version | Bumps when the event schema changes incompatibly |

## Concrete examples

| Topic | What it fires on |
|---|---|
| `s4/sap/s4hanacloud/ce/sales/v1/SalesOrder/Created/v1` | New sales order saved |
| `s4/sap/s4hanacloud/ce/sales/v1/SalesOrder/Changed/v1` | Existing sales order modified |
| `s4/sap/s4hanacloud/ce/sales/v1/SalesOrder/Cancelled/v1` | Sales order cancelled |
| `s4/sap/s4hanacloud/ce/finance/v1/InvoiceDocument/Posted/v1` | Customer invoice posted |
| `s4/sap/s4hanacloud/ce/finance/v1/AccountingDocument/Created/v1` | Journal entry created |
| `s4/sap/s4hanacloud/ce/master/v1/BusinessPartner/Created/v1` | New customer/vendor |
| `s4/sap/s4hanacloud/ce/master/v1/Material/Created/v1` | New material master |
| `s4/sap/s4hanacloud/ce/procurement/v1/PurchaseOrder/Released/v1` | PO released by approver |

## Wildcards in subscriptions

AMQP / Event Mesh supports two wildcards in subscription topic filters:

| Wildcard | Matches | Use when |
|---|---|---|
| `+` (plus) | Exactly one path segment | You want all verbs for one entity, or all entities in one context |
| `#` (hash) | Zero or more trailing segments | You want everything below a point in the tree |

Examples:

| Subscription pattern | Matches |
|---|---|
| `s4/sap/s4hanacloud/ce/sales/v1/SalesOrder/+/v1` | All SalesOrder lifecycle events (Created, Changed, Cancelled, ...) |
| `s4/sap/s4hanacloud/ce/sales/v1/+/Created/v1` | All "Created" events in the sales context |
| `s4/sap/s4hanacloud/ce/sales/#` | Everything in the sales bounded-context |
| `s4/sap/s4hanacloud/ce/+/v1/+/Created/v1` | All "Created" events across every business context |
| `s4/sap/s4hanacloud/#` | All S/4HANA Cloud events. **Don't.** |

## Subscribe specifically vs by wildcard — when to choose which

| Decision | Subscribe specifically | Subscribe with wildcard |
|---|---|---|
| Event volume | Predictable, low | High but you want to handle everything uniformly |
| Schema differences across verbs | Significantly different per verb | Similar shape, dispatched by `ce-type` in script |
| New verbs added later | Want the iFlow change to be a deliberate decision | Want auto-pickup |
| Failure isolation | One bad event type doesn't block others | One bad event type might poison the queue |

For the Order Hub: we subscribe **specifically** to `SalesOrder/Created/v1`. Reasons:

- The handling logic for `Created` is meaningfully different from `Changed` (Changed needs merge semantics; Created is a clean insert).
- Adding `Changed` later is a small change with its own dedicated branch.
- Wildcards make the failure-mode "one event poisons all" worse — we'd rather have separate queues per event type.

## When the convention isn't followed

Older or hand-rolled producers may not follow `s4/sap/s4hanacloud/...`. Examples seen in the wild:

| Pattern | Origin |
|---|---|
| `iflmap/...` | Older CPI/HCI broker topics, before CloudEvents standardization |
| `enterprise.event.salesorder.created` | Custom envelopes from third-party producers |
| `/Orders/Created` | Hand-rolled topics from a partner integration |

If you see one of these: don't try to "fix" the topic name on the producer side. Subscribe to it as-is. The convention is a *recommendation* for clarity; the broker doesn't enforce it.

## Listing topics in Event Mesh cockpit

In BTP cockpit → Event Mesh service instance → Service Key → open Event Mesh dashboard:

- **Topics** tab: shows topics that have been published to OR subscribed by something. Topics that exist only as a future subscription target aren't listed until something connects.
- **Queues** tab: shows queues and their bindings to topics. The Order Hub's queue `roi-orderhub-salesorder-created` is bound here to the SalesOrder/Created topic — that binding is set up in the cockpit, not in the iFlow.

## In the iFlow's AMQP sender adapter

You configure the **queue** name, not the topic:

```
Address Type: Queue
Address Name: roi-orderhub-salesorder-created
```

The topic-to-queue routing is done in Event Mesh. This means:

- Multiple queues can subscribe to the same topic — finance team's iFlow gets its own queue bound to the same `SalesOrder/Created` topic.
- One queue can be bound to multiple topics — `roi-orderhub-allsales` could subscribe to both `Created` and `Changed`.
- Changing the binding doesn't require redeploying the iFlow — change happens in Event Mesh cockpit.

This is a separation of concerns: the broker decides *what messages land in this queue*, the iFlow decides *what to do with messages that land*.

## Topic naming for events YOUR iFlow publishes

If the Order Hub publishes its own events (Week-4 stretch goal or beyond), follow the same convention with your own root:

```
roi/orderhub/<context>/v1/<EntityName>/<Verb>/v1
```

Concrete: `roi/orderhub/orders/v1/Order/Accepted/v1`, `roi/orderhub/orders/v1/Order/Rejected/v1`.

This is a project-team convention; the CNCF / SAP spec doesn't mandate root namespacing. But adopting one makes downstream subscriptions cleaner.
