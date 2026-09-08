# JMS — limits and decision rules

The Customer Echo Service uses **ProcessDirect** (in-memory). Day 1.4 introduces JMS for the contrast.

## JMS Standard plan limits — memorize these

| Limit | Value | What runs out first |
|---|---|---|
| Queues | 30 | Hits first on tenants with many partners — each B2B partner often gets 1–2 queues. |
| Storage | 9.3 GB | Long retention + large payloads. Sweep dead messages aggressively. |
| Transactions / consumers / providers | 150 (combined) | Producer count + consumer count + in-flight tx. Reuse iFlows across queues instead of creating one per queue. |

Exceeded any one of these and the tenant **stops accepting new JMS sends**. Not graceful — alert on 80% headroom.

## ProcessDirect vs JMS — pick one

| Question | If yes → use… |
|---|---|
| Do producer and consumer run inside the same tenant? | Either works |
| Must the consumer survive a worker crash? | **JMS** (ProcessDirect is in-memory; lost on restart) |
| Do you want retry + DLQ semantics for free? | **JMS** (configurable on the adapter) |
| Do you need fan-out (multiple consumers)? | **JMS** (pub/sub via Event Mesh is also an option) |
| Is throughput dominant and you want zero per-message metering? | **ProcessDirect** (not metered) |
| Is the producer at one rate, consumer at a different rate? | **JMS** (queue absorbs the burst) |

> Cookbook rule: **ProcessDirect for synchronous composition. JMS for durability and rate decoupling.** Don't try to make ProcessDirect carry retry semantics.

## "JMS hop is not metered"

True only for the JMS adapter itself. The receiver adapter at the *end* of the consumer iFlow (HTTPS to OMS, etc.) is metered normally. See Day 1.1 `metering_examples.md` example 2.
