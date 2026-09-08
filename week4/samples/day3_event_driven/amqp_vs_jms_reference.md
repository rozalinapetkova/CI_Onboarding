# AMQP vs JMS — what's different in practice

You used the **JMS adapter** in Week 3 to put messages onto a CI-internal broker queue. You're now using the **AMQP adapter** to receive from Event Mesh. They feel similar but are different beasts.

## Side-by-side

| Aspect | JMS (CI broker) | AMQP (Event Mesh) |
|---|---|---|
| **Broker location** | CI tenant-internal | External BTP service (Event Mesh) |
| **Wire protocol** | OpenWire / proprietary | AMQP 1.0 (OASIS standard) |
| **Counted toward metering** | No | Publisher (e.g. an EventPublisher iFlow): possibly, verify your plan; Consumer (the Order Hub's AMQP entry): no |
| **Auth** | Internal — no creds needed in iFlow | Client credentials via Security Material |
| **Destination naming** | Flat queue name, e.g. `roi.orderhub.queue` | `queue:my-queue` or `topic:my-topic` |
| **Topic support** | No (CI's JMS is queue-only) | Yes — publish-subscribe with multiple consumers per topic |
| **Durable subscription concept** | Always durable (it's a queue) | Same — durability is a property of the queue, set in Event Mesh cockpit at creation, not an adapter field |
| **QoS** | At-Least-Once, EOIO available | At-Least-Once (typical), some setups can do EO |
| **Retry / DLQ** | Configured on the JMS adapter, broker-side | Configured on AMQP adapter AND on broker (Event Mesh queue settings) |
| **Cross-tenant visibility** | Only this tenant | Event Mesh can be shared across tenants and even non-SAP systems |
| **Subscription "name" identity** | N/A (the queue IS the identity) | Same here — the queue IS the identity on this adapter too; there's no separate subscription-name field |
| **Throughput ceiling** | Tens of thousands/sec | Lower — Event Mesh charges per message |

## When to use which

| Need | Choose |
|---|---|
| Buffering between two iFlows in the same tenant | JMS |
| Decoupling producer rate from consumer rate, within CI | JMS |
| Subscribing to events from S/4HANA Cloud | AMQP (Event Mesh) |
| Receiving events from non-SAP systems via Event Mesh | AMQP |
| Publishing events for other systems (SAP or not) to consume | AMQP |
| High-volume internal message handoff | JMS (cheaper, faster) |
| Long-term integration with the broader SAP event ecosystem | AMQP |
| Want pub-sub (multiple consumers) of the same message | AMQP (topics) |

The Order Hub uses **both**:
- AMQP at the entry (subscribe to S/4 events).
- JMS in the middle (decouple producer from consumer iFlows).

This is the standard pattern: AMQP for external eventing, JMS for internal queueing.

## What identifies a consumer in AMQP, on this adapter

There's no separate "subscription" registration to name on CPI's AMQP Sender — unlike some AMQP client libraries that expose durable-subscription identities independent of the queue, this adapter just consumes from the queue you point it at. The queue name is the whole identity.

- If the consumer disconnects, the broker holds undelivered events on the durable **queue** — not under some separate subscription name.
- When the consumer reconnects to the same queue, delivery resumes from where it left off.
- If you point the adapter at a **different** queue, you're consuming different events entirely — the original queue's backlog just sits there, untouched, until something else drains it.

For the Order Hub: the queue is `roi-orderhub-salesorder-created-<your_initials>`. **Don't casually repoint the adapter at a different queue.** If you genuinely need a breaking change (schema-incompatible payload, for example), stand up a new queue bound to a new topic version, migrate deliberately, and drain the old one before removing it.

## Acknowledgement — automatic, not a setting

There's no acknowledgement-mode field to choose on this adapter. What actually happens: the adapter acknowledges a message to the broker when the iFlow run that consumed it completes successfully. If the run fails, no acknowledgement is sent, and the broker redelivers (governed by the adapter's Max. Number of Retries). This is effectively "client acknowledgement" behavior — it's just not a mode you select, it's simply how the adapter works.

This implies at-least-once delivery: duplicates can happen if the iFlow processes the message but crashes before completing. Hence: idempotency is mandatory.

## What you CAN'T do with the AMQP adapter

| Need | Workaround |
|---|---|
| Synchronous request-reply over AMQP (unusual pattern but supported by spec) | CI's adapter is one-way; use HTTP if you need request-reply |
| Selectors with complex predicates | Limited to simple header-equality; for complex routing, deliver everything and filter in the iFlow |
| Cross-cluster failover | Configure two AMQP credentials and switch via destination; not automatic |
| Transactional sends bundling AMQP + JMS in one tx | Not supported; two-phase commit absent. Design idempotency instead. |

## Performance implications

| Scenario | JMS | AMQP |
|---|---|---|
| In-tenant 1000 msg/sec handoff | Fine | Possibly throttled by Event Mesh plan; check |
| Polling every 5 seconds for control messages | Cheap | Costs Event Mesh quota; use sparingly |
| Bursting 10K events in a minute | Fine | Test against your plan's burst limit |
| Idle subscription, occasional message | Costs nothing | Costs the subscription "kept alive" overhead |

## Both adapters in one iFlow — pattern

The Order Hub uses this pattern:

```
AMQP Sender (subscribe to S/4 event) → ... → JMS Producer (put on internal queue)
                                                              ↓
                                  JMS Consumer iFlow (Week 3) → Receiver → OMS
```

Why two queueing technologies in sequence?

- AMQP gives us the standard event subscription contract with S/4 and other producers.
- JMS gives us cheap, fast internal handoff between the entry iFlow and the consumer iFlow.
- The hop also gives us a place to reshape the payload (CloudEvents `data` → canonical XML) before the consumer iFlow has to deal with it.

If you only had AMQP and no internal JMS, the AMQP consumer iFlow would be doing too many jobs in one place. Two queues, two jobs.
