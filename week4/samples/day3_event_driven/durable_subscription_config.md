# Durable queues — how they actually work, and what the AMQP adapter actually configures

The single most important property here is whether the queue is **durable**. Get it wrong and silent message loss is guaranteed. This doc covers what durability actually means, where it's actually set, every real field on the AMQP Sender adapter, and what recovery looks like.

## What "durable" means at the broker level

When your iFlow's AMQP Sender adapter connects to a queue in Event Mesh:

- **Non-durable queue**: the broker delivers events that arrive *while a consumer is connected*. If nothing is connected, events that arrive are dropped (or routed elsewhere if there are other subscribers).
- **Durable queue**: the broker persists events regardless of whether a consumer is currently connected. Disconnect, and events keep accumulating; reconnect, and you get everything that piled up.

For production iFlows: **always durable**. Non-durable is only useful for ephemeral monitoring/debugging consumers.

**Where this is set: the Event Mesh cockpit, at queue-creation time — not the CPI adapter.** Durability is a property of the queue itself. The CPI AMQP Sender adapter just points at a queue by name; it has no field for choosing durability, because that decision was already made when the queue was created.

## Every real field on the AMQP Sender adapter

| Field | Recommended value | Why |
|---|---|---|
| **Connection > Credential Name** | `event_mesh_amqp_<your_initials>` (Security Material alias) | Decouples credential rotation from iFlow code |
| **Connection > Queue Name** | `roi-orderhub-salesorder-created-<your_initials>` | The durable queue the trainer already created in Event Mesh cockpit, bound to the topic |
| **Processing > Number of Concurrent Processes** | `1` for the lab; `5` for production | More concurrency = more throughput, but harder to reason about ordering |
| **Processing > Max. Number of Prefetched Messages** | Default | How many messages the adapter fetches ahead of processing them |
| **Processing > Consume Expired Messages** | Off (default) | Whether to process messages the broker has marked expired |
| **Processing > Max. Number of Retries** | `5` | Re-deliver up to 5 times before giving up on the message |
| **Processing > Delivery Status After Max. Retries** | `REJECTED` | What the adapter tells the broker once retries are exhausted. **Never `MODIFIED_FAILED_UNDELIVERABLE`** — SAP's own guidance says it's unsupported and can cause processing errors. |

There is no Subscription Name, Subscription Type, or Acknowledgement Mode field. Those don't exist on this adapter.

## The queue name IS the identity

Unlike some AMQP implementations that separate "queue" from "subscription," CPI's AMQP Sender simply consumes from the named queue. There's no separate subscription registration to track, rename, or lose — the queue itself, and its durability, is the whole story.

| Action | Effect |
|---|---|
| Deploy pointing at `roi-orderhub-salesorder-created-<your_initials>` | Adapter starts consuming; any backlog already on the durable queue starts draining |
| Undeploy the iFlow | Nothing consumes the queue; events keep accumulating (because the queue is durable) |
| Redeploy pointing at the **same** Queue Name | Resumes draining exactly where it left off |
| Redeploy pointing at a **different** Queue Name | You're now consuming a different queue entirely — the original queue's backlog is untouched, just nothing is reading it |
| Delete the queue itself in Event Mesh cockpit | All accumulated events are lost. The trainer's queue has deletion protection; production should too |

The practical rule: **treat Queue Name as a stable contract with the broker, not something to casually change.** If you genuinely need a breaking change (schema-incompatible payload, for example), stand up a new queue bound to a new topic version, migrate consumers deliberately, and drain the old queue before removing it.

## Acknowledgement — automatic, not a setting

There's no acknowledgement-mode dropdown to choose. What actually happens: the adapter acknowledges a message to the broker when the iFlow run that consumed it completes successfully. If the run fails, no acknowledgement is sent, and the broker redelivers according to Max. Number of Retries. Some AMQP implementations expose this as a manual auto-ack-vs-client-ack choice — on this adapter, it's simply how it works, not a setting you pick.

## Maximum Retries — what happens at the limit

When the iFlow run fails, the broker redelivers, up to `Max. Number of Retries` times:

1. First attempt: run #1 fails (adapter doesn't acknowledge).
2. Broker redelivers after backoff. Attempt #2 fails.
3. ... up to the configured retry count fails.
4. After that, the adapter reports `Delivery Status = REJECTED` to the broker. What happens next depends on config that lives **entirely on the Event Mesh broker side, not the CPI adapter**:
   - Event Mesh calls this a **Dead Message Queue**, not "DLQ" — different product, different term for the same idea. It's a **genuinely separate queue object** — you have to explicitly create it yourself; it isn't auto-provisioned, and it isn't just a status label on the original queue.
   - Two fields directly on the queue's own properties: **Max Redelivery Count** and **Dead Message Queue** (holds the name of the queue that should receive dead messages). Confirmed directly on the real `roi-orderhub-salesorder-created-<your_initials>` queue — both fields sit right on the queue's main property list, no extra "Advanced Settings" navigation needed.
   - **The Dead Message Queue field alone isn't a safety net.** SAP's own docs are explicit: *"If the DMQ doesn't exist, discarded messages are deleted."* Naming a queue there without actually having created it doesn't leave messages stuck somewhere recoverable — it silently deletes them.
   - SAP's own recommendation: give every queue that needs one its own dedicated DMQ, named `<queue-name>_dmq`, actually created as a real queue, rather than sharing one DMQ across queues or just naming one without creating it.

**Verify before relying on this — don't assume it's wired up.** On the real `roi-orderhub-salesorder-created-<your_initials>` queue, Max Redelivery Count currently shows `0`. Whatever `0` actually means for this field (unlimited redelivery, or immediate dead-lettering on first failure) and whether the Dead Message Queue field is even populated needs confirming directly on the queue before treating dead-lettering as something this lab can rely on out of the box.

## Recovery scenarios

| Scenario | What happens |
|---|---|
| iFlow undeployed for 5 min during a transport | Events accumulate on the durable queue. Redeploy resumes draining. No loss. |
| Dev tenant restarted overnight | Broker connection drops, adapter reconnects, draining resumes. No loss. |
| Event Mesh service restarted | Same broker instance after restart; queue state persists. No loss. |
| Event Mesh credentials rotated | Adapter fails authentication until Security Material is updated with new credentials. Events accumulate on the queue in the meantime — no loss, just delayed processing. |
| Queue deleted by ops in cockpit | All accumulated events are lost. The trainer's queue has deletion protection; production should too. |
| iFlow upgraded to a new version, same Queue Name | Seamless — the broker has no concept of iFlow versions, only queues. |
| Schema-breaking change in the event payload | Each delivery causes the iFlow to fail (parse error). After Max Retries, the message goes to DLQ. Fix the iFlow or roll back; the DLQ is your safety net. |

## Verifying durability is actually on

You'd be amazed how many "I made it durable" turn out not to be, on closer inspection. To verify: **check the queue itself in the Event Mesh cockpit** — Service instance → Queues → `roi-orderhub-salesorder-created-<your_initials>` → its properties will show whether it's durable. This isn't something the CPI adapter side can tell you, since it isn't configured there.

**Provoking the failure mode (Day 4.3 lab section "Failure cases"):**
- Undeploy the iFlow.
- Send a test event.
- Redeploy.
- If the event is processed → the queue is durable ✓
- If the event is gone forever → it isn't ✗ (check the queue's settings in Event Mesh cockpit)

## Queue depth — when to alert

The queue depth (number of events waiting to be processed) is a key metric:

| Depth | Meaning |
|---|---|
| 0 most of the time | Healthy — consumer keeps up with producer |
| Briefly elevated (under 100) during business hours | Normal — burst |
| Continuously climbing | Consumer is slower than producer — investigate iFlow performance |
| Stuck at a number > 0 with no consumption | Consumer is offline or its connection is broken |

For the Order Hub: the trainer pre-configures a Cloud ALM alert when queue depth > 500 for 5 minutes (Day 4.1 alerting tied to this Day 4.3 mechanism).
