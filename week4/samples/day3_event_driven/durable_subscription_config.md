# Durable subscription — adapter config and recovery semantics

The single most important setting on the AMQP adapter is **Durable**. Get it wrong and silent message loss is guaranteed. This doc covers what the setting does, every related field on the adapter, and what recovery looks like in each combination.

## What "durable" means at the broker level

When a consumer (your iFlow) connects to Event Mesh and says "I want events on this queue":

- **Non-durable subscription**: the broker delivers events that arrive *while you're connected*. If you disconnect, the broker forgets you ever subscribed. Events that arrive while you're away are dropped (or routed to other subscribers if any).
- **Durable subscription**: the broker remembers you under a **Subscription Name**. If you disconnect, events keep accumulating in the queue under your name. When you reconnect with the same Subscription Name, you get everything that piled up.

For production iFlows: **always durable**. Non-durable is only useful for ephemeral monitoring/debugging consumers (e.g., a developer tail).

## Every relevant field on the AMQP Sender adapter

Below are the settings on the AMQP Sender (subscriber) adapter as they appear in CI's iFlow editor. Recommended values for the Order Hub:

| Field | Recommended value | Why |
|---|---|---|
| **Connection > Credential Name** | `event_mesh_amqp` (Security Material alias) | Decouples credential rotation from iFlow code |
| **Connection > Address Type** | `Queue` | Always queue; Event Mesh routes topic→queue, your iFlow consumes from queue |
| **Connection > Address Name** | `roi-orderhub-salesorder-created` | The queue created by the trainer in Event Mesh cockpit |
| **Connection > Reconnect** | `Yes` | If the broker drops the connection, reconnect automatically |
| **Processing > Number of Concurrent Processes** | `1` for the lab; `5` for production | More concurrency = more throughput, but harder to reason about ordering |
| **Processing > Acknowledgement Mode** | `Client Acknowledgement` | ACK only after iFlow run succeeds; failures cause re-delivery |
| **Processing > Subscription Type** | `Durable` | Survive consumer downtime |
| **Processing > Subscription Name** | `roi-orderhub-salesorder-v1` | Stable identity — never rename mid-lifetime |
| **Processing > Maximum Retries** | `5` | Re-deliver up to 5 times before failing the message |
| **Processing > Backoff (between retries)** | `5000` ms (5 seconds), exponential | Avoid hammering a flaky downstream |
| **Selectors > Selector** | (empty for the Order Hub) | Filter messages by header equality. Empty = receive everything from the queue |

## Subscription Name — the identity that must never change

This is the single sharpest edge of AMQP.

| Action | Effect |
|---|---|
| Deploy with name `roi-orderhub-salesorder-v1` first time | Broker creates durable subscription `roi-orderhub-salesorder-v1` and starts accumulating events |
| Undeploy iFlow | Subscription remains on the broker; events accumulate |
| Redeploy with the **same** name | Resume from where you left off — drain the backlog |
| Redeploy with a **different** name `...-v2` | Broker treats it as a fresh subscription with empty backlog. The events that accumulated under `...-v1` are stuck there until the retention policy purges them |
| Delete the iFlow | Subscription remains on the broker (you have to delete it in the Event Mesh cockpit separately if you want to free up the name) |

The rule: **treat Subscription Name as a stable contract with the broker, not a configurable property of your iFlow.**

If you genuinely need a new subscription (schema-breaking change for example), follow the v1/v2 migration pattern:

1. Bring up `roi-orderhub-salesorder-v2` alongside v1 in a parallel iFlow.
2. Verify v2 processes correctly on test events.
3. Stop the producer from generating new events to v1 (or accept that v1's tail will be processed by the old iFlow).
4. Drain v1 to zero depth on the broker.
5. Undeploy v1's iFlow.
6. Delete v1 subscription from Event Mesh cockpit.

This is overkill for additive schema changes. Use it only for genuinely incompatible changes.

## Acknowledgement Mode — what each does

Already covered in `amqp_vs_jms_reference.md` but worth repeating here:

| Mode | When ACK is sent | Risk on iFlow failure |
|---|---|---|
| Auto-Acknowledgement | Immediately on receipt by the adapter | Event is lost if iFlow crashes mid-processing — **don't use** in production |
| Client Acknowledgement | When iFlow run reaches successful end | Re-delivery on failure; idempotency is mandatory |
| Manual | Your script explicitly calls ACK | Rare; you almost never want this complexity |

**Client Acknowledgement** is the right choice for the Order Hub.

## Maximum Retries — what happens at the limit

When the iFlow fails and Client Acknowledgement is set, the broker re-delivers. With Maximum Retries = 5:

1. First attempt: iFlow run #1 fails (broker doesn't get ACK).
2. Broker re-delivers after backoff. Attempt #2 fails.
3. ... up to attempt #5 fails.
4. After the 5th failure, the broker stops re-delivering this message. What happens next depends on the **DLQ configuration** in Event Mesh:
   - If DLQ is configured: message moves to the dead-letter queue.
   - If no DLQ: message stays in the queue with a "delivery count exceeded" flag. New events behind it can still be delivered, but the poison message lingers.

For the Order Hub: trainer pre-configures a DLQ `roi-orderhub-salesorder-created.dlq` in Event Mesh. Day 4.4 wires error handling to consume from the DLQ for forensics.

## Recovery scenarios

| Scenario | What happens |
|---|---|
| iFlow undeployed for 5 min during a transport | Events accumulate in the queue under the durable subscription. Redeploy resumes drain. No loss. |
| Dev tenant restarted overnight | Broker connection is dropped, adapter reconnects, durable subscription resumes. No loss. |
| Event Mesh service restarted | Broker is the same instance after restart. Subscription state persists. No loss. |
| Event Mesh credentials rotated | Adapter fails authentication. No events processed. Re-deploy with new credentials in Security Material to resume. Events accumulated during the outage drain on resume. No loss but delayed processing. |
| Queue deleted by ops in cockpit | All accumulated events are lost. The trainer's queue is configured with deletion protection; in production you'd want the same. |
| Subscription name renamed in iFlow | New subscription with empty backlog; old subscription's events are orphaned on the broker. Loss until retention purge. **Avoid.** |
| iFlow upgraded to a new version | Same Subscription Name → seamless. The broker doesn't know your iFlow versioned. |
| Schema-breaking change in the event payload | Each delivery causes the iFlow to fail (parse error). After Max Retries, message goes to DLQ. You fix the iFlow or roll back. The DLQ is your safety net. |

## Verifying durability is actually on

You'd be amazed how many "I configured Durable" turn out to be Non-Durable on closer inspection. To verify:

**In the iFlow editor:**
- AMQP Sender adapter → Processing tab → Subscription Type should show `Durable`. Subscription Name should be filled in.

**In Event Mesh cockpit:**
- Service instance → Queues → click `roi-orderhub-salesorder-created` → Subscribers tab.
- Each connected consumer shows its Subscription Name. If you see your iFlow listed with the expected name, it's durable. If the subscription disappears as soon as you undeploy the iFlow, it was non-durable.

**Provoking the failure mode (Day 4.3 lab section "Failure cases"):**
- Undeploy the iFlow.
- Send a test event.
- Redeploy.
- If the event is processed → durable ✓
- If the event is gone forever → non-durable ✗

## Subscription depth — when to alert

The queue depth (number of events waiting to be processed) is a key metric:

| Depth | Meaning |
|---|---|
| 0 most of the time | Healthy — consumer keeps up with producer |
| Briefly elevated (under 100) during business hours | Normal — burst |
| Continuously climbing | Consumer is slower than producer — investigate iFlow performance |
| Stuck at a number > 0 with no consumption | Consumer is offline or its connection is broken |

For the Order Hub: trainer pre-configures a Cloud ALM alert when queue depth > 500 for 5 minutes (Day 4.1 alerting tied to this Day 4.3 mechanism).

## Settings that look similar but are different

| Setting | Where | What |
|---|---|---|
| **Subscription Name** | AMQP adapter, Processing tab | Broker-side identity of the subscription |
| **Container ID** | AMQP connection (auto-generated unless overridden) | Identifies the AMQP client; usually unique per connection, doesn't need to match Subscription Name |
| **Queue Name** | AMQP adapter, Connection tab > Address Name | The queue the iFlow consumes from |
| **Topic name** | Event Mesh cockpit, queue's binding | The topic the queue is bound to |

Subscription Name is *not* the queue name. Two iFlows can both consume from `roi-orderhub-salesorder-created` queue with different Subscription Names — each gets independent delivery state. (Whether you should do this is a design question; usually no.)
