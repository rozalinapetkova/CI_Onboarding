# EOIO via JMS serialization key — when, why, why not

EOIO = **Exactly Once In Order**. Not a checkbox you flip — a discipline you apply only when ordering is a business requirement.

## What "serialization key" actually does

A JMS sender adapter can declare a **Serialization Key** expression (typically a header value). The broker then enforces:

- Messages with the **same key value** are delivered to the consumer **strictly in arrival order**, one at a time.
- Messages with **different key values** can be delivered concurrently.

This is *partitioned* in-order delivery. Each key is its own ordered partition; partitions are independent.

Example: serialization key = `${header.customerId}`.

| Order arrival | customerId | Processing order |
|---|---|---|
| 1 | ACME | ACME-1 must finish before ACME-2 starts |
| 2 | ACME | ACME-2 starts when ACME-1 completes |
| 3 | GLOBEX | GLOBEX-1 can run in parallel with the ACME chain |
| 4 | ACME | Queued behind ACME-2 |
| 5 | GLOBEX | Queued behind GLOBEX-1 |

## When EOIO is the right answer

| Scenario | Why EOIO |
|---|---|
| Order then Cancellation arriving back-to-back for the same customer | Cancellation must process *after* the Order it cancels. Out-of-order = NPE on the downstream |
| Inventory increment + decrement on the same SKU | Order matters arithmetically (depending on starting stock) |
| Bank transactions with running balance | Strictly ordered per account |
| State-machine events per entity (Created → Updated → Closed) | Closed before Created = downstream rejection |

In each: the **partition key** is the entity that owns the order (`customerId`, `SKU`, `accountId`, `entityId`).

## When EOIO is the WRONG answer

| Scenario | Why not |
|---|---|
| Independent orders from different customers | They're already independent — adding a serialization key per customer is redundant for "every order has its own customerId" cases. Throughput drops with no benefit |
| Notifications that are idempotent and order-irrelevant | "Order arrived" notifications can land in any order |
| Audit/log events | Aggregation tolerates out-of-order |
| The Order Hub lab | Each `orderId` is independent — no two messages share a key naturally |

**For the Day 3.2 Order Hub lab: do not use EOIO.** It would cap throughput at one message per `orderId` partition — fine in principle, but the lab doesn't need it and adding it obscures the JMS basics being taught.

## Cost of EOIO

| Cost | Impact |
|---|---|
| **Throughput cap per partition** | One in-flight message per key. If one customer suddenly sends 1000 orders, they queue behind each other while other customers' orders process freely |
| **Stuck-key blocking** | If ACME-1 fails and goes into retry, ACME-2 waits the full retry window. ACME messages back up; GLOBEX is unaffected |
| **Access Type interaction** | EOIO + Access Type = Exclusive = single-threaded everything (redundant combination). Avoid combining unless absolutely necessary |
| **DLQ semantics** | A Bypass'd ACME-1 lands in DLQ; ACME-2 then processes — meaning the entity's strict order is *already broken*. The downstream must handle that |

The last cost is the subtle one: **EOIO is best-effort under failure**. The moment a message lands in DLQ, "strict order" is past tense for that partition. Downstream consumers of EOIO queues must still be resilient to gap recovery.

## Where it's set

Cockpit: JMS sender adapter → *Processing* tab → *Serialization Key* field.

Expression form, e.g.:
- `${header.customerId}`
- `${property.partitionKey}`
- Constant value (useless — collapses everything to one partition = global single-thread)

## Alternative — SOAP SAP RM

The other EOIO option in SAP CI is the **SOAP SAP RM** adapter — gives EOIO with a 90-day duplicate-detection window. Different protocol entirely (SOAP, not HTTP/JMS). Use only when the partner explicitly requires SAP-Reliable-Messaging semantics. Mentioned for awareness; out of scope for this lab.

## Two-sentence defence — example

> Q: We use JMS for the Order Hub. Should we add EOIO with a `customerId` key?
>
> A: Only if "two orders from the same customer must process in arrival order" is a business requirement — which for the Order Hub it isn't, orders are independent per `orderId`. Adding EOIO would cap throughput per customer and add stuck-key risk during retries, both for no payoff.
