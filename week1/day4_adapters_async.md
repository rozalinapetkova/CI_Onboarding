# Day 1.4 — Adapters Part 2: Async / File / Internal

> **Goal of the day.** Cover the remaining major adapter family — SFTP, IDoc, JDBC, JMS, ProcessDirect — and finish your Customer Echo Service by adding a ProcessDirect hop to a logger iFlow plus a Data Store write. By Friday demo it should be functionally complete.

## 1. Polling vs. push — the sender mental model for async

Asynchronous senders come in two shapes:

- **Polling-based** — the iFlow itself wakes up at intervals and *checks* the source. The source is passive. Examples: SFTP, Mail.
- **Push-based** — the external system *calls* the iFlow's exposed endpoint. The iFlow is passive between calls. Examples: HTTP, OData, AMQP-with-server-push.

The choice has operational consequences: polling burns runs even when there is nothing to do; push depends on the external system being reachable.

## 2. SFTP adapter — the file-transfer workhorse

**Sender (polling).** Configuration items that bite people:

- **Read Lock Strategy** — how does the adapter know a file is *complete* and not still being written by the sender? Options:
  - *None* — pick up immediately. Risk: half-written files.
  - *Content Change* — wait until size stops changing for N seconds. Safe but latency-adding.
  - *Done File Expected* — only pick up `foo.csv` when `foo.csv.done` exists. Most reliable; requires sender cooperation.
  - *Rename* — pick up only `*.RDY` files; sender renames after writing.
- **Post-Processing** — what to do after successful processing:
  - *Delete* (default).
  - *Keep + Mark* (move to processed/, optional).
  - *Keep + Reprocess* (re-pick on every poll — useful for dev testing only).
  - *Move* (to a target folder).
- **Idempotent Repository** — to prevent re-processing of the same file across polls or workers, the adapter records what it has processed. *Database* is **required** for multi-node setups; *In-Memory* is fine for dev only.
- **Max Messages per Poll** — default 20, max 500. Tune carefully — high values starve the worker.

**Receiver.** Dynamic via headers / properties:
- `CamelFileName` — overrides the target filename.
- `SAP_FtpTimeout`, `SAP_FtpMaxReconnect`, `SAP_FtpMaxReconDelay`, `SAP_FtpStepwise`, `SAP_FtpCreateDir`, `SAP_FtpFlattenFileName`, `SAP_FtpAfterProc` — all runtime-tunable per message.

## 3. IDoc adapter — talking to ABAP, the SAP-CI way

In CI, IDocs flow over **SOAP**, not tRFC like in PI/PO. This is a frequent confusion point for PI veterans.

- **Sender side** (S/4 sends IDocs to CI):
  - SM59 destination of type **G** (HTTP), port **443**.
  - WE20 partner profile defines what IDoc types go to which destination.
- **Receiver side** (CI sends IDocs to S/4):
  - ICF service `/sap/bc/srt/idoc` must be active.
  - SRTIDOC registration on the ABAP side.

The CI side just sees XML payloads with the IDoc structure. You don't have to know ALE administration — but the trainer should walk you through one example so you recognize a real IDoc XML when you see one.

## 4. JDBC receiver — direct database calls

For when you need to read/write a database without a wrapping API.

- Supported engines: SAP HANA, Oracle, SQL Server, PostgreSQL, MariaDB, DB2.
- Non-SAP databases require uploading the JDBC driver as an artifact.
- The payload is **XML-shaped SQL** — a special schema that describes inserts/updates/selects.

You'll mention but probably not lab JDBC today (no DB available). Just know: it exists, it works, but it ties your iFlow to a database schema, which is an architectural smell most of the time. Prefer a service over JDBC where you can.

## 5. JMS adapter — the in-broker async backbone

JMS (Java Message Service) is **the** decoupling tool inside CI.

- Uses the **SAP-managed broker only** — you cannot point JMS at an external broker.
- **Standard plan limits** (you should know these by heart):
  - **30 queues** total per tenant.
  - **9.3 GB** total storage.
  - **150 transactions / consumers / providers** total.
  - Per-queue: **300 MB, 5 transactions, 5 consumers, 5 providers**.
- Messages **>5 MB are auto-split**, max **1280 MB** per logical message.
- Headers + properties combined max **4 MB**.

JMS is **not metered** for messaging — internal hops are free.

JMS deep dive is Week 3.2. Today you only need to recognize the icon and the broker concept.

## 6. ProcessDirect adapter — the in-memory iFlow-to-iFlow connector

ProcessDirect (PD) is a *unique-to-CI* construct. It connects two iFlows running on the **same tenant** with **zero network overhead**.

- Address format: `/ProcessDirect/<endpointName>` (no leading host — it's internal).
- **Synchronous**, in-memory hand-off.
- **Headers are NOT propagated by default** — you configure an *Allowed Headers* list. This trips people up *constantly*.
- **Properties are NEVER propagated.** They are scoped to the iFlow run; the called iFlow starts fresh.
- Transactions are scoped to a single iFlow.
- **Not counted for message metering.**

**Why use ProcessDirect?**

- Reusable subflows (a logger, a validator, an enricher) that many iFlows can call.
- Composition without paying network round-trips.
- "Service-like" architecture inside one tenant.

**Why NOT use ProcessDirect?**

- You need durability — PD is in-memory; if the consumer is undeployed, the call fails immediately. Use JMS for durability.
- You need to span tenants — PD is single-tenant.
- You forgot that headers and properties don't auto-propagate, and now your downstream is missing the correlation ID. (Allow-list it.)

## 7. The producer–queue–consumer pattern (preview)

You'll do the full version of this in Week 3, but the shape is:

```
[Source] ─▶ Producer iFlow ─▶ JMS Queue ─▶ Consumer iFlow ─▶ [Target]
```

The **two iFlows** decouple completely. The producer can run when the target is down. The consumer can scale independently. Failures in one don't bubble synchronously into the other.

Today you'll do a *toy* version of this with **ProcessDirect** instead of JMS — same shape, no durability, but enough to grasp the producer/consumer split.

---

## Hands-on lab — Customer Echo Service: the producer/consumer split

> Time: ~3 hours. Goal: split the Echo Service into two iFlows, where the main iFlow does the enrichment and forwards a copy via ProcessDirect to a logger iFlow, *and* writes to a Data Store entry keyed by `<your_initials>_customerId`.

### Architecture

```
HTTPS POST ─▶ roi_CustomerEchoService (main)
                  │
                  ├─▶ enrich (Content Modifier)
                  ├─▶ Data Store Write (key=customerId)
                  ├─▶ ProcessDirect to /ProcessDirect/customerLog
                  └─▶ return enriched JSON

                                roi_CustomerLogger (consumer)
                                  ProcessDirect sender at /ProcessDirect/customerLog
                                  ─▶ MessageLog attachment "Customer received"
                                  ─▶ End
```

### Steps

1. **Create the consumer iFlow `roi_<your_initials>_CustomerLogger`.**
   - Sender: **ProcessDirect** at address `/ProcessDirect/<your_initials>_customerLog`. MEP: One-Way.
   - Inside the IP: a **Script step** is *not* required for today; instead use a Content Modifier that sets a header `X-Logged: true`.
   - End event.
   - Save → version → deploy. Wait for "Started".

2. **Open the main iFlow `roi_<your_initials>_CustomerEchoService`.**
   - Add a **ProcessDirect receiver** call:
     - Drop a *Send* step (one-way, fire-and-forget) — *not* Request-Reply, since we don't need a response.
     - Wire to a new receiver pool, adapter type **ProcessDirect**, address `/ProcessDirect/<your_initials>_customerLog`.
     - Click the adapter's *Allowed Headers* — add `correlationId, customerId` so the consumer can see them.
   - Add a **Data Store Write** step:
     - Operation: *Write*.
     - Data Store Name: `CustomerEcho`.
     - Visibility: *Integration Flow*.
     - Entry ID: `${header.customerId}` (set this header earlier in the Content Modifier — read it from the body via JSON converter or for now require the caller to send it as a header).
     - Retention Threshold: 7 days.

3. **Save → version → deploy** the main iFlow.

4. **Test.**
   ```bash
   curl -u <u>:<p> -X POST "<echo-url>" \
        -H "customerId: C-1001" -H "customerCountry: DE" \
        -H "Content-Type: application/json" \
        -d '{ "customerId": "C-1001", "name": "Acme GmbH", "country": "DE" }'
   ```
   - Hit it 3–5 times with different `customerId` values.

5. **Verify.**
   - Monitor → Message Processing → confirm both iFlow runs (the main one and the logger consumer) appear and both are *Completed*. They should share a correlation ID.
   - Monitor → Manage Stores → Data Store → `CustomerEcho` → confirm one entry per `customerId`.
   - Try replaying the same `customerId` — the Data Store will overwrite. We'll add idempotency in Week 3 so duplicates are *detected* and *rejected*.

6. **Custom-header search.**
   - Add a Groovy Script step (or extend an existing one) that registers `customerId` as a searchable MPL property:
     ```groovy
     String customerId = message.getHeaders().get("customerId") as String;
     def messageLog = messageLogFactory.getMessageLog(message);
     if (messageLog != null) {
         messageLog.addCustomHeaderProperty("customerId", customerId);
     }
     ```
   - Redeploy, send another test call, then in Message Processing search, type `customerId=C-1001`. The system finds the message by that custom header.

### Failure cases to provoke

- Undeploy `roi_<your_initials>_CustomerLogger` → call the main iFlow → main iFlow **fails immediately** with a "no consumer for ProcessDirect endpoint" error. This is the in-memory-no-durability lesson, hands-on.
- Re-deploy `roi_<your_initials>_CustomerLogger`. Try again. Should work.
- Send a request without the `customerId` header. The Data Store Write fails with a missing-key error. Inspect the *Steps* tree to see where it stopped.

---

## Reference card excerpt — Day 1.4

- Polling senders: **SFTP**, Mail. Push senders: **HTTP**, OData, AMQP.
- SFTP read locks: *None / Content Change / Done File Expected / Rename* — only the last two are safe in production.
- IDoc in CI = **SOAP** (not tRFC).
- JDBC receiver — supported engines list; non-SAP DBs need driver upload; XML-shaped SQL payload.
- JMS limits (Standard): 30 queues, 9.3 GB, 150 tx/consumers/providers; per queue 300 MB / 5 / 5 / 5; auto-split >5 MB.
- ProcessDirect: in-memory, **headers NOT propagated by default — configure Allowed Headers**, properties **never** propagated, not metered, single-tenant only.
- Producer–queue–consumer is the canonical decoupling pattern; ProcessDirect is its *non-durable* cousin.
- Custom headers must be flagged as **MPL custom header properties** to be searchable in the Monitor.
