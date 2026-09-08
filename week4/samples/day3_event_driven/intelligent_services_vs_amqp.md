# Intelligent Services vs direct AMQP — when to use which

Two ways to subscribe to events on SAP Integration Suite. They're not competitors — they're different doors into the same hallway (Event Mesh). Choosing the right door saves hours.

## What each is

**Intelligent Services** — a curated catalog inside Integration Suite that lists events SAP applications publish (S/4HANA Cloud, SuccessFactors, Field Service, Concur, IBP). For each event, it provides:
- The schema (auto-imported, no copy-paste).
- A "Subscribe" wizard that creates the AMQP subscription with sensible defaults.
- A managed relationship — if SAP changes the event schema, the catalog updates and you get notified.

**Direct AMQP adapter** — you drag an AMQP sender onto your iFlow, configure the queue name, subscription name, credentials yourself. You're responsible for knowing the topic name, the schema, and the auth setup.

Both end up doing the same thing at runtime: AMQP subscription to Event Mesh. Intelligent Services is a wizard on top; direct AMQP is the raw building block.

## Side-by-side

| Aspect | Intelligent Services | Direct AMQP |
|---|---|---|
| **UI** | Catalog with search, schema preview, "Subscribe" button | Drag adapter, fill fields manually |
| **Schema** | Auto-imported, kept in sync with producer | You import/copy yourself |
| **Topic discovery** | Pick from list | You have to know the topic name |
| **Auth setup** | Pre-wired to the bound Event Mesh instance | You configure Security Material credentials yourself |
| **Multi-tenant** | Each subscription per tenant — limited cross-tenant tricks | Configure any AMQP endpoint you have credentials for |
| **Wildcards** | Not exposed in the wizard | Fully supported |
| **Custom producers** | Not available — only SAP-cataloged events | Works for any AMQP producer |
| **Versioning visibility** | Catalog shows event-type versions side-by-side | You read the topic name to know which version |
| **Schema validation** | Implicit (the catalog publishes it) | You import the schema and validate explicitly in script |
| **Change traceability** | Shows when SAP last updated the event schema | Manual — you check producer docs |
| **What's logged in MPL** | Standard adapter logs + catalog metadata | Standard adapter logs |

## When to use Intelligent Services

| Scenario | Why IS wins |
|---|---|
| Subscribing to an S/4HANA Cloud event for the first time | Wizard handles auth, schema, queue creation in one flow |
| You need the official schema for code generation | IS exposes it; raw AMQP doesn't |
| Cohort training — first event subscription in the curriculum | The wizard hides complexity; learners focus on the iFlow logic |
| You want to be notified when the event schema evolves | Catalog tracks producer-side changes |
| Subscribing to events from SuccessFactors, Field Service, Concur, IBP | Same wizard pattern across SAP cloud products |

## When to use direct AMQP

| Scenario | Why direct AMQP wins |
|---|---|
| Producer is custom or third-party (not in the catalog) | IS doesn't help; you need raw AMQP |
| You need wildcard subscriptions | Wizard doesn't expose wildcards |
| You're subscribing to a non-SAP AMQP broker (Azure Service Bus, ActiveMQ, RabbitMQ) | IS only covers SAP-managed Event Mesh |
| You want explicit control over queue naming for ops visibility | Wizard auto-names; you may want a specific name |
| The event flows through multiple Event Mesh instances (cross-tenant federation) | Wizard's per-tenant model doesn't fit |
| You want to understand the mechanics — training scenarios past introductory | Direct AMQP teaches what's actually happening |

## For the Order Hub — why we chose direct AMQP

The Day 4.3 lab uses **direct AMQP** even though `SalesOrder.Created` is in the Intelligent Services catalog. Three reasons:

1. **Teaching value.** The wizard hides the queue, the subscription name, the acknowledgement mode — exactly the things you need to understand for production debugging. After you've done direct AMQP once, the wizard becomes a quality-of-life shortcut rather than a magic box.
2. **Wildcard preparation.** Stretch goal: subscribe to `SalesOrder/+/v1` for both Created and Changed. The wizard doesn't expose this; direct AMQP does.
3. **The pattern transfers.** Once you understand direct AMQP, subscribing to non-SAP events (a partner's RabbitMQ, an internal Mule producer) reuses the same skills.

In a real production rollout where you're subscribing to dozens of S/4 events, **use Intelligent Services**. The schema-tracking alone pays for itself the first time S/4 changes a field name.

## Migration between the two

You can switch later. If you start with Intelligent Services and need wildcards or cross-tenant federation:

1. Note the queue name and subscription name the wizard created — they're visible in the AMQP adapter properties on the iFlow.
2. Delete the iFlow's IS-subscription step.
3. Add a direct AMQP sender, point at the same queue and subscription name. The broker doesn't care which side of the adapter UI you came from — it sees the same AMQP client.
4. Test with a replayed event from a paused subscription, verify it still works.

Going the other direction (direct AMQP → IS) is harder because IS owns the queue naming; you'd let IS create a new queue and migrate the binding in Event Mesh cockpit.

## Common mistakes

| Mistake | Symptom |
|---|---|
| Using IS for a non-SAP producer | Wizard doesn't find your event; you give up and switch to direct AMQP anyway — wasted time |
| Using direct AMQP for an SAP event when IS would do | Manually copying schema, manually tracking version bumps, future-you cursing past-you |
| Mixing both in one iFlow without coordination | Two AMQP adapters on the canvas, confusing for the next reader. Pick one entry method per event source. |
| Assuming IS schema is always up-to-date | It mostly is, but SAP's catalog occasionally lags producer updates by days. For new events, verify by sending a test event before relying on the schema |

## Decision flowchart

```
Is the event producer an SAP cloud app in the catalog?
   |
   YES → Do you need wildcards or cross-tenant federation?
   |       |
   |       NO  → Use Intelligent Services
   |       YES → Use direct AMQP
   |
   NO  → Use direct AMQP
```

Two questions, three decision points. That's the whole framework.
