# AMQP vs JMS — what's different in practice

You used the **JMS adapter** in Week 3 to put messages onto a CI-internal broker queue. You're now using the **AMQP adapter** to receive from Event Mesh. They feel similar but are different beasts.

## Side-by-side

| Aspect | JMS (CI broker) | AMQP (Event Mesh) |
|---|---|---|
| **Broker location** | CI tenant-internal | External BTP service (Event Mesh) |
| **Wire protocol** | OpenWire / proprietary | AMQP 1.0 (OASIS standard) |
| **Counted toward metering** | No | Sender flow: yes; Subscriber: no (verify your plan) |
| **Auth** | Internal — no creds needed in iFlow | Client credentials via Security Material |
| **Destination naming** | Flat queue name, e.g. `roi.orderhub.queue` | `queue:my-queue` or `topic:my-topic` |
| **Topic support** | No (CI's JMS is queue-only) | Yes — publish-subscribe with multiple consumers per topic |
| **Durable subscription concept** | Always durable (it's a queue) | Configurable — must explicitly choose Durable |
| **QoS** | At-Least-Once, EOIO available | At-Least-Once (typical), some setups can do EO |
| **Retry / DLQ** | Configured on the JMS adapter, broker-side | Configured on AMQP adapter AND on broker (Event Mesh queue settings) |
| **Cross-tenant visibility** | Only this tenant | Event Mesh can be shared across tenants and even non-SAP systems |
| **Subscription "name" identity** | N/A (the queue IS the identity) | Subscription Name is broker-side identity; renaming abandons backlog |
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

## What "Subscription Name" means in AMQP

Concept absent from JMS. Important enough to deserve its own callout:

- A **subscription** is a stateful registration with the broker that says "deliver matching events to this consumer."
- The **Subscription Name** is the broker-side identifier for that registration.
- If the consumer disconnects, the broker holds undelivered events under the Subscription Name.
- When the consumer reconnects with the same Subscription Name, delivery resumes from where it left off.
- If the consumer reconnects with a **different** Subscription Name, the broker treats it as a fresh subscription. The old backlog is orphaned on the broker — eventually cleaned up by the broker's retention policy.

For the Order Hub: Subscription Name is `roi-orderhub-salesorder-v1`. **Never rename it during the iFlow's lifetime.** If you must (e.g., schema-breaking change requires a v2 subscription), follow a planned migration: bring up v2 alongside v1, drain v1 to zero depth on the broker, then remove v1.

## Acknowledgement modes — what each means for retry

| Mode | What happens on failure |
|---|---|
| **Auto-Acknowledgement** | Broker acknowledges as soon as it delivers. If your iFlow crashes mid-processing, the event is lost. **Don't use** in production. |
| **Client Acknowledgement** | CI sends ACK only when the iFlow run completes successfully. If the run fails, broker re-delivers. **Use this.** |
| **Manual** | Your script explicitly sends ACK. Very rare; use Client Acknowledgement instead. |

Client Acknowledgement is the default and the correct choice. It implies at-least-once delivery: duplicates can happen if the iFlow processes the message but crashes before the ACK lands. Hence: idempotency is mandatory.

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
